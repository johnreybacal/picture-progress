import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

class OnionSkinOverlayPainter extends CustomPainter {
  const OnionSkinOverlayPainter({
    required this.image,
    this.mirrorHorizontally = false,
  });

  final ui.Image image;
  final bool mirrorHorizontally;

  @override
  void paint(Canvas canvas, Size size) {
    final sourceRect = Rect.fromLTWH(
      0,
      0,
      image.width.toDouble(),
      image.height.toDouble(),
    );
    final fittedSizes = applyBoxFit(
      BoxFit.cover,
      Size(sourceRect.width, sourceRect.height),
      size,
    );
    final inputRect = Alignment.center.inscribe(fittedSizes.source, sourceRect);
    final outputRect = Alignment.center.inscribe(
      fittedSizes.destination,
      Offset.zero & size,
    );
    final paint = Paint()..filterQuality = FilterQuality.high;

    if (mirrorHorizontally) {
      canvas.save();
      canvas.translate(size.width, 0);
      canvas.scale(-1, 1);
      canvas.drawImageRect(image, inputRect, outputRect, paint);
      canvas.restore();
      return;
    }

    canvas.drawImageRect(image, inputRect, outputRect, paint);
  }

  @override
  bool shouldRepaint(covariant OnionSkinOverlayPainter oldDelegate) {
    return oldDelegate.image != image ||
        oldDelegate.mirrorHorizontally != mirrorHorizontally;
  }
}
