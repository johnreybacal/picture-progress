import 'dart:math';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:path/path.dart' as path;

import '../../core/constants/app_constants.dart';
import '../../core/utils/pose_alignment_engine.dart';
import '../../core/utils/timelapse_command_builder.dart';
import '../models/pose_record.dart';
import '../models/pose_series.dart';
import 'file_storage_service.dart';

class TimelapseExportService {
  TimelapseExportService({
    required this.fileStorageService,
    required this.commandBuilder,
  });

  final FileStorageService fileStorageService;
  final TimelapseCommandBuilder commandBuilder;

  Future<String> exportMp4({
    required PoseSeries series,
    required List<PoseRecord> records,
    int fps = 10,
    String? exportDirectoryPath,
  }) async {
    return _export(
      series: series,
      records: records,
      fps: fps,
      format: _ExportFormat.mp4,
      exportDirectoryPath: exportDirectoryPath,
    );
  }

  Future<String> exportGif({
    required PoseSeries series,
    required List<PoseRecord> records,
    int fps = 8,
    String? exportDirectoryPath,
  }) async {
    return _export(
      series: series,
      records: records,
      fps: fps,
      format: _ExportFormat.gif,
      exportDirectoryPath: exportDirectoryPath,
    );
  }

  Future<String> _export({
    required PoseSeries series,
    required List<PoseRecord> records,
    required int fps,
    required _ExportFormat format,
    String? exportDirectoryPath,
  }) async {
    final orderedRecords = [...records]
      ..sort((first, second) => first.timestamp.compareTo(second.timestamp));
    if (orderedRecords.isEmpty) {
      throw StateError('No pose captures are available for export.');
    }

    final workspace = await fileStorageService.createExportWorkspace(
      series.id ?? 0,
      exportDirectoryPath: exportDirectoryPath,
    );
    try {
      final framePlans = await _buildFramePlans(
        orderedRecords,
        workspace.framesDirectory.path,
      );

      for (final framePlan in framePlans) {
        await _runCommand(
          commandBuilder.buildStabilizedFrameCommand(framePlan: framePlan),
        );
      }

      final seriesSlug = _slugify(series.name);
      final extension = format == _ExportFormat.mp4 ? 'mp4' : 'gif';
      final outputPath = path.join(
        workspace.outputDirectory.path,
        '${seriesSlug}_${DateTime.now().millisecondsSinceEpoch}.$extension',
      );
      final framesPattern = path.join(
        workspace.framesDirectory.path,
        'frame_%05d.jpg',
      );

      final renderCommand = format == _ExportFormat.mp4
          ? commandBuilder.buildMp4Command(
              framesPattern: framesPattern,
              outputPath: outputPath,
              fps: fps,
            )
          : commandBuilder.buildGifCommand(
              framesPattern: framesPattern,
              outputPath: outputPath,
              fps: fps,
            );

      await _runCommand(renderCommand);
      return outputPath;
    } finally {
      await fileStorageService.deleteDirectory(workspace.rootDirectory.path);
    }
  }

  Future<List<ExportFramePlan>> _buildFramePlans(
    List<PoseRecord> records,
    String framesDirectoryPath,
  ) async {
    final resolvedRecords = <_ResolvedRecord>[];
    for (final record in records) {
      final sourcePath = await fileStorageService.resolveAbsolutePath(
        record.imagePath,
      );
      final imageSize = record.hasSourceDimensions
          ? StoredImageDimensions(
              width: record.imageWidth,
              height: record.imageHeight,
            )
          : await fileStorageService.readImageDimensions(sourcePath);
      resolvedRecords.add(
        _ResolvedRecord(
          record: record,
          sourcePath: sourcePath,
          imageWidth: imageSize.width.toDouble(),
          imageHeight: imageSize.height.toDouble(),
        ),
      );
    }

    final aspectRatio = AppConstants.exportWidth / AppConstants.exportHeight;

    final framePlans = <ExportFramePlan>[];
    for (var index = 0; index < resolvedRecords.length; index++) {
      final item = resolvedRecords[index];
      final quarterTurns = item.record.captureOrientation
          .quarterTurnsForDisplay(
            rawWidth: item.imageWidth.round(),
            rawHeight: item.imageHeight.round(),
          );
      final displayWidth = quarterTurns.isOdd
          ? item.imageHeight
          : item.imageWidth;
      final displayHeight = quarterTurns.isOdd
          ? item.imageWidth
          : item.imageHeight;
      final displayAnchor = item.record.displayAnchorCenter(
        rawWidth: item.imageWidth.round(),
        rawHeight: item.imageHeight.round(),
      );
      final displayLandmarks = item.record.displayLandmarks(
        rawWidth: item.imageWidth.round(),
        rawHeight: item.imageHeight.round(),
      );
      final recordBodyScale = max(
        PoseGeometry.bodyScaleFor(displayLandmarks),
        1.0,
      );

      var cropHeight = min(
        max(240.0, recordBodyScale * AppConstants.exportBodyPaddingMultiplier),
        displayHeight,
      );
      var cropWidth = cropHeight * aspectRatio;

      if (cropWidth > displayWidth) {
        cropWidth = displayWidth;
        cropHeight = cropWidth / aspectRatio;
      }

      if (cropHeight > displayHeight) {
        cropHeight = displayHeight;
        cropWidth = cropHeight * aspectRatio;
      }

      final maxLeft = max(0.0, displayWidth - cropWidth);
      final maxTop = max(0.0, displayHeight - cropHeight);
      final cropLeft =
          (displayAnchor.x - (AppConstants.targetAnchorX * cropWidth))
              .clamp(0.0, maxLeft)
              .toDouble();
      final cropTop =
          (displayAnchor.y - (AppConstants.targetAnchorY * cropHeight))
              .clamp(0.0, maxTop)
              .toDouble();

      framePlans.add(
        ExportFramePlan(
          record: item.record,
          sourcePath: item.sourcePath,
          outputPath: path.join(
            framesDirectoryPath,
            'frame_${(index + 1).toString().padLeft(5, '0')}.jpg',
          ),
          quarterTurns: quarterTurns,
          cropLeft: cropLeft,
          cropTop: cropTop,
          cropWidth: cropWidth,
          cropHeight: cropHeight,
        ),
      );
    }

    return framePlans;
  }

  Future<void> _runCommand(String command) async {
    final session = await FFmpegKit.execute(command);
    final returnCode = await session.getReturnCode();
    if (!ReturnCode.isSuccess(returnCode)) {
      final output = await session.getOutput();
      throw StateError(
        output?.trim().isNotEmpty == true
            ? output!.trim()
            : 'FFmpeg command failed.',
      );
    }
  }

  String _slugify(String value) {
    final slug = value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    return slug.isEmpty ? 'pose_series' : slug;
  }
}

class _ResolvedRecord {
  const _ResolvedRecord({
    required this.record,
    required this.sourcePath,
    required this.imageWidth,
    required this.imageHeight,
  });

  final PoseRecord record;
  final String sourcePath;
  final double imageWidth;
  final double imageHeight;
}

enum _ExportFormat { mp4, gif }
