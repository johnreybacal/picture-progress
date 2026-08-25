import 'package:flutter/material.dart';

import '../utils/camera_viewport_geometry.dart';
import '../../data/models/capture_viewport_ratio.dart';

class CameraPreviewViewport extends StatelessWidget {
  const CameraPreviewViewport({
    super.key,
    required this.viewportRatio,
    required this.child,
  });

  final CaptureViewportRatio viewportRatio;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportRect = resolveCameraViewportRect(
          canvasSize: constraints.biggest,
          viewportRatio: viewportRatio,
        );

        return Stack(
          fit: StackFit.expand,
          children: [
            child,
            if (!viewportRatio.isFull)
              IgnorePointer(
                child: CustomPaint(
                  painter: _ViewportMaskPainter(viewportRect: viewportRect),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _ViewportMaskPainter extends CustomPainter {
  const _ViewportMaskPainter({required this.viewportRect});

  final Rect viewportRect;

  @override
  void paint(Canvas canvas, Size size) {
    final outerPath = Path()..addRect(Offset.zero & size);
    final innerPath = Path()
      ..addRRect(
        RRect.fromRectAndRadius(viewportRect, const Radius.circular(2)),
      );
    final overlayPath = Path.combine(
      PathOperation.difference,
      outerPath,
      innerPath,
    );

    final overlayPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.42)
      ..style = PaintingStyle.fill;
    canvas.drawPath(overlayPath, overlayPaint);

    final borderPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.28)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    canvas.drawRRect(
      RRect.fromRectAndRadius(viewportRect, const Radius.circular(2)),
      borderPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _ViewportMaskPainter oldDelegate) {
    return oldDelegate.viewportRect != viewportRect;
  }
}
