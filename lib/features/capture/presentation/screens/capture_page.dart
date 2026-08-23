import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import '../../../../app/providers.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/utils/pose_alignment_engine.dart';
import '../../../../data/models/pose_landmark_point.dart';
import '../../../../data/models/pose_record.dart';
import '../../../../data/models/pose_series.dart';
import '../widgets/onion_skin_overlay_painter.dart';

class PoseCapturePage extends ConsumerStatefulWidget {
  const PoseCapturePage({
    super.key,
    required this.series,
    required this.isBaselineCapture,
    this.baselineRecord,
  });

  final PoseSeries series;
  final bool isBaselineCapture;
  final PoseRecord? baselineRecord;

  @override
  ConsumerState<PoseCapturePage> createState() => _PoseCapturePageState();
}

class _PoseCapturePageState extends ConsumerState<PoseCapturePage> {
  static const Map<String, int> _orientations = {
    'portraitUp': 0,
    'landscapeLeft': 90,
    'portraitDown': 180,
    'landscapeRight': 270,
  };

  CameraController? _cameraController;
  late final PoseDetector _streamPoseDetector;

  ui.Image? _overlayImage;
  List<PoseLandmarkPoint> _latestLandmarks = const [];
  PoseAlignmentResult _alignmentResult = const PoseAlignmentResult.empty();
  bool _initializing = true;
  bool _processingFrame = false;
  bool _capturing = false;
  bool _autoCaptureEnabled = true;
  double _autoCaptureThreshold = AppConstants.defaultAutoCaptureThreshold;
  double _overlayOpacity = AppConstants.defaultOverlayOpacity;
  DateTime? _alignmentHeldSince;
  String? _errorMessage;

  bool get _canAutoCapture {
    return !widget.isBaselineCapture &&
        widget.baselineRecord != null &&
        widget.baselineRecord!.landmarks.isNotEmpty;
  }

  @override
  void initState() {
    super.initState();
    _streamPoseDetector = PoseDetector(
      options: PoseDetectorOptions(
        model: PoseDetectionModel.base,
        mode: PoseDetectionMode.stream,
      ),
    );
    unawaited(_initializeCaptureFlow());
  }

  @override
  void dispose() {
    unawaited(_cameraController?.dispose());
    unawaited(_streamPoseDetector.close());
    super.dispose();
  }

