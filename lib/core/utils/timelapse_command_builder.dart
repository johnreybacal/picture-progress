import '../constants/app_constants.dart';
import '../../data/models/pose_record.dart';

class ExportFramePlan {
  const ExportFramePlan({
    required this.record,
    required this.sourcePath,
    required this.outputPath,
    required this.cropLeft,
    required this.cropTop,
    required this.cropWidth,
    required this.cropHeight,
  });

  final PoseRecord record;
  final String sourcePath;
  final String outputPath;
  final double cropLeft;
  final double cropTop;
  final double cropWidth;
  final double cropHeight;
}

class TimelapseCommandBuilder {
  const TimelapseCommandBuilder();

  String buildNormalizedFrameCommand({required ExportFramePlan framePlan}) {
    final filter = [
      'crop=${_format(framePlan.cropWidth)}:${_format(framePlan.cropHeight)}:${_format(framePlan.cropLeft)}:${_format(framePlan.cropTop)}',
      'scale=${AppConstants.exportWidth}:${AppConstants.exportHeight}:flags=lanczos',
      'setsar=1',
    ].join(',');

    return '-y -i ${_quote(framePlan.sourcePath)} -vf "$filter" -q:v 2 ${_quote(framePlan.outputPath)}';
  }

  String buildMp4Command({
    required String framesPattern,
    required String outputPath,
    int fps = 10,
  }) {
    final filter =
        'scale=${AppConstants.exportWidth}:${AppConstants.exportHeight}:flags=lanczos,format=yuv420p';
    return '-y -framerate $fps -i ${_quote(framesPattern)} -vf "$filter" -c:v libx264 -preset medium -crf 18 -movflags +faststart ${_quote(outputPath)}';
  }

  String buildGifCommand({
    required String framesPattern,
    required String outputPath,
    int fps = 8,
    int gifWidth = 720,
  }) {
    final filterComplex =
        '[0:v]fps=$fps,scale=$gifWidth:-1:flags=lanczos,split[a][b];[a]palettegen=stats_mode=single[p];[b][p]paletteuse=dither=sierra2_4a';
    return '-y -framerate $fps -i ${_quote(framesPattern)} -filter_complex "$filterComplex" -loop 0 ${_quote(outputPath)}';
  }

  String _quote(String value) {
    return '"${value.replaceAll('"', r'\"')}"';
  }

  String _format(double value) {
    return value.toStringAsFixed(2);
  }
}
