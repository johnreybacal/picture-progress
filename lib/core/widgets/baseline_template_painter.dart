import 'dart:math';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import '../constants/app_constants.dart';
import '../utils/pose_alignment_engine.dart';
import '../utils/pose_skeleton_graph.dart';
import '../../data/models/pose_landmark_point.dart';
import '../../data/models/pose_record.dart';

class BaselineGuidePainter extends CustomPainter {
  BaselineGuidePainter({
    required this.baselineRecord,
    required this.liveLandmarks,
    required this.liveImageSize,
    required this.liveRotation,
    required this.cameraLensDirection,
    required this.opacity,
    required this.mirrorHorizontally,
    this.pointColor = const Color(0xFFFDE68A),
    this.lineColor = const Color(0xFFF97316),
  });

  final PoseRecord baselineRecord;
  final List<PoseLandmarkPoint> liveLandmarks;
  final Size liveImageSize;
  final InputImageRotation liveRotation;
  final CameraLensDirection cameraLensDirection;
  final double opacity;
  final bool mirrorHorizontally;
  final Color pointColor;
  final Color lineColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (!baselineRecord.hasSourceDimensions ||
        baselineRecord.landmarks.isEmpty) {
      return;
    }

    final landmarks = baselineRecord.displayLandmarks();
    final visibleLandmarks = landmarks
        .where(
          (landmark) =>
              landmark.likelihood >= AppConstants.minimumLandmarkLikelihood,
        )
        .toList(growable: false);
    if (visibleLandmarks.length < 6) {
      return;
    }

    final anchor = baselineRecord.displayAnchorCenter();
    final baselineScale = max(PoseGeometry.bodyScaleFor(visibleLandmarks), 1.0);
    final liveProjection = _resolveLiveProjection(size);
    final anchorOffset = liveProjection.anchorOffset;
    final projectedBodyHeight = liveProjection.bodyScale;

    final projected = <String, Offset>{};
    for (final landmark in visibleLandmarks) {
      final normalizedX = (landmark.x - anchor.x) / baselineScale;
      final normalizedY = (landmark.y - anchor.y) / baselineScale;
      final direction = mirrorHorizontally ? -1.0 : 1.0;
      projected[landmark.type] = Offset(
        anchorOffset.dx + (normalizedX * projectedBodyHeight * direction),
        anchorOffset.dy + (normalizedY * projectedBodyHeight),
      );
    }

    final linePaint = Paint()
      ..color = lineColor.withValues(alpha: opacity.clamp(0.0, 1.0) * 0.92)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round;
    final pointPaint = Paint()..style = PaintingStyle.fill;

    for (final connection in PoseSkeletonGraph.visibleConnections(
      visibleLandmarks,
    )) {
      final start = projected[connection.startType];
      final end = projected[connection.endType];
      if (start == null || end == null) {
        continue;
      }
      canvas.drawLine(start, end, linePaint);
    }

