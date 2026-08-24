import 'package:flutter/material.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

class PosePreviewCoordinateTransformer {
  const PosePreviewCoordinateTransformer({
    required this.imageSize,
    required this.rotation,
  });

  final Size imageSize;
  final InputImageRotation rotation;

  Offset project({
    required double x,
    required double y,
    required Size canvasSize,
  }) {
    return _rotateToPreview(x: x, y: y, canvasSize: canvasSize);
  }

  Offset _rotateToPreview({
    required double x,
    required double y,
    required Size canvasSize,
  }) {
    switch (rotation) {
      case InputImageRotation.rotation90deg:
        return Offset(
          x * canvasSize.width / imageSize.height,
          y * canvasSize.height / imageSize.width,
        );
      case InputImageRotation.rotation270deg:
        return Offset(
          canvasSize.width - x * canvasSize.width / imageSize.height,
          y * canvasSize.height / imageSize.width,
        );
      case InputImageRotation.rotation0deg:
      case InputImageRotation.rotation180deg:
        return Offset(
          x * canvasSize.width / imageSize.width,
          y * canvasSize.height / imageSize.height,
        );
    }
  }
}
