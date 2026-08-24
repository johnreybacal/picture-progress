import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:native_device_orientation/native_device_orientation.dart';

import '../../data/models/capture_orientation.dart';

class RotationUtility {
  RotationUtility({
    NativeDeviceOrientationCommunicator? orientationCommunicator,
  }) : _orientationCommunicator =
           orientationCommunicator ?? NativeDeviceOrientationCommunicator();

  final NativeDeviceOrientationCommunicator _orientationCommunicator;

  Future<RotatedCaptureResult> transformJpegForStorage({
    required Uint8List jpegBytes,
    required DeviceOrientation fallbackOrientation,
  }) async {
    final physicalOrientation = await readPhysicalOrientation();
    final decoded = img.decodeJpg(jpegBytes) ?? img.decodeImage(jpegBytes);
    if (decoded == null) {
      return RotatedCaptureResult(
        bytes: jpegBytes,
        storedOrientation: CaptureOrientation.portrait,
        physicalOrientation: physicalOrientation,
      );
    }

    final bakedImage = img.bakeOrientation(decoded);
    final rotationDegrees = _portraitNormalizationDegrees(
      physicalOrientation,
      fallbackOrientation,
    );
    final rotatedImage = rotationDegrees == 0
        ? bakedImage
        : img.copyRotate(bakedImage, angle: rotationDegrees);

    return RotatedCaptureResult(
      bytes: Uint8List.fromList(img.encodeJpg(rotatedImage, quality: 94)),
      storedOrientation: CaptureOrientation.portrait,
      physicalOrientation: physicalOrientation,
    );
  }

  Future<NativeDeviceOrientation> readPhysicalOrientation() async {
    final orientation = await _orientationCommunicator.orientation(
      useSensor: true,
    );
    return orientation;
  }

  int _portraitNormalizationDegrees(
    NativeDeviceOrientation physicalOrientation,
    DeviceOrientation fallbackOrientation,
  ) {
    return _degreesForOrientation(physicalOrientation, fallbackOrientation);
  }

  int _degreesForOrientation(
    NativeDeviceOrientation orientation,
    DeviceOrientation fallbackOrientation,
  ) {
    switch (orientation) {
      case NativeDeviceOrientation.portraitUp:
        return 0;
      case NativeDeviceOrientation.landscapeLeft:
        return 90;
      case NativeDeviceOrientation.portraitDown:
        return 180;
      case NativeDeviceOrientation.landscapeRight:
        return 270;
      case NativeDeviceOrientation.unknown:
        return _degreesForFallback(fallbackOrientation);
    }
  }

  int _degreesForFallback(DeviceOrientation orientation) {
    switch (orientation) {
      case DeviceOrientation.portraitUp:
        return 0;
      case DeviceOrientation.landscapeLeft:
        return 90;
      case DeviceOrientation.portraitDown:
        return 180;
      case DeviceOrientation.landscapeRight:
        return 270;
    }
  }
}

class RotatedCaptureResult {
  const RotatedCaptureResult({
    required this.bytes,
    required this.storedOrientation,
    required this.physicalOrientation,
  });

  final Uint8List bytes;
  final CaptureOrientation storedOrientation;
  final NativeDeviceOrientation physicalOrientation;
}