    for (final landmark in visibleLandmarks) {
      final offset = projected[landmark.type];
      if (offset == null) {
        continue;
      }
      pointPaint.color = pointColor.withValues(
        alpha: opacity.clamp(0.0, 1.0) * 0.95,
      );
      canvas.drawCircle(offset, 3.6, pointPaint);
    }
  }

  @override
  bool shouldRepaint(covariant BaselineGuidePainter oldDelegate) {
    return oldDelegate.baselineRecord != baselineRecord ||
        oldDelegate.liveLandmarks != liveLandmarks ||
        oldDelegate.liveImageSize != liveImageSize ||
        oldDelegate.liveRotation != liveRotation ||
        oldDelegate.cameraLensDirection != cameraLensDirection ||
        oldDelegate.opacity != opacity ||
        oldDelegate.mirrorHorizontally != mirrorHorizontally ||
        oldDelegate.pointColor != pointColor ||
        oldDelegate.lineColor != lineColor;
  }

  _LiveProjection _resolveLiveProjection(Size canvasSize) {
    final visibleLiveLandmarks = liveLandmarks
        .where(
          (landmark) =>
              landmark.likelihood >= AppConstants.minimumLandmarkLikelihood,
        )
        .toList(growable: false);
    if (visibleLiveLandmarks.isEmpty || liveImageSize.isEmpty) {
      return _fallbackProjection(canvasSize);
    }

    final projectedByType = <String, Offset>{};
    for (final landmark in visibleLiveLandmarks) {
      projectedByType[landmark.type] = Offset(
        _translateX(landmark.x, canvasSize),
        _translateY(landmark.y, canvasSize),
      );
    }

    final anchorPoint = PoseGeometry.anchorFor(visibleLiveLandmarks);
    final anchorOffset = Offset(
      _translateX(anchorPoint.x, canvasSize),
      _translateY(anchorPoint.y, canvasSize),
    );
    final bodyScale = _liveBodyScale(projectedByType);
    if (bodyScale <= 0) {
      return _fallbackProjection(canvasSize);
    }

    return _LiveProjection(anchorOffset: anchorOffset, bodyScale: bodyScale);
  }

  _LiveProjection _fallbackProjection(Size canvasSize) {
    final boundingBox = baselineRecord.displayBoundingBox();
    final displayHeight = max(
      baselineRecord.displayImageHeight.toDouble(),
      1.0,
    );
    final normalizedBodyHeight = (boundingBox.height / displayHeight).clamp(
      0.28,
      0.72,
    );
    return _LiveProjection(
      anchorOffset: Offset(
        canvasSize.width * AppConstants.targetAnchorX,
        canvasSize.height * AppConstants.targetAnchorY,
      ),
      bodyScale: canvasSize.height * normalizedBodyHeight,
    );
  }

  double _liveBodyScale(Map<String, Offset> projectedByType) {
    final shoulderMidpoint = _projectedMidpoint(
      projectedByType,
      'leftShoulder',
      'rightShoulder',
    );
    final hipMidpoint = _projectedMidpoint(
      projectedByType,
      'leftHip',
      'rightHip',
    );
    if (shoulderMidpoint != null && hipMidpoint != null) {
      return (hipMidpoint - shoulderMidpoint).distance;
    }

    final projectedOffsets = projectedByType.values.toList(growable: false);
    if (projectedOffsets.isEmpty) {
      return 0;
    }
    final xs = projectedOffsets
        .map((offset) => offset.dx)
        .toList(growable: false);
    final ys = projectedOffsets
        .map((offset) => offset.dy)
        .toList(growable: false);
    return max(
      xs.reduce(max) - xs.reduce(min),
      ys.reduce(max) - ys.reduce(min),
    );
  }

  Offset? _projectedMidpoint(
    Map<String, Offset> projectedByType,
    String firstType,
    String secondType,
  ) {
    final first = projectedByType[firstType];
    final second = projectedByType[secondType];
    if (first == null || second == null) {
      return null;
    }

    return Offset((first.dx + second.dx) / 2, (first.dy + second.dy) / 2);
  }

  double _translateX(double x, Size canvasSize) {
    switch (liveRotation) {
      case InputImageRotation.rotation90deg:
        return x * canvasSize.width / liveImageSize.height;
      case InputImageRotation.rotation270deg:
        return canvasSize.width - x * canvasSize.width / liveImageSize.height;
      case InputImageRotation.rotation0deg:
      case InputImageRotation.rotation180deg:
        switch (cameraLensDirection) {
          case CameraLensDirection.back:
            return x * canvasSize.width / liveImageSize.width;
          case CameraLensDirection.front:
          case CameraLensDirection.external:
            return canvasSize.width -
                x * canvasSize.width / liveImageSize.width;
        }
    }
  }

  double _translateY(double y, Size canvasSize) {
    switch (liveRotation) {
      case InputImageRotation.rotation90deg:
      case InputImageRotation.rotation270deg:
        return y * canvasSize.height / liveImageSize.width;
      case InputImageRotation.rotation0deg:
      case InputImageRotation.rotation180deg:
        return y * canvasSize.height / liveImageSize.height;
    }
  }
}

class BaselineTemplatePainter extends BaselineGuidePainter {
  BaselineTemplatePainter({
    required super.baselineRecord,
    required super.liveLandmarks,
    required super.liveImageSize,
    required super.liveRotation,
    required super.cameraLensDirection,
    required super.opacity,
    required super.mirrorHorizontally,
    super.pointColor,
    super.lineColor,
  });
}

class _LiveProjection {
  const _LiveProjection({required this.anchorOffset, required this.bodyScale});

  final Offset anchorOffset;
  final double bodyScale;
}
