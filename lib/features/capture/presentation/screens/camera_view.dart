import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import '../../../../app/app_settings.dart';
import '../../../../app/providers.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/utils/accuracy_debouncer.dart';
import '../../../../core/utils/dynamic_alignment_service.dart';
import '../../../../core/utils/landmark_smoother.dart';
import '../../../../core/utils/pose_alignment_engine.dart';
import '../../../../core/utils/rotation_utility.dart';
import '../../../../core/widgets/camera_preview_viewport.dart';
import '../../../../core/widgets/pose_skeleton_painter.dart';
import '../../../../core/widgets/reference_guide_painter.dart';
import '../../../../data/models/capture_viewport_ratio.dart';
import '../../../../data/models/lens_facing.dart';
import '../../../../data/models/pose_landmark_point.dart';
import '../../../../data/models/pose_record.dart';
import '../../../../data/models/pose_series.dart';

class CameraView extends ConsumerStatefulWidget {
  const CameraView({super.key, required this.series, this.referenceRecord});

  final PoseSeries series;
  final PoseRecord? referenceRecord;

  @override
  ConsumerState<CameraView> createState() => _CameraViewState();
}

class _CameraViewState extends ConsumerState<CameraView> {
  static const Map<String, int> _orientations = {
    'portraitUp': 0,
    'landscapeLeft': 90,
    'portraitDown': 180,
    'landscapeRight': 270,
  };

  late final PoseDetector _streamPoseDetector;
  late final LandmarkSmoother _landmarkSmoother;
  late final AccuracyDebouncer _accuracyDebouncer;
  late final DynamicAlignmentService _dynamicAlignmentService;
  late final RotationUtility _rotationUtility;

  List<CameraDescription> _availableCameras = const [];
  CameraController? _cameraController;
  int _selectedCameraIndex = 0;

  List<PoseLandmarkPoint> _latestLandmarks = const [];
  InputImageRotation _latestFrameRotation = InputImageRotation.rotation0deg;
  Size _latestFrameSize = Size.zero;
  double _poseMotion = 1.0;
  double _displayedAlignmentScore = 0;

  bool _initializing = true;
  bool _processingFrame = false;
  bool _capturing = false;
  DateTime? _alignmentHeldSince;
  String? _errorMessage;

  double _minZoomLevel = AppConstants.defaultZoomLevel;
  double _maxZoomLevel = AppConstants.defaultZoomLevel;
  double _zoomLevel = AppConstants.defaultZoomLevel;
  double _baseZoomLevel = AppConstants.defaultZoomLevel;
  double? _seriesZoomPreference;
  LensFacing? _seriesLensPreference;
  late CaptureViewportRatio _viewportRatio;
  Timer? _seriesPreferencesSaveTimer;

  bool get _canAutoCapture {
    return widget.referenceRecord != null &&
        widget.referenceRecord!.landmarks.isNotEmpty;
  }

  bool get _supportsUltraWide => _minZoomLevel <= 0.65;

  double get _minimumSelectableZoom {
    if (_supportsUltraWide) {
      return _minZoomLevel;
    }
    return _minZoomLevel > AppConstants.defaultZoomLevel
        ? _minZoomLevel
        : AppConstants.defaultZoomLevel;
  }

  @override
  void initState() {
    super.initState();
    _landmarkSmoother = LandmarkSmoother();
    _accuracyDebouncer = AccuracyDebouncer(
      alpha: AppConstants.defaultAccuracyDebounceAlpha,
      updateInterval: AppConstants.accuracyDebounceInterval,
    );
    _dynamicAlignmentService = ref.read(dynamicAlignmentServiceProvider);
    _rotationUtility = ref.read(rotationUtilityProvider);
    _seriesZoomPreference = widget.series.lastUsedZoomLevel;
    _seriesLensPreference = widget.series.preferredLens;
    _viewportRatio = widget.series.lastUsedAspectRatio;
    _streamPoseDetector = PoseDetector(
      options: PoseDetectorOptions(
        model: PoseDetectionModel.base,
        mode: PoseDetectionMode.stream,
      ),
    );
    unawaited(_initializeCameraFlow());
  }

