import 'dart:math' as math;
import 'dart:ui';

import '../../data/models/capture_viewport_ratio.dart';

Rect resolveCameraViewportRect({
  required Size canvasSize,
  required CaptureViewportRatio viewportRatio,
}) {
  if (canvasSize.isEmpty ||
      viewportRatio.isFull ||
      viewportRatio.aspectRatio == null) {
    return Offset.zero & canvasSize;
  }

  final targetAspectRatio = viewportRatio.aspectRatio!;
  final fittedHeight = canvasSize.width / targetAspectRatio;
  if (fittedHeight <= canvasSize.height) {
    final top = (canvasSize.height - fittedHeight) / 2;
    return Rect.fromLTWH(0, top, canvasSize.width, fittedHeight);
  }

  final fittedWidth = canvasSize.height * targetAspectRatio;
  final left = (canvasSize.width - fittedWidth) / 2;
  return Rect.fromLTWH(left, 0, fittedWidth, canvasSize.height);
}

Rect resolveViewportCropRectInDisplaySpace({
  required Size previewCanvasSize,
  required Size displayImageSize,
  required CaptureViewportRatio viewportRatio,
}) {
  if (previewCanvasSize.isEmpty || displayImageSize.isEmpty) {
    return Offset.zero & displayImageSize;
  }
  if (viewportRatio.isFull || viewportRatio.aspectRatio == null) {
    return Offset.zero & displayImageSize;
  }

  final viewportRect = resolveCameraViewportRect(
    canvasSize: previewCanvasSize,
    viewportRatio: viewportRatio,
  );
  final scale = math.max(
    previewCanvasSize.width / displayImageSize.width,
    previewCanvasSize.height / displayImageSize.height,
  );
  final displayedImageRect = Rect.fromLTWH(
    (previewCanvasSize.width - (displayImageSize.width * scale)) / 2,
    (previewCanvasSize.height - (displayImageSize.height * scale)) / 2,
    displayImageSize.width * scale,
    displayImageSize.height * scale,
  );

  final left = ((viewportRect.left - displayedImageRect.left) / scale)
      .clamp(0.0, displayImageSize.width)
      .toDouble();
  final top = ((viewportRect.top - displayedImageRect.top) / scale)
      .clamp(0.0, displayImageSize.height)
      .toDouble();
  final right = ((viewportRect.right - displayedImageRect.left) / scale)
      .clamp(left, displayImageSize.width)
      .toDouble();
  final bottom = ((viewportRect.bottom - displayedImageRect.top) / scale)
      .clamp(top, displayImageSize.height)
      .toDouble();

  return Rect.fromLTRB(left, top, right, bottom);
}

Rect mapDisplayRectToRawImageRect({
  required Rect displayRect,
  required Size rawImageSize,
  required int quarterTurns,
}) {
  if (displayRect.isEmpty || rawImageSize.isEmpty) {
    return Offset.zero & rawImageSize;
  }

  final normalizedQuarterTurns = quarterTurns % 4;
  if (normalizedQuarterTurns == 0) {
    return displayRect;
  }

  final corners =
      [
        displayRect.topLeft,
        Offset(displayRect.right, displayRect.top),
        Offset(displayRect.left, displayRect.bottom),
        displayRect.bottomRight,
      ].map(
        (point) => _displayPointToRawPoint(
          point,
          rawImageSize: rawImageSize,
          quarterTurns: normalizedQuarterTurns,
        ),
      );

  final xs = corners.map((point) => point.dx).toList(growable: false);
  final ys = corners.map((point) => point.dy).toList(growable: false);
  return Rect.fromLTRB(
    xs.reduce(math.min),
    ys.reduce(math.min),
    xs.reduce(math.max),
    ys.reduce(math.max),
  );
}

Offset _displayPointToRawPoint(
  Offset point, {
  required Size rawImageSize,
  required int quarterTurns,
}) {
  final rawWidth = rawImageSize.width;
  final rawHeight = rawImageSize.height;

  switch (quarterTurns % 4) {
    case 1:
      return Offset(point.dy, rawHeight - point.dx);
    case 2:
      return Offset(rawWidth - point.dx, rawHeight - point.dy);
    case 3:
      return Offset(rawWidth - point.dy, point.dx);
    default:
      return point;
  }
}
