import 'dart:io';
import 'dart:math';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import '../constants/app_constants.dart';
import '../utils/pose_skeleton_graph.dart';
import '../../data/models/pose_landmark_point.dart';

class SkeletonPainter extends CustomPainter {
  SkeletonPainter({
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

    final projectedLandmarks = <String, _ProjectedLandmark>{};
    for (final landmark in landmarks) {
      if (landmark.likelihood < AppConstants.minimumLandmarkLikelihood) {
        continue;
      }

      final offset = Offset(
        _translateX(landmark.x, size),
        _translateY(landmark.y, size),
      );
      if (!_isInsideCanvas(offset, size)) {
        continue;
      }
      projectedLandmarks[landmark.type] = _ProjectedLandmark(landmark, offset);
    }

    if (projectedLandmarks.isEmpty) {
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

    final visibleLandmarks = projectedLandmarks.values
        .map((entry) => entry.landmark)
        .toList(growable: false);
    for (final connection in PoseSkeletonGraph.visibleConnections(
      visibleLandmarks,
    )) {
      final start = projectedLandmarks[connection.startType]!;
      final end = projectedLandmarks[connection.endType]!;
      canvas.drawLine(start.offset, end.offset, linePaint);
    }

    for (final entry in projectedLandmarks.values) {
      final landmark = entry.landmark;
      final depthFactor = (1 - (landmark.z / 800).clamp(-0.5, 0.8)).toDouble();
      final radius = max(2.4, 4.2 * depthFactor);
      pointPaint.color = pointColor.withValues(
        alpha: landmark.likelihood
            .clamp(AppConstants.minimumLandmarkLikelihood, 1.0)
            .toDouble(),
      );
      canvas.drawCircle(entry.offset, radius, pointPaint);
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

  bool _isInsideCanvas(Offset offset, Size size) {
    return offset.dx >= 0 &&
        offset.dx <= size.width &&
        offset.dy >= 0 &&
        offset.dy <= size.height;
  }

  @override
  bool shouldRepaint(covariant SkeletonPainter oldDelegate) {
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

    final projectedLandmarks = <String, _ProjectedLandmark>{};
    for (final landmark in landmarks) {
      if (landmark.likelihood < AppConstants.minimumLandmarkLikelihood) {
        continue;
      }

      final offset = _mapOffset(landmark, inputRect, outputRect);
      if (offset == null || !_isInsideCanvas(offset, size)) {
        continue;
      }
      projectedLandmarks[landmark.type] = _ProjectedLandmark(landmark, offset);
    }

    if (projectedLandmarks.isEmpty) {
      return;
    }

    final linePaint = Paint()
      ..color = lineColor.withValues(alpha: 0.88)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = max(1.8, size.shortestSide * 0.022);
    final pointPaint = Paint()..style = PaintingStyle.fill;

    final visibleLandmarks = projectedLandmarks.values
        .map((entry) => entry.landmark)
        .toList(growable: false);
    for (final connection in PoseSkeletonGraph.visibleConnections(
      visibleLandmarks,
    )) {
      final start = projectedLandmarks[connection.startType]!;
      final end = projectedLandmarks[connection.endType]!;
      canvas.drawLine(start.offset, end.offset, linePaint);
    }

    for (final entry in projectedLandmarks.values) {
      final landmark = entry.landmark;
      pointPaint.color = pointColor.withValues(
        alpha: landmark.likelihood
            .clamp(AppConstants.minimumLandmarkLikelihood, 1.0)
            .toDouble(),
      );
      canvas.drawCircle(
        entry.offset,
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

  bool _isInsideCanvas(Offset offset, Size size) {
    return offset.dx >= 0 &&
        offset.dx <= size.width &&
        offset.dy >= 0 &&
        offset.dy <= size.height;
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

class _ProjectedLandmark {
  const _ProjectedLandmark(this.landmark, this.offset);

  final PoseLandmarkPoint landmark;
  final Offset offset;
}
