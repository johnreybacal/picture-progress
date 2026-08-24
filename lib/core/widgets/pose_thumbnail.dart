import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/models/pose_record.dart';
import '../../data/services/file_storage_service.dart';
import 'pose_skeleton_painter.dart';

class PoseThumbnail extends ConsumerWidget {
  const PoseThumbnail({
    super.key,
    required this.record,
    this.borderRadius = const BorderRadius.all(Radius.circular(18)),
    this.fit = BoxFit.cover,
    this.showSkeletonOverlay = true,
    this.skeletonOverlayOpacity = 0.34,
  });

  final PoseRecord record;
  final BorderRadius borderRadius;
  final BoxFit fit;
  final bool showSkeletonOverlay;
  final double skeletonOverlayOpacity;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder<_PoseThumbnailData>(
      future: _loadThumbnailData(ref),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const ColoredBox(
            color: Color(0xFFE9E4D8),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }

        final data = snapshot.data!;
        final quarterTurns = record.captureOrientation.quarterTurnsForDisplay(
          rawWidth: data.imageWidth,
          rawHeight: data.imageHeight,
        );
        final displayWidth = quarterTurns.isOdd
            ? data.imageHeight.toDouble()
            : data.imageWidth.toDouble();
        final displayHeight = quarterTurns.isOdd
            ? data.imageWidth.toDouble()
            : data.imageHeight.toDouble();
        final rawFrame = SizedBox(
          width: data.imageWidth.toDouble(),
          height: data.imageHeight.toDouble(),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.file(File(data.absolutePath), fit: BoxFit.fill),
              if (showSkeletonOverlay)
                IgnorePointer(
                  child: CustomPaint(
                    painter: StoredPoseSkeletonPainter(
                      landmarks: record.landmarks,
                      fit: BoxFit.fill,
                      opacity: skeletonOverlayOpacity,
                      imageSize: Size(
                        data.imageWidth.toDouble(),
                        data.imageHeight.toDouble(),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );

        return ClipRRect(
          borderRadius: borderRadius,
          child: SizedBox.expand(
            child: FittedBox(
              fit: fit,
              child: SizedBox(
                width: displayWidth,
                height: displayHeight,
                child: quarterTurns == 0
                    ? rawFrame
                    : RotatedBox(quarterTurns: quarterTurns, child: rawFrame),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<_PoseThumbnailData> _loadThumbnailData(WidgetRef ref) async {
    final fileStorage = ref.read(fileStorageServiceProvider);
    final absolutePath = await fileStorage.resolveAbsolutePath(
      record.imagePath,
    );
    final dimensions = record.hasSourceDimensions
        ? StoredImageDimensions(
            width: record.imageWidth,
            height: record.imageHeight,
          )
        : await fileStorage.readImageDimensions(absolutePath);
    return _PoseThumbnailData(
      absolutePath: absolutePath,
      imageWidth: dimensions.width,
      imageHeight: dimensions.height,
    );
  }
}

class _PoseThumbnailData {
  const _PoseThumbnailData({
    required this.absolutePath,
    required this.imageWidth,
    required this.imageHeight,
  });

  final String absolutePath;
  final int imageWidth;
  final int imageHeight;
}
