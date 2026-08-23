import 'dart:io';
import 'dart:math';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import '../utils/pose_skeleton_graph.dart';
import '../../data/models/pose_landmark_point.dart';

class LivePoseSkeletonPainter extends CustomPainter {
  LivePoseSkeletonPainter({
    required this.landmarks,
    required this.imageSize,
    required this.rotation,
    required this.cameraLensDirection,
    this.pointColor = const Color(0xFF5EEAD4),
    this.lineColor = const Color(0xFF34D399),
  });

  final List<PoseLandmarkPoint> landmarks;
  final Size imageSize;
  final InputImageRotation rotation;
  final CameraLensDirection cameraLensDirection;
  final Color pointColor;
  final Color lineColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (landmarks.isEmpty || imageSize.isEmpty) {
      return;
    }

    final pointPaint = Paint()
      ..color = pointColor
      ..style = PaintingStyle.fill
      ..strokeCap = StrokeCap.round;
    final linePaint = Paint()
      ..color = lineColor.withValues(alpha: 0.82)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.2
      ..strokeCap = StrokeCap.round;

    final indexedLandmarks = PoseSkeletonGraph.indexByType(landmarks);
    for (final connection in PoseSkeletonGraph.visibleConnections(landmarks)) {
      final start = indexedLandmarks[connection.startType]!;
      final end = indexedLandmarks[connection.endType]!;
      canvas.drawLine(
        Offset(_translateX(start.x, size), _translateY(start.y, size)),
        Offset(_translateX(end.x, size), _translateY(end.y, size)),
        linePaint,
      );
    }

    for (final landmark in landmarks) {
      final depthFactor = (1 - (landmark.z / 800).clamp(-0.5, 0.8)).toDouble();
      final radius = max(2.4, 4.2 * depthFactor);
      pointPaint.color = pointColor.withValues(
        alpha: landmark.likelihood.clamp(0.35, 1.0).toDouble(),
      );
      canvas.drawCircle(
        Offset(_translateX(landmark.x, size), _translateY(landmark.y, size)),
        radius,
        pointPaint,
      );
    }
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
        switch (cameraLensDirection) {
          case CameraLensDirection.back:
            return x * canvasSize.width / imageSize.width;
          case CameraLensDirection.front:
          case CameraLensDirection.external:
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

  @override
  bool shouldRepaint(covariant LivePoseSkeletonPainter oldDelegate) {
    return oldDelegate.landmarks != landmarks ||
        oldDelegate.imageSize != imageSize ||
        oldDelegate.rotation != rotation ||
        oldDelegate.cameraLensDirection != cameraLensDirection ||
        oldDelegate.pointColor != pointColor ||
        oldDelegate.lineColor != lineColor;
  }
}

class StoredPoseSkeletonPainter extends CustomPainter {
  StoredPoseSkeletonPainter({
    required this.landmarks,
    required this.imageSize,
    this.fit = BoxFit.cover,
    this.pointColor = const Color(0xFFFDE68A),
    this.lineColor = const Color(0xFF22C55E),
  });

  final List<PoseLandmarkPoint> landmarks;
  final Size imageSize;
  final BoxFit fit;
  final Color pointColor;
  final Color lineColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (landmarks.isEmpty || imageSize.isEmpty) {
      return;
    }

    final sourceRect = Offset.zero & imageSize;
    final fitted = applyBoxFit(fit, imageSize, size);
    final inputRect = Alignment.center.inscribe(fitted.source, sourceRect);
    final outputRect = Alignment.center.inscribe(
      fitted.destination,
      Offset.zero & size,
    );

    final indexedLandmarks = PoseSkeletonGraph.indexByType(landmarks);
    final linePaint = Paint()
      ..color = lineColor.withValues(alpha: 0.88)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = max(1.8, size.shortestSide * 0.022);
    final pointPaint = Paint()..style = PaintingStyle.fill;

    for (final connection in PoseSkeletonGraph.visibleConnections(landmarks)) {
      final start = indexedLandmarks[connection.startType]!;
      final end = indexedLandmarks[connection.endType]!;
      final startOffset = _mapOffset(start, inputRect, outputRect);
      final endOffset = _mapOffset(end, inputRect, outputRect);
      if (startOffset == null || endOffset == null) {
        continue;
      }
      canvas.drawLine(startOffset, endOffset, linePaint);
    }

    for (final landmark in landmarks) {
      final offset = _mapOffset(landmark, inputRect, outputRect);
      if (offset == null) {
        continue;
      }
      pointPaint.color = pointColor.withValues(
        alpha: landmark.likelihood.clamp(0.4, 1.0).toDouble(),
      );
      canvas.drawCircle(
        offset,
        max(1.8, size.shortestSide * 0.028),
        pointPaint,
      );
    }
  }

  Offset? _mapOffset(
    PoseLandmarkPoint landmark,
    Rect inputRect,
    Rect outputRect,
  ) {
    if (!inputRect.contains(Offset(landmark.x, landmark.y))) {
      return null;
    }

    final dx = (landmark.x - inputRect.left) / inputRect.width;
    final dy = (landmark.y - inputRect.top) / inputRect.height;
    return Offset(
      outputRect.left + (dx * outputRect.width),
      outputRect.top + (dy * outputRect.height),
    );
  }

  @override
  bool shouldRepaint(covariant StoredPoseSkeletonPainter oldDelegate) {
    return oldDelegate.landmarks != landmarks ||
        oldDelegate.imageSize != imageSize ||
        oldDelegate.fit != fit ||
        oldDelegate.pointColor != pointColor ||
        oldDelegate.lineColor != lineColor;
  }
}
