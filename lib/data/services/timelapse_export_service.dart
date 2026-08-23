import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:path/path.dart' as path;

import '../../core/constants/app_constants.dart';
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
  }) async {
    return _export(
      series: series,
      records: records,
      fps: fps,
      format: _ExportFormat.mp4,
    );
  }

  Future<String> exportGif({
    required PoseSeries series,
    required List<PoseRecord> records,
    int fps = 8,
  }) async {
    return _export(
      series: series,
      records: records,
      fps: fps,
      format: _ExportFormat.gif,
    );
  }

  Future<String> _export({
    required PoseSeries series,
    required List<PoseRecord> records,
    required int fps,
    required _ExportFormat format,
  }) async {
    final orderedRecords = [...records]
      ..sort((first, second) => first.timestamp.compareTo(second.timestamp));
    if (orderedRecords.isEmpty) {
      throw StateError('No pose captures are available for export.');
    }

    final workspace = await fileStorageService.createExportWorkspace(
      series.id ?? 0,
    );
    final framePlans = await _buildFramePlans(
      orderedRecords,
      workspace.framesDirectory.path,
    );

    for (final framePlan in framePlans) {
      await _runCommand(
        commandBuilder.buildNormalizedFrameCommand(framePlan: framePlan),
      );
    }

    final seriesSlug = _slugify(series.name);
    final extension = format == _ExportFormat.mp4 ? 'mp4' : 'gif';
    final outputPath = path.join(
      workspace.rootDirectory.path,
      '$seriesSlug.$extension',
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
      final imageSize = await _readImageSize(sourcePath);
      resolvedRecords.add(
        _ResolvedRecord(
          record: record,
          sourcePath: sourcePath,
          imageWidth: imageSize.width,
          imageHeight: imageSize.height,
        ),
      );
    }

    final bodyHeights = resolvedRecords
        .map((item) => item.record.boundingBox.height)
        .where((value) => value > 0)
        .toList();
    final referenceBodyHeight = max(
      240.0,
      (bodyHeights.isEmpty ? 1080.0 : bodyHeights.reduce(max)) *
          AppConstants.exportBodyPaddingMultiplier,
    );
    final aspectRatio = AppConstants.exportWidth / AppConstants.exportHeight;

    final framePlans = <ExportFramePlan>[];
    for (var index = 0; index < resolvedRecords.length; index++) {
      final item = resolvedRecords[index];
      var cropHeight = min(referenceBodyHeight, item.imageHeight);
      var cropWidth = cropHeight * aspectRatio;

      if (cropWidth > item.imageWidth) {
        cropWidth = item.imageWidth;
        cropHeight = cropWidth / aspectRatio;
      }

      if (cropHeight > item.imageHeight) {
        cropHeight = item.imageHeight;
        cropWidth = cropHeight * aspectRatio;
      }

      final maxLeft = max(0.0, item.imageWidth - cropWidth);
      final maxTop = max(0.0, item.imageHeight - cropHeight);
      final cropLeft =
          (item.record.anchorCenter.x -
                  (AppConstants.targetAnchorX * cropWidth))
              .clamp(0.0, maxLeft)
              .toDouble();
      final cropTop =
          (item.record.anchorCenter.y -
                  (AppConstants.targetAnchorY * cropHeight))
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
          cropLeft: cropLeft,
          cropTop: cropTop,
          cropWidth: cropWidth,
          cropHeight: cropHeight,
        ),
      );
    }

    return framePlans;
  }

  Future<ui.Size> _readImageSize(String imagePath) async {
    final bytes = await File(imagePath).readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();

    return ui.Size(frame.image.width.toDouble(), frame.image.height.toDouble());
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
