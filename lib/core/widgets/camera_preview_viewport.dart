import 'package:flutter/material.dart';

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
    if (viewportRatio.isFull) {
      return SizedBox.expand(child: child);
    }

    return Center(
      child: AspectRatio(
        aspectRatio: viewportRatio.aspectRatio!,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white24),
              borderRadius: BorderRadius.circular(28),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