  @override
  void dispose() {
    _landmarkSmoother.reset();
    _accuracyDebouncer.reset();
    _seriesPreferencesSaveTimer?.cancel();
    unawaited(_cameraController?.dispose());
    unawaited(_streamPoseDetector.close());
    super.dispose();
  }

  Future<void> _initializeCameraFlow() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        throw StateError('No camera is available on this device.');
      }

      final preferredLensDirection =
          _seriesLensPreference?.cameraLensDirection ??
          (widget.referenceRecord?.cameraLens == CameraLensDirection.back.name
              ? CameraLensDirection.back
              : CameraLensDirection.front);
      final preferredIndex = cameras.indexWhere(
        (camera) => camera.lensDirection == preferredLensDirection,
      );
      _availableCameras = cameras;
      _selectedCameraIndex = preferredIndex >= 0 ? preferredIndex : 0;

      await _startCamera(_availableCameras[_selectedCameraIndex]);
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

  Future<void> _startCamera(CameraDescription description) async {
    final previousController = _cameraController;
    if (previousController != null) {
      if (previousController.value.isStreamingImages) {
        await previousController.stopImageStream();
      }
      await previousController.dispose();
    }

    if (mounted) {
      setState(() {
        _initializing = true;
        _errorMessage = null;
      });
    }

    final controller = CameraController(
      description,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: Platform.isAndroid
          ? ImageFormatGroup.nv21
          : ImageFormatGroup.bgra8888,
    );

    await controller.initialize();

    final minZoom = await controller.getMinZoomLevel();
    final maxZoom = await controller.getMaxZoomLevel();
    final minimumSelectableZoom = minZoom <= 0.65
        ? minZoom
        : (minZoom > AppConstants.defaultZoomLevel
              ? minZoom
              : AppConstants.defaultZoomLevel);
    final desiredZoom = previousController == null
        ? (_seriesZoomPreference ?? AppConstants.defaultZoomLevel)
        : (_seriesZoomPreference ?? _zoomLevel);
    final zoom = desiredZoom.clamp(minimumSelectableZoom, maxZoom).toDouble();

    await controller.setZoomLevel(zoom);
    await controller.startImageStream(_processCameraFrame);

    if (!mounted) {
      await controller.dispose();
      return;
    }

    _landmarkSmoother.reset();
    _accuracyDebouncer.reset();
    _seriesZoomPreference = zoom;
    _seriesLensPreference = LensFacing.fromCameraLensDirection(
      description.lensDirection,
    );
    setState(() {
      _cameraController = controller;
      _minZoomLevel = minZoom;
      _maxZoomLevel = maxZoom;
      _zoomLevel = zoom;
      _alignmentHeldSince = null;
      _latestLandmarks = const [];
      _poseMotion = 1.0;
      _displayedAlignmentScore = 0;
      _initializing = false;
    });
    _scheduleSeriesPreferencesSave();
  }

  Future<void> _switchCamera() async {
    if (_availableCameras.length < 2 || _capturing) {
      return;
    }

    final nextIndex = (_selectedCameraIndex + 1) % _availableCameras.length;
    _selectedCameraIndex = nextIndex;
    _seriesLensPreference = LensFacing.fromCameraLensDirection(
      _availableCameras[_selectedCameraIndex].lensDirection,
    );
    await _startCamera(_availableCameras[_selectedCameraIndex]);
  }

  Future<void> _processCameraFrame(CameraImage image) async {
    if (_processingFrame || _capturing) {
      return;
    }

    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }

    final input = _cameraInputFromImage(image, controller);
    if (input == null) {
      return;
    }

    _processingFrame = true;
    try {
      final poses = await _streamPoseDetector.processImage(input.inputImage);
      if (!mounted) {
        return;
      }

      if (poses.isEmpty) {
        _landmarkSmoother.reset();
        _clearTracking(input.rotation, input.imageSize);
        return;
      }

      final rawLandmarks = poses.first.landmarks.values
          .map(PoseLandmarkPoint.fromPoseLandmark)
          .toList(growable: false);
      final landmarks = _landmarkSmoother.smooth(rawLandmarks);
      if (landmarks.isEmpty) {
        _clearTracking(input.rotation, input.imageSize);
        return;
      }

      final poseMotion = _landmarkSmoother.lastAverageMotion;
      final alignmentComparison = _canAutoCapture
          ? _dynamicAlignmentService.compareToReference(
              liveLandmarks: landmarks,
              referenceRecord: widget.referenceRecord!,
              activeLensDirection: controller.description.lensDirection,
            )
          : const DynamicAlignmentComparison.empty();
      final displayedAlignmentScore = _canAutoCapture
          ? _accuracyDebouncer.update(alignmentComparison.alignment.score)
          : 0.0;

      setState(() {
        _latestLandmarks = landmarks;
        _latestFrameRotation = input.rotation;
        _latestFrameSize = input.imageSize;
        _poseMotion = poseMotion;
        _displayedAlignmentScore = displayedAlignmentScore;
      });

      _handleAutoCapture(displayedAlignmentScore, poseMotion);
    } catch (_) {
      _alignmentHeldSince = null;
    } finally {
      _processingFrame = false;
    }
  }

  void _clearTracking(InputImageRotation rotation, Size imageSize) {
    _accuracyDebouncer.reset();
    setState(() {
      _latestLandmarks = const [];
      _latestFrameRotation = rotation;
      _latestFrameSize = imageSize;
      _poseMotion = 1.0;
      _displayedAlignmentScore = 0;
      _alignmentHeldSince = null;
    });
  }

  void _handleAutoCapture(double score, double poseMotion) {
    final settings = ref.read(appSettingsProvider);
    if (!_canAutoCapture || !settings.autoCaptureEnabled || _capturing) {
      _alignmentHeldSince = null;
      return;
    }
    if (score < settings.alignmentThreshold ||
        poseMotion > settings.stabilitySensitivity) {
      _alignmentHeldSince = null;
      return;
    }

    final now = DateTime.now();
    _alignmentHeldSince ??= now;
    if (now.difference(_alignmentHeldSince!) >= settings.autoCaptureDelay) {
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
        'Step back until your full pose is visible to the tracker.',
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

      final sensedOrientation = controller.value.deviceOrientation;
      final xFile = await controller.takePicture();
      final fileStorage = ref.read(fileStorageServiceProvider);
      final repository = ref.read(poseRepositoryProvider);
      final settings = ref.read(appSettingsProvider);
      final captureResult = await _rotationUtility.transformJpegForStorage(
        jpegBytes: await File(xFile.path).readAsBytes(),
        fallbackOrientation: sensedOrientation,
      );
      final relativePath = await fileStorage.persistCaptureBytes(
        captureResult.bytes,
        seriesId: widget.series.id!,
        preferredRootPath: settings.photoStorageDirectoryPath.isEmpty
            ? null
            : settings.photoStorageDirectoryPath,
      );
      try {
        await File(xFile.path).delete();
      } catch (_) {}
      final absolutePath = await fileStorage.resolveAbsolutePath(relativePath);
      final dimensions = await fileStorage.readImageDimensions(absolutePath);
      final detectedLandmarks = await _detectLandmarksInSavedImage(
        absolutePath,
      );
      final landmarks = detectedLandmarks.isEmpty
          ? _latestLandmarks
          : detectedLandmarks;

      if (landmarks.isEmpty) {
        throw StateError('No person was detected in the saved photo.');
      }

      await repository.addRecord(
        seriesId: widget.series.id!,
        imagePath: relativePath,
        label: '',
        timestamp: DateTime.now(),
        landmarks: landmarks,
        boundingBox: PoseGeometry.boundingBoxFor(landmarks),
        anchorCenter: PoseGeometry.anchorFor(landmarks),
        cameraLens: controller.description.lensDirection.name,
        captureOrientation: captureResult.storedOrientation,
        imageWidth: dimensions.width,
        imageHeight: dimensions.height,
        captureZoomLevel: _zoomLevel,
        captureViewportRatio: _viewportRatio,
      );

      ref.invalidate(seriesRecordsProvider(widget.series.id!));
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
        _landmarkSmoother.reset();
        _accuracyDebouncer.reset();
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
          .toList(growable: false);
    } finally {
      await detector.close();
    }
  }

  _CameraInput? _cameraInputFromImage(
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
    return _CameraInput(
      inputImage: InputImage.fromBytes(
        bytes: plane.bytes,
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: rotation,
          format: inputImageFormat,
          bytesPerRow: plane.bytesPerRow,
        ),
      ),
      rotation: rotation,
      imageSize: Size(image.width.toDouble(), image.height.toDouble()),
    );
  }

  Future<void> _setZoomLevel(double zoom) async {
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }

    final clampedZoom = zoom
        .clamp(_minimumSelectableZoom, _maxZoomLevel)
        .toDouble();
    await controller.setZoomLevel(clampedZoom);
    if (!mounted) {
      return;
    }
    _seriesZoomPreference = clampedZoom;
    setState(() {
      _zoomLevel = clampedZoom;
    });
    _scheduleSeriesPreferencesSave();
  }

  void _setViewportRatio(CaptureViewportRatio viewportRatio) {
    if (_viewportRatio == viewportRatio) {
      return;
    }

    setState(() {
      _viewportRatio = viewportRatio;
    });
    _scheduleSeriesPreferencesSave();
  }

  List<double> _zoomPresets() {
    final presets = <double>[
      if (_supportsUltraWide) 0.6,
      1.0,
      if (_maxZoomLevel >= 2.0) 2.0,
    ];
    return presets
        .where(
          (value) =>
              value >= _minimumSelectableZoom - 0.01 && value <= _maxZoomLevel,
        )
        .toList(growable: false);
  }

  void _scheduleSeriesPreferencesSave() {
    final seriesId = widget.series.id;
    final controller = _cameraController;
    if (seriesId == null || controller == null) {
      return;
    }

    _seriesPreferencesSaveTimer?.cancel();
    _seriesPreferencesSaveTimer = Timer(const Duration(milliseconds: 220), () {
      unawaited(
        ref
            .read(poseRepositoryProvider)
            .updateSeriesCapturePreferences(
              seriesId,
              preferredLens: LensFacing.fromCameraLensDirection(
                controller.description.lensDirection,
              ),
              lastUsedZoomLevel: _seriesZoomPreference ?? _zoomLevel,
              lastUsedAspectRatio: _viewportRatio,
            ),
      );
    });
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
    final settings = ref.watch(appSettingsProvider);
    final controller = _cameraController;
    final autoCaptureProgress = _alignmentHeldSince == null
        ? 0.0
        : (DateTime.now().difference(_alignmentHeldSince!).inMilliseconds /
                  settings.autoCaptureDelay.inMilliseconds)
              .clamp(0.0, 1.0)
              .toDouble();

    return Scaffold(
      backgroundColor: Colors.black,
      body: _initializing
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  _errorMessage!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            )
          : controller == null
          ? const Center(
              child: Text(
                'Camera setup failed.',
                style: TextStyle(color: Colors.white),
              ),
            )
          : Stack(
              children: [
                Positioned.fill(child: _buildFullScreenPreview(controller)),
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: Row(
                        children: [
                          _GlassIconButton(
                            icon: Icons.arrow_back_ios_new_rounded,
                            onPressed: () => Navigator.of(context).maybePop(),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _InfoPill(
                              title: widget.series.name,
                              subtitle: widget.referenceRecord == null
                                  ? 'Capture the first photo for this timeline. Later shots will line up to it.'
                                  : _statusMessage(settings),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                      child: _buildBottomControls(
                        settings,
                        autoCaptureProgress,
                      ),
                    ),
                  ),
                ),
                if (_capturing)
                  Positioned.fill(
                    child: ColoredBox(
                      color: Colors.black.withValues(alpha: 0.28),
                      child: const Center(child: CircularProgressIndicator()),
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _buildFullScreenPreview(CameraController controller) {
    final settings = ref.watch(appSettingsProvider);
    final previewSize = controller.value.previewSize ?? const Size(720, 1280);
    final orientedPreviewSize = previewSize.height > previewSize.width
        ? previewSize
        : Size(previewSize.height, previewSize.width);
    final shouldShowReferenceGuide =
        !_capturing &&
        widget.referenceRecord != null &&
        settings.showReferenceOverlay;
    final mirrorReferenceGuide =
        shouldShowReferenceGuide &&
        widget.referenceRecord!.cameraLens !=
            controller.description.lensDirection.name;

    return GestureDetector(
      onScaleStart: (_) {
        _baseZoomLevel = _zoomLevel;
      },
      onScaleUpdate: (details) {
        if (details.pointerCount < 2) {
          return;
        }
        unawaited(_setZoomLevel(_baseZoomLevel * details.scale));
      },
      child: CameraPreviewViewport(
        viewportRatio: _viewportRatio,
        child: ClipRect(
          child: FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: orientedPreviewSize.width,
              height: orientedPreviewSize.height,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CameraPreview(controller),
                  if (shouldShowReferenceGuide)
                    IgnorePointer(
                      child: CustomPaint(
                        painter: ReferenceGuidePainter(
                          referenceRecord: widget.referenceRecord!,
                          liveLandmarks: _latestLandmarks,
                          liveImageSize: _latestFrameSize,
                          liveRotation: _latestFrameRotation,
                          cameraLensDirection:
                              controller.description.lensDirection,
                          opacity: settings.referenceOverlayOpacity,
                          mirrorHorizontally: mirrorReferenceGuide,
                        ),
                      ),
                    ),
                  IgnorePointer(
                    child: CustomPaint(
                      painter: SkeletonPainter(
                        landmarks: _latestLandmarks,
                        imageSize: _latestFrameSize,
                        rotation: _latestFrameRotation,
                        cameraLensDirection:
                            controller.description.lensDirection,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomControls(
    AppSettings settings,
    double autoCaptureProgress,
  ) {
    final theme = Theme.of(context);
    final showProgress =
        _canAutoCapture &&
        settings.autoCaptureEnabled &&
        _displayedAlignmentScore >= settings.alignmentThreshold &&
        _poseMotion <= settings.stabilitySensitivity;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.referenceRecord != null)
          _CaptureStatusCard(
            score: _displayedAlignmentScore,
            statusText: _statusMessage(settings),
            progress: autoCaptureProgress,
            showProgress: showProgress,
          ),
        if (widget.referenceRecord != null) const SizedBox(height: 14),
        DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.58),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
            child: Column(
              children: [
                Row(
                  children: [
                    Text(
                      'Zoom ${_zoomLevel.toStringAsFixed(1)}x',
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      (_cameraController?.description.lensDirection.name ??
                              'front')
                          .toUpperCase(),
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: CaptureViewportRatio.values
                      .map(
                        (viewportRatio) => ChoiceChip(
                          label: Text(viewportRatio.label),
                          selected: _viewportRatio == viewportRatio,
                          onSelected: (_) => _setViewportRatio(viewportRatio),
                        ),
                      )
                      .toList(growable: false),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _zoomPresets()
                      .map(
                        (preset) => ChoiceChip(
                          label: Text('${preset.toStringAsFixed(1)}x'),
                          selected: (_zoomLevel - preset).abs() < 0.05,
                          onSelected: (_) => unawaited(_setZoomLevel(preset)),
                        ),
                      )
                      .toList(growable: false),
                ),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 8,
                    ),
                    overlayShape: const RoundSliderOverlayShape(
                      overlayRadius: 16,
                    ),
                  ),
                  child: Slider(
                    value: _zoomLevel,
                    min: _minimumSelectableZoom,
                    max: _maxZoomLevel,
                    onChanged: (value) => unawaited(_setZoomLevel(value)),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            const Expanded(child: SizedBox()),
            _ShutterButton(
              busy: _capturing,
              semanticLabel: widget.referenceRecord == null
                  ? 'Capture first photo'
                  : 'Capture progress photo',
              onPressed: _capturing ? null : _captureFrame,
            ),
            Expanded(
              child: Align(
                alignment: Alignment.centerRight,
                child: _GlassIconButton(
                  icon: Icons.flip_camera_ios_rounded,
                  onPressed: _availableCameras.length > 1
                      ? _switchCamera
                      : null,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  String _statusMessage(AppSettings settings) {
    if (_latestLandmarks.isEmpty) {
      return 'Step back until shoulders, hips, knees, and feet are visible.';
    }
    if (widget.referenceRecord == null) {
      return 'Frame the first photo and use the shutter when you are ready.';
    }
    if (!_canAutoCapture || !settings.autoCaptureEnabled) {
      return 'Frame the photo and use the shutter when you are ready.';
    }
    if (_displayedAlignmentScore < settings.alignmentThreshold) {
      return 'Match the latest photo before auto-capture begins.';
    }
    if (_poseMotion > settings.stabilitySensitivity) {
      return 'Hold still while the tracker settles on the current pose.';
    }

    final elapsedMs = _alignmentHeldSince == null
        ? 0
        : DateTime.now().difference(_alignmentHeldSince!).inMilliseconds;
    final remainingMs = (settings.autoCaptureDelay.inMilliseconds - elapsedMs)
        .clamp(0, settings.autoCaptureDelay.inMilliseconds);
    final remainingSeconds = (remainingMs / 1000).toStringAsFixed(1);
    return 'Aligned. Auto-capture in ${remainingSeconds}s.';
  }
}

class _CameraInput {
  const _CameraInput({
    required this.inputImage,
    required this.rotation,
    required this.imageSize,
  });

  final InputImage inputImage;
  final InputImageRotation rotation;
  final Size imageSize;
}

class _GlassIconButton extends StatelessWidget {
  const _GlassIconButton({required this.icon, required this.onPressed});

  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.48),
        shape: BoxShape.circle,
      ),
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon, color: Colors.white),
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.48),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.white70),
            ),
          ],
        ),
      ),
    );
  }
}

class _CaptureStatusCard extends StatelessWidget {
  const _CaptureStatusCard({
    required this.score,
    required this.statusText,
    required this.progress,
    required this.showProgress,
  });

  final double score;
  final String statusText;
  final double progress;
  final bool showProgress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.58),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  '${score.round()}% aligned',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                if (showProgress)
                  Text(
                    '${(progress * 100).round()}%',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: Colors.white70,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              statusText,
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.white70),
            ),
            if (showProgress) ...[
              const SizedBox(height: 10),
              LinearProgressIndicator(
                value: progress,
                minHeight: 5,
                borderRadius: BorderRadius.circular(999),
                backgroundColor: Colors.white24,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ShutterButton extends StatelessWidget {
  const _ShutterButton({
    required this.busy,
    required this.semanticLabel,
    required this.onPressed,
  });

  final bool busy;
  final String semanticLabel;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel,
      child: GestureDetector(
        onTap: onPressed,
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 4),
          ),
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: busy ? Colors.white70 : Colors.white,
              ),
              child: SizedBox(
                width: 74,
                height: 74,
                child: busy
                    ? const Center(
                        child: SizedBox(
                          width: 26,
                          height: 26,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.black,
                          ),
                        ),
                      )
                    : null,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
