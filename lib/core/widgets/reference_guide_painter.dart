import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../data/models/pose_record.dart';
import '../utils/pose_skeleton_graph.dart';
import '../utils/reference_skeleton_transformer.dart';

class ReferenceGuidePainter extends CustomPainter {
  ReferenceGuidePainter({
    required this.referenceRecord,
    required this.opacity,
    required this.mirrorHorizontally,
    this.viewportRect,
    this.pointColor = const Color(0xFFFDE68A),
    this.lineColor = const Color(0xFFF97316),
  });

  static const ReferenceSkeletonTransformer _transformer =
      ReferenceSkeletonTransformer();

  final PoseRecord referenceRecord;
  final double opacity;
  final bool mirrorHorizontally;
  final Rect? viewportRect;
  final Color pointColor;
  final Color lineColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (!referenceRecord.hasSourceDimensions ||
        referenceRecord.landmarks.isEmpty) {
      return;
    }

    final transformedReference = _transformer.transform(referenceRecord);
    final renderedLandmarks = transformedReference.landmarks;
    if (renderedLandmarks.isEmpty) {
      return;
    }

    final targetRect = viewportRect ?? (Offset.zero & size);
    if (targetRect.isEmpty) {
      return;
    }

    canvas.save();
    canvas.clipRect(targetRect);

    final projection = _resolveProjection(
      targetRect: targetRect,
      referenceWidth: transformedReference.imageWidth.toDouble(),
      referenceHeight: transformedReference.imageHeight.toDouble(),
    );

    final projectedOffsets = <String, Offset>{};
    for (final landmark in renderedLandmarks) {
      final sourceX = mirrorHorizontally
          ? transformedReference.imageWidth.toDouble() - landmark.x
          : landmark.x;
      projectedOffsets[landmark.type] = Offset(
        projection.left + (sourceX * projection.scale),
        projection.top + (landmark.y * projection.scale),
      );
    }

    final linePaint = Paint()
      ..color = lineColor.withValues(alpha: opacity.clamp(0.0, 1.0) * 0.92)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round;
    final pointPaint = Paint()..style = PaintingStyle.fill;

    for (final connection in PoseSkeletonGraph.visibleConnections(
      renderedLandmarks,
    )) {
      final start = projectedOffsets[connection.startType];
      final end = projectedOffsets[connection.endType];
      if (start == null || end == null) {
        continue;
      }
      canvas.drawLine(start, end, linePaint);
    }

    for (final landmark in renderedLandmarks) {
      final offset = projectedOffsets[landmark.type];
      if (offset == null) {
        continue;
      }
      pointPaint.color = pointColor.withValues(
        alpha: opacity.clamp(0.0, 1.0) * 0.95,
      );
      canvas.drawCircle(offset, 3.6, pointPaint);
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant ReferenceGuidePainter oldDelegate) {
    return oldDelegate.referenceRecord != referenceRecord ||
        oldDelegate.opacity != opacity ||
        oldDelegate.mirrorHorizontally != mirrorHorizontally ||
        oldDelegate.viewportRect != viewportRect ||
        oldDelegate.pointColor != pointColor ||
        oldDelegate.lineColor != lineColor;
  }

  _ReferenceProjection _resolveProjection({
    required Rect targetRect,
    required double referenceWidth,
    required double referenceHeight,
  }) {
    final safeReferenceWidth = math.max(referenceWidth, 1.0);
    final safeReferenceHeight = math.max(referenceHeight, 1.0);
    final scale = math.max(
      targetRect.width / safeReferenceWidth,
      targetRect.height / safeReferenceHeight,
    );
    final fittedWidth = safeReferenceWidth * scale;
    final fittedHeight = safeReferenceHeight * scale;
    return _ReferenceProjection(
      scale: scale,
      left: targetRect.left + ((targetRect.width - fittedWidth) / 2),
      top: targetRect.top + ((targetRect.height - fittedHeight) / 2),
    );
  }
}

class _ReferenceProjection {
  const _ReferenceProjection({
    required this.scale,
    required this.left,
    required this.top,
  });

  final double scale;
  final double left;
  final double top;
}
