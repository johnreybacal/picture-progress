import 'dart:math';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:path/path.dart' as path;

import '../../core/constants/app_constants.dart';
import '../../core/utils/timelapse_command_builder.dart';
import '../models/pose_record.dart';
import '../models/pose_point.dart';
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
      series,
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

    final preparedFrames = <_PreparedFrame>[];
    for (final item in resolvedRecords) {
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
      final scaleFactor = min(
        AppConstants.exportWidth / displayWidth,
        AppConstants.exportHeight / displayHeight,
      );
      final fittedWidth = displayWidth * scaleFactor;
      final fittedHeight = displayHeight * scaleFactor;
      preparedFrames.add(
        _PreparedFrame(
          resolvedRecord: item,
          quarterTurns: quarterTurns,
          fittedWidth: fittedWidth,
          fittedHeight: fittedHeight,
          anchorInOutput: PosePoint(
            x: displayAnchor.x * scaleFactor,
            y: displayAnchor.y * scaleFactor,
          ),
        ),
      );
    }

    final targetAnchor = PosePoint(
      x:
          preparedFrames
              .map((frame) => frame.anchorInOutput.x)
              .reduce((first, second) => first + second) /
          preparedFrames.length,
      y:
          preparedFrames
              .map((frame) => frame.anchorInOutput.y)
              .reduce((first, second) => first + second) /
          preparedFrames.length,
    );

    final framePlans = <ExportFramePlan>[];
    for (var index = 0; index < preparedFrames.length; index++) {
      final frame = preparedFrames[index];
      final centeredLeft = (AppConstants.exportWidth - frame.fittedWidth) / 2;
      final centeredTop = (AppConstants.exportHeight - frame.fittedHeight) / 2;
      final desiredLeft =
          centeredLeft + (targetAnchor.x - frame.anchorInOutput.x);
      final desiredTop =
          centeredTop + (targetAnchor.y - frame.anchorInOutput.y);
      final maxLeft = max(0.0, AppConstants.exportWidth - frame.fittedWidth);
      final maxTop = max(0.0, AppConstants.exportHeight - frame.fittedHeight);
      final frameLeft = desiredLeft.clamp(0.0, maxLeft).toDouble();
      final frameTop = desiredTop.clamp(0.0, maxTop).toDouble();

      framePlans.add(
        ExportFramePlan(
          record: frame.record,
          sourcePath: frame.sourcePath,
          outputPath: path.join(
            framesDirectoryPath,
            'frame_${(index + 1).toString().padLeft(5, '0')}.jpg',
          ),
          quarterTurns: frame.quarterTurns,
          frameLeft: frameLeft,
          frameTop: frameTop,
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

class _PreparedFrame {
  const _PreparedFrame({
    required this.resolvedRecord,
    required this.quarterTurns,
    required this.fittedWidth,
    required this.fittedHeight,
    required this.anchorInOutput,
  });

  final _ResolvedRecord resolvedRecord;
  final int quarterTurns;
  final double fittedWidth;
  final double fittedHeight;
  final PosePoint anchorInOutput;

  PoseRecord get record => resolvedRecord.record;
  String get sourcePath => resolvedRecord.sourcePath;
}

enum _ExportFormat { mp4, gif }
