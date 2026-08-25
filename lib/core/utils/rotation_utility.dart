import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:native_device_orientation/native_device_orientation.dart';

import '../../data/models/capture_viewport_ratio.dart';
import '../../data/models/capture_orientation.dart';
import 'camera_viewport_geometry.dart';

class RotationUtility {
  RotationUtility({
    NativeDeviceOrientationCommunicator? orientationCommunicator,
  }) : _orientationCommunicator =
           orientationCommunicator ?? NativeDeviceOrientationCommunicator();

  final NativeDeviceOrientationCommunicator _orientationCommunicator;

  Future<RotatedCaptureResult> transformJpegForStorage({
    required Uint8List jpegBytes,
    required DeviceOrientation fallbackOrientation,
    CaptureViewportRatio viewportRatio = CaptureViewportRatio.full,
    Size? previewCanvasSize,
  }) async {
    final physicalOrientation = _deviceOrientationForFallback(
      fallbackOrientation,
    );
    final storedOrientation = _captureOrientationForFallback(
      fallbackOrientation,
    );
    final decoded = img.decodeJpg(jpegBytes) ?? img.decodeImage(jpegBytes);
    if (decoded == null) {
      return RotatedCaptureResult(
        bytes: jpegBytes,
        storedOrientation: storedOrientation,
        physicalOrientation: physicalOrientation,
      );
    }

    final bakedImage = img.bakeOrientation(decoded);
    final croppedImage = _cropForViewport(
      bakedImage,
      storedOrientation: storedOrientation,
      viewportRatio: viewportRatio,
      previewCanvasSize: previewCanvasSize,
    );

    return RotatedCaptureResult(
      bytes: Uint8List.fromList(img.encodeJpg(croppedImage, quality: 94)),
      storedOrientation: storedOrientation,
      physicalOrientation: physicalOrientation,
    );
  }

  img.Image _cropForViewport(
    img.Image source, {
    required CaptureOrientation storedOrientation,
    required CaptureViewportRatio viewportRatio,
    required Size? previewCanvasSize,
  }) {
    if (previewCanvasSize == null ||
        previewCanvasSize.isEmpty ||
        viewportRatio.isFull) {
      return source;
    }

    final rawSize = Size(source.width.toDouble(), source.height.toDouble());
    final displayQuarterTurns = storedOrientation.quarterTurnsForDisplay(
      rawWidth: source.width,
      rawHeight: source.height,
    );
    final displaySize = displayQuarterTurns.isOdd
        ? Size(rawSize.height, rawSize.width)
        : rawSize;
    final displayCropRect = resolveViewportCropRectInDisplaySpace(
      previewCanvasSize: previewCanvasSize,
      displayImageSize: displaySize,
      viewportRatio: viewportRatio,
    );
    final rawCropRect = mapDisplayRectToRawImageRect(
      displayRect: displayCropRect,
      rawImageSize: rawSize,
      quarterTurns: displayQuarterTurns,
    );

    final left = rawCropRect.left.floor().clamp(0, source.width - 1);
    final top = rawCropRect.top.floor().clamp(0, source.height - 1);
    final right = rawCropRect.right.ceil().clamp(left + 1, source.width);
    final bottom = rawCropRect.bottom.ceil().clamp(top + 1, source.height);
    final cropWidth = math.max(1, right - left);
    final cropHeight = math.max(1, bottom - top);

    if (cropWidth >= source.width && cropHeight >= source.height) {
      return source;
    }

    return img.copyCrop(
      source,
      x: left,
      y: top,
      width: cropWidth,
      height: cropHeight,
    );
  }

  Future<NativeDeviceOrientation> readPhysicalOrientation() async {
    final orientation = await _orientationCommunicator.orientation(
      useSensor: true,
    );
    return orientation;
  }

  CaptureOrientation _captureOrientationForFallback(
    DeviceOrientation fallbackOrientation,
  ) {
    switch (fallbackOrientation) {
      case DeviceOrientation.portraitUp:
        return CaptureOrientation.portrait;
      case DeviceOrientation.landscapeLeft:
        return CaptureOrientation.landscapeLeft;
      case DeviceOrientation.portraitDown:
        return CaptureOrientation.portraitDown;
      case DeviceOrientation.landscapeRight:
        return CaptureOrientation.landscapeRight;
    }
  }

  NativeDeviceOrientation _deviceOrientationForFallback(
    DeviceOrientation fallbackOrientation,
  ) {
    switch (fallbackOrientation) {
      case DeviceOrientation.portraitUp:
        return NativeDeviceOrientation.portraitUp;
      case DeviceOrientation.landscapeLeft:
        return NativeDeviceOrientation.landscapeLeft;
      case DeviceOrientation.portraitDown:
        return NativeDeviceOrientation.portraitDown;
      case DeviceOrientation.landscapeRight:
        return NativeDeviceOrientation.landscapeRight;
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
