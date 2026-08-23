import 'dart:math';

import 'package:flutter/material.dart';

import '../constants/app_constants.dart';
import '../utils/pose_skeleton_graph.dart';
import '../../data/models/pose_record.dart';

class BaselineTemplatePainter extends CustomPainter {
  BaselineTemplatePainter({
    required this.baselineRecord,
    required this.opacity,
    required this.mirrorHorizontally,
    this.pointColor = const Color(0xFFFDE68A),
    this.lineColor = const Color(0xFFF97316),
  });

  final PoseRecord baselineRecord;
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
    final boundingBox = baselineRecord.displayBoundingBox();
    final displayHeight = max(
      baselineRecord.displayImageHeight.toDouble(),
      1.0,
    );
    final normalizedBodyHeight = (boundingBox.height / displayHeight).clamp(
      0.28,
      0.72,
    );
    final projectedBodyHeight = size.height * normalizedBodyHeight;
    final scale = max(max(boundingBox.height, boundingBox.width), 1.0);
    final anchorOffset = Offset(
      size.width * AppConstants.targetAnchorX,
      size.height * AppConstants.targetAnchorY,
    );

    final projected = <String, Offset>{};
    for (final landmark in visibleLandmarks) {
      final normalizedX = (landmark.x - anchor.x) / scale;
      final normalizedY = (landmark.y - anchor.y) / scale;
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
  bool shouldRepaint(covariant BaselineTemplatePainter oldDelegate) {
    return oldDelegate.baselineRecord != baselineRecord ||
        oldDelegate.opacity != opacity ||
        oldDelegate.mirrorHorizontally != mirrorHorizontally ||
        oldDelegate.pointColor != pointColor ||
        oldDelegate.lineColor != lineColor;
  }
}
