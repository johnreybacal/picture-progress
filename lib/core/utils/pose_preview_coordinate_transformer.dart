import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

class PosePreviewCoordinateTransformer {
  const PosePreviewCoordinateTransformer({
    required this.imageSize,
    required this.rotation,
    required this.lensDirection,
  });

  final Size imageSize;
  final InputImageRotation rotation;
  final CameraLensDirection lensDirection;

  Offset project({
    required double x,
    required double y,
    required Size canvasSize,
  }) {
    return Offset(_translateX(x, canvasSize), _translateY(y, canvasSize));
  }

  double _translateX(double x, Size canvasSize) {
    switch (rotation) {
      case InputImageRotation.rotation90deg:
        return x *
            canvasSize.width /
            (Platform.isIOS ? imageSize.width : imageSize.height);
      case InputImageRotation.rotation270deg:
        return canvasSize.width -
            x *
                canvasSize.width /
                (Platform.isIOS ? imageSize.width : imageSize.height);
      case InputImageRotation.rotation0deg:
      case InputImageRotation.rotation180deg:
        switch (lensDirection) {
          case CameraLensDirection.back:
          case CameraLensDirection.external:
            return x * canvasSize.width / imageSize.width;
          case CameraLensDirection.front:
            return canvasSize.width - x * canvasSize.width / imageSize.width;
        }
    }
  }

  double _translateY(double y, Size canvasSize) {
    switch (rotation) {
      case InputImageRotation.rotation90deg:
      case InputImageRotation.rotation270deg:
        return y *
            canvasSize.height /
            (Platform.isIOS ? imageSize.height : imageSize.width);
      case InputImageRotation.rotation0deg:
      case InputImageRotation.rotation180deg:
        return y * canvasSize.height / imageSize.height;
    }
  }
}
