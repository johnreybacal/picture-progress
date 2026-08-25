import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import '../../../../app/app_settings.dart';
import '../../../../app/providers.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/utils/accuracy_debouncer.dart';
import '../../../../core/utils/camera_viewport_geometry.dart';
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

  CameraController? _cameraController;
  CameraDescription? _frontCamera;
  _RearCameraSystem? _rearCameraSystem;

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
  double _baseLogicalZoomLevel = AppConstants.defaultZoomLevel;
  double _currentLensBaseZoom = AppConstants.defaultZoomLevel;
  double _lastFrontLogicalZoomLevel = AppConstants.defaultZoomLevel;
  double _lastBackLogicalZoomLevel = AppConstants.defaultZoomLevel;
  double? _seriesZoomPreference;
  LensFacing? _seriesLensPreference;
  late CaptureViewportRatio _viewportRatio;
  Timer? _seriesPreferencesSaveTimer;
  late final FocusNode _cameraShortcutsFocusNode;

  bool get _canAutoCapture {
    return widget.referenceRecord != null &&
        widget.referenceRecord!.landmarks.isNotEmpty;
  }

  bool get _isFrontCameraActive {
    return _cameraController?.description.lensDirection ==
        CameraLensDirection.front;
  }

  bool get _hasCameraDirections {
    return _frontCamera != null && _rearCameraSystem != null;
  }

  bool get _isFirstCapture {
    return widget.referenceRecord == null;
  }

  @override
  void initState() {
    super.initState();
    _cameraShortcutsFocusNode = FocusNode(debugLabel: 'cameraShortcuts');
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

    final initialLogicalZoom =
        _seriesZoomPreference ?? AppConstants.defaultZoomLevel;
    if (_seriesLensPreference == LensFacing.front) {
      _lastFrontLogicalZoomLevel = initialLogicalZoom;
    } else {
      _lastBackLogicalZoomLevel = initialLogicalZoom;
    }

    _streamPoseDetector = PoseDetector(
      options: PoseDetectorOptions(
        model: PoseDetectionModel.base,
        mode: PoseDetectionMode.stream,
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _requestCameraShortcutsFocus();
    });
    _initializeCameraFlow();
  }

  @override
  void dispose() {
    _landmarkSmoother.reset();
    _accuracyDebouncer.reset();
    _seriesPreferencesSaveTimer?.cancel();
    _cameraShortcutsFocusNode.dispose();

    final controller = _cameraController;
    if (controller != null) {
      try {
        if (controller.value.isStreamingImages) {
          controller.stopImageStream();
        }
      } catch (_) {}
      unawaited(controller.dispose().catchError((_) {}));
    }

    unawaited(_streamPoseDetector.close());
    super.dispose();
  }

  Future<void> _initializeCameraFlow() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        throw StateError('No camera is available on this device.');
      }

      _frontCamera = _selectFrontCamera(cameras);
      _rearCameraSystem = _buildRearCameraSystem(cameras);

      final preferredLensDirection =
          _seriesLensPreference?.cameraLensDirection ??
          (widget.referenceRecord?.cameraLens == CameraLensDirection.back.name
              ? CameraLensDirection.back
              : CameraLensDirection.front);

      if (preferredLensDirection == CameraLensDirection.front &&
          _frontCamera != null) {
        await _startFrontCamera(
          preferredLogicalZoom: _seriesLensPreference == LensFacing.front
              ? (_seriesZoomPreference ?? _lastFrontLogicalZoomLevel)
              : _lastFrontLogicalZoomLevel,
        );
        return;
      }

      if (_rearCameraSystem != null) {
        await _startBackCameraForLogicalZoom(
          _seriesLensPreference == LensFacing.back
              ? (_seriesZoomPreference ?? _lastBackLogicalZoomLevel)
              : _lastBackLogicalZoomLevel,
        );
        return;
      }

      if (_frontCamera != null) {
        await _startFrontCamera(
          preferredLogicalZoom: _lastFrontLogicalZoomLevel,
        );
        return;
      }

      throw StateError('No supported front or rear camera is available.');
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

  CameraDescription? _selectFrontCamera(List<CameraDescription> cameras) {
    final frontCameras = cameras
        .where((camera) => camera.lensDirection == CameraLensDirection.front)
        .toList(growable: false);
    if (frontCameras.isEmpty) {
      return null;
    }

    return _firstCameraWithLensType(frontCameras, CameraLensType.wide) ??
        frontCameras.first;
  }

  _RearCameraSystem? _buildRearCameraSystem(List<CameraDescription> cameras) {
    final rearCameras = cameras
        .where((camera) => camera.lensDirection != CameraLensDirection.front)
        .toList(growable: false);
    if (rearCameras.isEmpty) {
      return null;
    }

    final explicitUltraWide =
        _firstCameraWithLensType(rearCameras, CameraLensType.ultraWide) ??
        _firstCameraMatchingName(rearCameras, const ['ultra', '0.6']);
    final telephoto =
        _firstCameraWithLensType(rearCameras, CameraLensType.telephoto) ??
        _firstCameraMatchingName(rearCameras, const ['tele', '2x', 'zoom']);
    final ultraWide = explicitUltraWide;
    final wide =
        _firstCameraWithLensType(rearCameras, CameraLensType.wide) ??
        rearCameras.firstWhere(
          (camera) => camera != ultraWide && camera != telephoto,
          orElse: () => rearCameras.first,
        );

    return _RearCameraSystem(
      wide: wide,
      ultraWide: ultraWide == wide ? null : ultraWide,
      telephoto: telephoto == wide ? null : telephoto,
    );
  }

  CameraDescription? _firstCameraWithLensType(
    List<CameraDescription> cameras,
    CameraLensType lensType,
  ) {
    for (final camera in cameras) {
      if (camera.lensType == lensType) {
        return camera;
      }
    }
    return null;
  }

  CameraDescription? _firstCameraMatchingName(
    List<CameraDescription> cameras,
    List<String> keywords,
  ) {
    for (final camera in cameras) {
      final lowerName = camera.name.toLowerCase();
      if (keywords.any(lowerName.contains)) {
        return camera;
      }
    }
    return null;
  }

  Future<void> _startFrontCamera({
    double preferredLogicalZoom = AppConstants.defaultZoomLevel,
  }) async {
    final camera = _frontCamera ?? _rearCameraSystem?.wide;
    if (camera == null) {
      throw StateError('No front camera is available on this device.');
    }

    await _startCamera(
      camera,
      desiredControllerZoom: preferredLogicalZoom,
      lensBaseZoom: AppConstants.defaultZoomLevel,
    );
  }

  Future<void> _startBackCameraForLogicalZoom(double logicalZoom) async {
    final rearCameraSystem = _rearCameraSystem;
    if (rearCameraSystem == null) {
      if (_frontCamera != null) {
        await _startFrontCamera(
          preferredLogicalZoom: _lastFrontLogicalZoomLevel,
        );
      }
      return;
    }

    final plan = _resolveBackCameraLaunchPlan(logicalZoom, rearCameraSystem);
    await _startCamera(
      plan.camera,
      desiredControllerZoom: plan.desiredControllerZoom,
      lensBaseZoom: plan.lensBaseZoom,
    );
  }

  _BackCameraLaunchPlan _resolveBackCameraLaunchPlan(
    double logicalZoom,
    _RearCameraSystem rearCameraSystem,
  ) {
    final preset = _presetForLogicalZoom(logicalZoom);
    switch (preset) {
      case _ZoomPreset.ultraWide:
        if (rearCameraSystem.ultraWide != null) {
          return _BackCameraLaunchPlan(
            camera: rearCameraSystem.ultraWide!,
            lensBaseZoom: _ZoomPreset.ultraWide.logicalZoom,
            desiredControllerZoom:
                logicalZoom / _ZoomPreset.ultraWide.logicalZoom,
          );
        }
        return _BackCameraLaunchPlan(
          camera: rearCameraSystem.wide,
          lensBaseZoom: AppConstants.defaultZoomLevel,
          desiredControllerZoom: logicalZoom,
        );
      case _ZoomPreset.telephoto:
        if (rearCameraSystem.telephoto != null) {
          return _BackCameraLaunchPlan(
            camera: rearCameraSystem.telephoto!,
            lensBaseZoom: _ZoomPreset.telephoto.logicalZoom,
            desiredControllerZoom:
                logicalZoom / _ZoomPreset.telephoto.logicalZoom,
          );
        }
        return _BackCameraLaunchPlan(
          camera: rearCameraSystem.wide,
          lensBaseZoom: AppConstants.defaultZoomLevel,
          desiredControllerZoom: logicalZoom,
        );
      case _ZoomPreset.wide:
        return _BackCameraLaunchPlan(
          camera: rearCameraSystem.wide,
          lensBaseZoom: AppConstants.defaultZoomLevel,
          desiredControllerZoom: logicalZoom,
        );
    }
  }

  _ZoomPreset _presetForLogicalZoom(double logicalZoom) {
    if (logicalZoom < AppConstants.defaultZoomLevel) {
      return _ZoomPreset.ultraWide;
    }
    if (logicalZoom > _ZoomPreset.telephoto.logicalZoom) {
      return _ZoomPreset.telephoto;
    }
    return _ZoomPreset.wide;
  }

  Future<void> _startCamera(
    CameraDescription description, {
    required double desiredControllerZoom,
    required double lensBaseZoom,
  }) async {
    final previousController = _cameraController;
    if (previousController != null) {
      try {
        if (previousController.value.isStreamingImages) {
          await previousController.stopImageStream();
        }
      } catch (_) {}
      try {
        await previousController.dispose();
      } catch (_) {}
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
    final controllerZoom = desiredControllerZoom
        .clamp(minZoom, maxZoom)
        .toDouble();

    await controller.setZoomLevel(controllerZoom);
    await controller.startImageStream(_processCameraFrame);

    if (!mounted) {
      unawaited(controller.dispose().catchError((_) {}));
      return;
    }

    final logicalZoom = controllerZoom * lensBaseZoom;
    _landmarkSmoother.reset();
    _accuracyDebouncer.reset();
    _seriesZoomPreference = logicalZoom;
    _seriesLensPreference = LensFacing.fromCameraLensDirection(
      description.lensDirection,
    );
    if (description.lensDirection == CameraLensDirection.front) {
      _lastFrontLogicalZoomLevel = logicalZoom;
    } else {
      _lastBackLogicalZoomLevel = logicalZoom;
    }

    setState(() {
      _cameraController = controller;
      _minZoomLevel = minZoom;
      _maxZoomLevel = maxZoom;
      _currentLensBaseZoom = lensBaseZoom;
      _zoomLevel = logicalZoom;
      _alignmentHeldSince = null;
      _latestLandmarks = const [];
      _poseMotion = 1.0;
      _displayedAlignmentScore = 0;
      _initializing = false;
    });
    _scheduleSeriesPreferencesSave();
  }

  Future<void> _switchCamera() async {
    if (_capturing || !_hasCameraDirections || !_isFirstCapture) {
      return;
    }

    if (_isFrontCameraActive) {
      await _startBackCameraForLogicalZoom(_lastBackLogicalZoomLevel);
      return;
    }

    await _startFrontCamera(preferredLogicalZoom: _lastFrontLogicalZoomLevel);
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
    final previewCanvasSize = MediaQuery.sizeOf(context);
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
        viewportRatio: _viewportRatio,
        previewCanvasSize: previewCanvasSize,
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

  Future<void> _setControllerZoomLevel(double zoom) async {
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }

    final clampedZoom = zoom.clamp(_minZoomLevel, _maxZoomLevel).toDouble();
    await controller.setZoomLevel(clampedZoom);
    if (!mounted) {
      return;
    }

    final logicalZoom = clampedZoom * _currentLensBaseZoom;
    final isFrontCamera =
        controller.description.lensDirection == CameraLensDirection.front;
    _seriesZoomPreference = logicalZoom;
    if (isFrontCamera) {
      _lastFrontLogicalZoomLevel = logicalZoom;
    } else {
      _lastBackLogicalZoomLevel = logicalZoom;
    }

    setState(() {
      _zoomLevel = logicalZoom;
    });
    _scheduleSeriesPreferencesSave();
  }

  Future<void> _setLogicalZoomLevel(double logicalZoom) async {
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }

    final clampedLogicalZoom = logicalZoom
        .clamp(_minimumLogicalZoom, _maximumLogicalZoom)
        .toDouble();
    if (_isFrontCameraActive || _rearCameraSystem == null) {
      await _setControllerZoomLevel(clampedLogicalZoom);
      return;
    }

    final plan = _resolveBackCameraLaunchPlan(
      clampedLogicalZoom,
      _rearCameraSystem!,
    );
    if (controller.description != plan.camera ||
        (_currentLensBaseZoom - plan.lensBaseZoom).abs() > 0.001) {
      await _startCamera(
        plan.camera,
        desiredControllerZoom: plan.desiredControllerZoom,
        lensBaseZoom: plan.lensBaseZoom,
      );
      return;
    }

    await _setControllerZoomLevel(plan.desiredControllerZoom);
  }

  Future<void> _adjustLogicalZoomBy(double delta) async {
    await _setLogicalZoomLevel(_zoomLevel + delta);
  }

  double get _minimumLogicalZoom {
    if (_isFrontCameraActive || _rearCameraSystem == null) {
      return _minZoomLevel * _currentLensBaseZoom;
    }

    final hasPhysicalUltraWide = _rearCameraSystem!.ultraWide != null;
    final hasDigitalUltraWide =
        (_currentLensBaseZoom - AppConstants.defaultZoomLevel).abs() < 0.001 &&
        _minZoomLevel < AppConstants.defaultZoomLevel;

    if ((_currentLensBaseZoom - _ZoomPreset.ultraWide.logicalZoom).abs() <
        0.001) {
      return _minZoomLevel * _currentLensBaseZoom;
    }

    if (hasDigitalUltraWide) {
      return _minZoomLevel;
    }

    if (hasPhysicalUltraWide) {
      return _ZoomPreset.ultraWide.logicalZoom;
    }

    return _minZoomLevel * _currentLensBaseZoom;
  }

  double get _maximumLogicalZoom {
    if (_isFrontCameraActive || _rearCameraSystem == null) {
      return _maxZoomLevel * _currentLensBaseZoom;
    }

    final baseMaximum = _maxZoomLevel * _currentLensBaseZoom;
    if (_rearCameraSystem!.telephoto != null) {
      return baseMaximum > _ZoomPreset.telephoto.logicalZoom
          ? baseMaximum
          : _ZoomPreset.telephoto.logicalZoom;
    }

    return baseMaximum;
  }

  String _zoomLabel(double logicalZoom) {
    return '${logicalZoom.toStringAsFixed(1)}x';
  }

  void _setViewportRatio(CaptureViewportRatio viewportRatio) {
    if (!_isFirstCapture || _viewportRatio == viewportRatio) {
      return;
    }

    setState(() {
      _viewportRatio = viewportRatio;
    });
    _scheduleSeriesPreferencesSave();
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

  void _requestCameraShortcutsFocus() {
    if (!mounted || _cameraShortcutsFocusNode.hasFocus) {
      return;
    }
    _cameraShortcutsFocusNode.requestFocus();
  }

  KeyEventResult _handleCameraKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey != LogicalKeyboardKey.audioVolumeDown) {
      return KeyEventResult.ignored;
    }

    unawaited(_captureFrame());
    return KeyEventResult.handled;
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
    final statusBadge = _statusBadgeData(settings);

    return Focus(
      focusNode: _cameraShortcutsFocusNode,
      autofocus: true,
      onKeyEvent: _handleCameraKeyEvent,
      child: Scaffold(
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
                  Positioned.fill(
                    child: ColoredBox(
                      color: Colors.black,
                      child: _buildPreviewSurface(controller, settings),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 0,
                    child: SafeArea(
                      bottom: false,
                      child: _buildTopControls(statusBadge: statusBadge),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: SafeArea(
                      top: false,
                      child: _buildBottomControls(
                        autoCaptureProgress: autoCaptureProgress,
                        statusBadge: statusBadge,
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
      ),
    );
  }

  Widget _buildPreviewSurface(
    CameraController controller,
    AppSettings settings,
  ) {
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
        controller.description.lensDirection == CameraLensDirection.front;

    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportRect = resolveCameraViewportRect(
          canvasSize: constraints.biggest,
          viewportRatio: _viewportRatio,
        );

        return GestureDetector(
          onTap: _requestCameraShortcutsFocus,
          onScaleStart: (_) {
            _baseLogicalZoomLevel = _zoomLevel;
          },
          onScaleUpdate: (details) {
            if (details.pointerCount < 2) {
              return;
            }
            unawaited(
              _setLogicalZoomLevel(_baseLogicalZoomLevel * details.scale),
            );
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              CameraPreviewViewport(
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
                          if (settings.showLiveSkeletonOverlay)
                            IgnorePointer(
                              child: CustomPaint(
                                painter: SkeletonPainter(
                                  landmarks: _latestLandmarks,
                                  imageSize: _latestFrameSize,
                                  rotation: _latestFrameRotation,
                                  lensDirection:
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
              if (shouldShowReferenceGuide)
                IgnorePointer(
                  child: CustomPaint(
                    painter: ReferenceGuidePainter(
                      referenceRecord: widget.referenceRecord!,
                      opacity: settings.referenceOverlayOpacity,
                      mirrorHorizontally: mirrorReferenceGuide,
                      viewportRect: viewportRect,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTopControls({required _StatusBadgeData? statusBadge}) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0.28),
            Colors.black.withValues(alpha: 0.08),
            Colors.transparent,
          ],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
        child: Row(
          children: [
            _UtilityIconButton(
              icon: Icons.close_rounded,
              onPressed: () => Navigator.of(context).maybePop(),
            ),
            Expanded(
              child: Center(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  child: statusBadge == null
                      ? const SizedBox.shrink()
                      : _StatusPill(
                          key: ValueKey(statusBadge.label),
                          label: statusBadge.label,
                          color: statusBadge.color,
                        ),
                ),
              ),
            ),
            if (_isFirstCapture)
              _AspectRatioMenuButton(
                viewportRatio: _viewportRatio,
                onSelected: _setViewportRatio,
              )
            else
              const SizedBox.square(dimension: 48),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomControls({
    required double autoCaptureProgress,
    required _StatusBadgeData? statusBadge,
  }) {
    final shutterColor = statusBadge?.color ?? Colors.white70;
    final canDecreaseZoom = _zoomLevel > (_minimumLogicalZoom + 0.01);
    final canIncreaseZoom = _zoomLevel < (_maximumLogicalZoom - 0.01);

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            Colors.black.withValues(alpha: 0.06),
            Colors.black.withValues(alpha: 0.36),
          ],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _CompactZoomControl(
                  label: _zoomLabel(_zoomLevel),
                  enabled: canDecreaseZoom || canIncreaseZoom,
                  canStepBackward: canDecreaseZoom,
                  canStepForward: canIncreaseZoom,
                  onAdjust: (direction) =>
                      unawaited(_adjustLogicalZoomBy(direction * 0.1)),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                const SizedBox(width: 52),
                Expanded(
                  child: Center(
                    child: _ShutterButton(
                      busy: _capturing,
                      semanticLabel: widget.referenceRecord == null
                          ? 'Capture first photo'
                          : 'Capture progress photo',
                      outlineColor: shutterColor,
                      onPressed: _capturing ? null : _captureFrame,
                    ),
                  ),
                ),
                SizedBox(
                  width: 52,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: _isFirstCapture
                        ? _UtilityIconButton(
                            icon: Icons.flip_camera_ios_rounded,
                            onPressed: _hasCameraDirections
                                ? _switchCamera
                                : null,
                          )
                        : const SizedBox.shrink(),
                  ),
                ),
              ],
            ),
            if (statusBadge != null && autoCaptureProgress > 0) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: 96,
                child: LinearProgressIndicator(
                  value: autoCaptureProgress,
                  minHeight: 3,
                  borderRadius: BorderRadius.circular(999),
                  color: statusBadge.color,
                  backgroundColor: Colors.white12,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  _StatusBadgeData? _statusBadgeData(AppSettings settings) {
    if (widget.referenceRecord == null) {
      return null;
    }
    if (_latestLandmarks.isEmpty) {
      return const _StatusBadgeData('Frame', Color(0xFF94A3B8));
    }
    if (!_canAutoCapture || !settings.autoCaptureEnabled) {
      return const _StatusBadgeData('Manual', Color(0xFF94A3B8));
    }
    if (_displayedAlignmentScore < settings.alignmentThreshold) {
      return const _StatusBadgeData('Align', Color(0xFFF59E0B));
    }
    if (_poseMotion > settings.stabilitySensitivity) {
      return const _StatusBadgeData('Hold', Color(0xFFFB923C));
    }

    final elapsedMs = _alignmentHeldSince == null
        ? 0
        : DateTime.now().difference(_alignmentHeldSince!).inMilliseconds;
    final remainingMs = (settings.autoCaptureDelay.inMilliseconds - elapsedMs)
        .clamp(0, settings.autoCaptureDelay.inMilliseconds);
    if (remainingMs == 0) {
      return const _StatusBadgeData('Ready', Color(0xFF22C55E));
    }
    return _StatusBadgeData(
      '${(remainingMs / 1000).toStringAsFixed(1)}s',
      const Color(0xFF22C55E),
    );
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

class _RearCameraSystem {
  const _RearCameraSystem({required this.wide, this.ultraWide, this.telephoto});

  final CameraDescription wide;
  final CameraDescription? ultraWide;
  final CameraDescription? telephoto;
}

class _BackCameraLaunchPlan {
  const _BackCameraLaunchPlan({
    required this.camera,
    required this.lensBaseZoom,
    required this.desiredControllerZoom,
  });

  final CameraDescription camera;
  final double lensBaseZoom;
  final double desiredControllerZoom;
}

enum _ZoomPreset {
  ultraWide(0.6, '0.6x'),
  wide(1.0, '1.0x'),
  telephoto(2.0, '2.0x');

  const _ZoomPreset(this.logicalZoom, this.label);

  final double logicalZoom;
  final String label;
}

class _StatusBadgeData {
  const _StatusBadgeData(this.label, this.color);

  final String label;
  final Color color;
}

class _AspectRatioMenuButton extends StatelessWidget {
  const _AspectRatioMenuButton({
    required this.viewportRatio,
    required this.onSelected,
  });

  final CaptureViewportRatio viewportRatio;
  final ValueChanged<CaptureViewportRatio> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final menuTextStyle = theme.textTheme.bodyMedium?.copyWith(
      color: const Color(0xFFF5F5F5),
      fontWeight: FontWeight.w600,
    );

    return Theme(
      data: theme.copyWith(
        colorScheme: theme.colorScheme.copyWith(
          surface: const Color(0xFF121212),
          onSurface: const Color(0xFFF5F5F5),
        ),
        popupMenuTheme: PopupMenuThemeData(
          color: const Color(0xFF121212),
          textStyle: menuTextStyle,
          labelTextStyle: WidgetStatePropertyAll(menuTextStyle),
        ),
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white12),
        ),
        child: PopupMenuButton<CaptureViewportRatio>(
          tooltip: 'Viewport settings',
          color: const Color(0xFF121212),
          position: PopupMenuPosition.under,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          onSelected: onSelected,
          icon: const Icon(Icons.tune_rounded, color: Colors.white),
          itemBuilder: (context) => [
            const PopupMenuItem<CaptureViewportRatio>(
              enabled: false,
              child: Text(
                'Aspect ratio',
                style: TextStyle(color: Color(0xFFBDBDBD)),
              ),
            ),
            ...CaptureViewportRatio.values.map(
              (ratio) => CheckedPopupMenuItem<CaptureViewportRatio>(
                value: ratio,
                checked: viewportRatio == ratio,
                child: Text(
                  ratio.label,
                  style: const TextStyle(color: Color(0xFFF5F5F5)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UtilityIconButton extends StatelessWidget {
  const _UtilityIconButton({required this.icon, required this.onPressed});

  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white12),
      ),
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon, color: Colors.white),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({super.key, required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white10),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              child: const SizedBox(width: 8, height: 8),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: Theme.of(context).textTheme.labelMedium
                  ?.copyWith(color: Colors.white, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

class _CompactZoomControl extends StatefulWidget {
  const _CompactZoomControl({
    required this.label,
    required this.enabled,
    required this.canStepBackward,
    required this.canStepForward,
    required this.onAdjust,
  });

  final String label;
  final bool enabled;
  final bool canStepBackward;
  final bool canStepForward;
  final ValueChanged<double> onAdjust;

  @override
  State<_CompactZoomControl> createState() => _CompactZoomControlState();
}

class _CompactZoomControlState extends State<_CompactZoomControl> {
  static const double _stepThreshold = 14;

  double _dragAccumulator = 0;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 160),
      opacity: widget.enabled ? 1.0 : 0.75,
      child: GestureDetector(
        onHorizontalDragStart: widget.enabled
            ? (_) {
                _dragAccumulator = 0;
              }
            : null,
        onHorizontalDragUpdate: widget.enabled
            ? (details) {
                _dragAccumulator += details.delta.dx;
                while (_dragAccumulator >= _stepThreshold) {
                  if (!widget.canStepForward) {
                    _dragAccumulator = 0;
                    break;
                  }
                  widget.onAdjust(0.1);
                  _dragAccumulator -= _stepThreshold;
                }
                while (_dragAccumulator <= -_stepThreshold) {
                  if (!widget.canStepBackward) {
                    _dragAccumulator = 0;
                    break;
                  }
                  widget.onAdjust(-0.1);
                  _dragAccumulator += _stepThreshold;
                }
              }
            : null,
        onHorizontalDragEnd: widget.enabled
            ? (_) {
                _dragAccumulator = 0;
              }
            : null,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.white12),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  onTap: widget.canStepBackward
                      ? () => widget.onAdjust(-0.1)
                      : null,
                  child: Icon(
                    Icons.remove_rounded,
                    size: 18,
                    color: widget.canStepBackward
                        ? Colors.white70
                        : Colors.white24,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  widget.label,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: widget.canStepForward
                      ? () => widget.onAdjust(0.1)
                      : null,
                  child: Icon(
                    Icons.add_rounded,
                    size: 18,
                    color: widget.canStepForward
                        ? Colors.white70
                        : Colors.white24,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ShutterButton extends StatelessWidget {
  const _ShutterButton({
    required this.busy,
    required this.semanticLabel,
    required this.outlineColor,
    required this.onPressed,
  });

  final bool busy;
  final String semanticLabel;
  final Color outlineColor;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel,
      child: GestureDetector(
        onTap: onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: outlineColor, width: 4),
            boxShadow: [
              BoxShadow(
                color: outlineColor.withValues(alpha: 0.18),
                blurRadius: 14,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: busy ? Colors.white70 : Colors.white,
              ),
              child: SizedBox(
                width: 66,
                height: 66,
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