  Future<void> _initializeCaptureFlow() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        throw StateError('No camera is available on this device.');
      }

      final selectedCamera = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      final controller = CameraController(
        selectedCamera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup.nv21
            : ImageFormatGroup.bgra8888,
      );
      await controller.initialize();
      await controller.startImageStream(_processCameraFrame);

      ui.Image? overlayImage;
      if (widget.baselineRecord != null &&
          widget.baselineRecord!.imagePath.isNotEmpty) {
        overlayImage = await _loadOverlayImage(
          widget.baselineRecord!.imagePath,
        );
      }

      if (!mounted) {
        await controller.dispose();
        return;
      }

      setState(() {
        _cameraController = controller;
        _overlayImage = overlayImage;
        _initializing = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _initializing = false;
        _errorMessage = error.toString();
      });
    }
  }

  Future<void> _processCameraFrame(CameraImage image) async {
    if (_processingFrame || _capturing) {
      return;
    }

    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }

    final inputImage = _inputImageFromCameraImage(image, controller);
    if (inputImage == null) {
      return;
    }

    _processingFrame = true;
    try {
      final poses = await _streamPoseDetector.processImage(inputImage);
      if (!mounted) {
        return;
      }

      if (poses.isEmpty) {
        setState(() {
          _latestLandmarks = const [];
          _alignmentResult = const PoseAlignmentResult.empty();
          _alignmentHeldSince = null;
        });
        return;
      }

      final landmarks = poses.first.landmarks.values
          .map(PoseLandmarkPoint.fromPoseLandmark)
          .toList();
      final alignmentResult = _canAutoCapture
          ? PoseAlignmentEngine.compare(
              liveLandmarks: landmarks,
              referenceLandmarks: widget.baselineRecord!.landmarks,
            )
          : const PoseAlignmentResult.empty();

      setState(() {
        _latestLandmarks = landmarks;
        _alignmentResult = alignmentResult;
      });

      _handleAutoCapture(alignmentResult.score);
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _errorMessage = error.toString();
      });
    } finally {
      _processingFrame = false;
    }
  }

  void _handleAutoCapture(double score) {
    if (!_canAutoCapture || !_autoCaptureEnabled || _capturing) {
      _alignmentHeldSince = null;
      return;
    }

    if (score < _autoCaptureThreshold) {
      _alignmentHeldSince = null;
      return;
    }

    final now = DateTime.now();
    _alignmentHeldSince ??= now;

    if (now.difference(_alignmentHeldSince!) >=
        AppConstants.autoCaptureHoldDuration) {
      _alignmentHeldSince = null;
      unawaited(_captureFrame());
    }
  }

  Future<void> _captureFrame() async {
    final controller = _cameraController;
    if (controller == null || _capturing) {
      return;
    }

    if (_latestLandmarks.isEmpty) {
      _showSnackBar(
        'Step fully into frame so ML Kit can detect your pose first.',
      );
      return;
    }

    setState(() {
      _capturing = true;
    });

    var shouldRestartStream = true;
    try {
      if (controller.value.isStreamingImages) {
        await controller.stopImageStream();
      }

      final xFile = await controller.takePicture();
      final storage = ref.read(fileStorageServiceProvider);
      final repository = ref.read(poseRepositoryProvider);
      final relativePath = await storage.persistCameraCapture(
        xFile,
        seriesId: widget.series.id!,
      );
      final absolutePath = await storage.resolveAbsolutePath(relativePath);
      final detectedLandmarks = await _detectLandmarksInSavedImage(
        absolutePath,
      );
      final landmarks = detectedLandmarks.isEmpty
          ? _latestLandmarks
          : detectedLandmarks;

      if (landmarks.isEmpty) {
        throw StateError('No pose was detected in the saved image.');
      }

      await repository.addRecord(
        seriesId: widget.series.id!,
        imagePath: relativePath,
        timestamp: DateTime.now(),
        landmarks: landmarks,
        boundingBox: PoseGeometry.boundingBoxFor(landmarks),
        anchorCenter: PoseGeometry.anchorFor(landmarks),
        isReference: widget.isBaselineCapture,
      );

      ref.invalidate(seriesRecordsProvider(widget.series.id!));
      ref.invalidate(seriesBaselineProvider(widget.series.id!));
      await ref.read(seriesListControllerProvider.notifier).refresh();
      shouldRestartStream = false;

      if (!mounted) {
        return;
      }

      Navigator.of(context).pop(true);
    } catch (error) {
      _showSnackBar(error.toString());
    } finally {
      if (shouldRestartStream && mounted && controller.value.isInitialized) {
        await controller.startImageStream(_processCameraFrame);
      }
      if (mounted) {
        setState(() {
          _capturing = false;
        });
      }
    }
  }

  Future<List<PoseLandmarkPoint>> _detectLandmarksInSavedImage(
    String imagePath,
  ) async {
    final detector = PoseDetector(
      options: PoseDetectorOptions(
        model: PoseDetectionModel.accurate,
        mode: PoseDetectionMode.single,
      ),
    );
    try {
      final poses = await detector.processImage(
        InputImage.fromFilePath(imagePath),
      );
      if (poses.isEmpty) {
        return const [];
      }
      return poses.first.landmarks.values
          .map(PoseLandmarkPoint.fromPoseLandmark)
          .toList();
    } finally {
      await detector.close();
    }
  }

  InputImage? _inputImageFromCameraImage(
    CameraImage image,
    CameraController controller,
  ) {
    final camera = controller.description;
    final sensorOrientation = camera.sensorOrientation;

    InputImageRotation? rotation;
    if (Platform.isIOS) {
      rotation = InputImageRotationValue.fromRawValue(sensorOrientation);
    } else if (Platform.isAndroid) {
      var rotationCompensation =
          _orientations[controller.value.deviceOrientation.name];
      if (rotationCompensation == null) {
        return null;
      }

      if (camera.lensDirection == CameraLensDirection.front) {
        rotationCompensation = (sensorOrientation + rotationCompensation) % 360;
      } else {
        rotationCompensation =
            (sensorOrientation - rotationCompensation + 360) % 360;
      }

      rotation = InputImageRotationValue.fromRawValue(rotationCompensation);
    }

    if (rotation == null) {
      return null;
    }

    final inputImageFormat = InputImageFormatValue.fromRawValue(
      image.format.raw,
    );
    if (inputImageFormat == null ||
        (Platform.isAndroid && inputImageFormat != InputImageFormat.nv21) ||
        (Platform.isIOS && inputImageFormat != InputImageFormat.bgra8888)) {
      return null;
    }

    if (image.planes.length != 1) {
      return null;
    }

    final plane = image.planes.first;
    return InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: inputImageFormat,
        bytesPerRow: plane.bytesPerRow,
      ),
    );
  }

  Future<ui.Image?> _loadOverlayImage(String storedPath) async {
    final absolutePath = await ref
        .read(fileStorageServiceProvider)
        .resolveAbsolutePath(storedPath);
    if (absolutePath.isEmpty) {
      return null;
    }

    final bytes = await File(absolutePath).readAsBytes();
    return _decodeImage(bytes);
  }

  Future<ui.Image> _decodeImage(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frameInfo = await codec.getNextFrame();
    return frameInfo.image;
  }

  void _showSnackBar(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final controller = _cameraController;
    final score = _alignmentResult.score;
    final autoCaptureProgress = _alignmentHeldSince == null
        ? 0.0
        : (DateTime.now().difference(_alignmentHeldSince!).inMilliseconds /
                  AppConstants.autoCaptureHoldDuration.inMilliseconds)
              .clamp(0.0, 1.0);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.isBaselineCapture
              ? 'Capture Baseline Pose'
              : 'Align and Capture',
        ),
      ),
      body: _initializing
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(_errorMessage!, textAlign: TextAlign.center),
              ),
            )
          : controller == null
          ? const Center(child: Text('Camera setup failed.'))
          : SafeArea(
              child: Column(
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(18, 8, 18, 12),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(28),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            AspectRatio(
                              aspectRatio: controller.value.aspectRatio,
                              child: CameraPreview(controller),
                            ),
                            if (_overlayImage != null)
                              Positioned.fill(
                                child: IgnorePointer(
                                  child: Opacity(
                                    opacity: _overlayOpacity,
                                    child: CustomPaint(
                                      painter: OnionSkinOverlayPainter(
                                        image: _overlayImage!,
                                        mirrorHorizontally:
                                            controller
                                                .description
                                                .lensDirection ==
                                            CameraLensDirection.front,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            Positioned(
                              top: 16,
                              left: 16,
                              right: 16,
                              child: _buildStatusPanel(
                                score,
                                autoCaptureProgress,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  _buildControls(context),
                ],
              ),
            ),
    );
  }

  Widget _buildStatusPanel(double score, double autoCaptureProgress) {
    final theme = Theme.of(context);
    return Card(
      color: Colors.black.withValues(alpha: 0.55),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.isBaselineCapture
                  ? 'Hold your neutral baseline pose. Save one clean reference frame for this series.'
                  : 'Match the onion-skin overlay until shoulders, hips, and limbs line up.',
              style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white),
            ),
            const SizedBox(height: 10),
            if (_canAutoCapture) ...[
              Row(
                children: [
                  Expanded(
                    child: LinearProgressIndicator(
                      value: score / 100,
                      minHeight: 10,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '${score.round()}%',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              LinearProgressIndicator(
                value: autoCaptureProgress,
                minHeight: 6,
                borderRadius: BorderRadius.circular(999),
                color: theme.colorScheme.tertiary,
                backgroundColor: Colors.white24,
              ),
              const SizedBox(height: 6),
              Text(
                score >= _autoCaptureThreshold
                    ? 'Hold steady for auto-capture.'
                    : 'Target threshold: ${_autoCaptureThreshold.round()}%',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.white70,
                ),
              ),
            ] else
              Text(
                _latestLandmarks.isEmpty
                    ? 'Step back until ML Kit detects your full body.'
                    : 'Pose detected. Capture when the stance feels right.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.white70,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildControls(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.series.name,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 6),
              Text(
                widget.isBaselineCapture
                    ? 'Onboarding step: save the baseline reference pose for this series.'
                    : 'Use the translucent reference frame and score meter to lock alignment before each shot.',
              ),
              const SizedBox(height: 14),
              if (_overlayImage != null) ...[
                Text('Onion skin opacity: ${(_overlayOpacity * 100).round()}%'),
                Slider(
                  value: _overlayOpacity,
                  min: 0.1,
                  max: 0.6,
                  onChanged: (value) {
                    setState(() {
                      _overlayOpacity = value;
                    });
                  },
                ),
                const SizedBox(height: 6),
              ],
              if (_canAutoCapture) ...[
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Auto-capture when alignment is stable'),
                  subtitle: const Text(
                    'Requires 1.5 seconds above the threshold.',
                  ),
                  value: _autoCaptureEnabled,
                  onChanged: (value) {
                    setState(() {
                      _autoCaptureEnabled = value;
                      _alignmentHeldSince = null;
                    });
                  },
                ),
                Text('Target threshold: ${_autoCaptureThreshold.round()}%'),
                Slider(
                  value: _autoCaptureThreshold,
                  min: 75,
                  max: 98,
                  divisions: 23,
                  label: '${_autoCaptureThreshold.round()}%',
                  onChanged: (value) {
                    setState(() {
                      _autoCaptureThreshold = value;
                      _alignmentHeldSince = null;
                    });
                  },
                ),
              ],
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _capturing ? null : _captureFrame,
                  icon: _capturing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.camera_alt_rounded),
                  label: Text(
                    widget.isBaselineCapture
                        ? 'Save Baseline Pose'
                        : 'Capture Progress Shot',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
