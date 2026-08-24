import '../constants/app_constants.dart';
import '../../data/models/pose_record.dart';

class ExportFramePlan {
  const ExportFramePlan({
    required this.record,
    required this.sourcePath,
    required this.outputPath,
    required this.quarterTurns,
    required this.frameLeft,
    required this.frameTop,
  });

  final PoseRecord record;
  final String sourcePath;
  final String outputPath;
  final int quarterTurns;
  final double frameLeft;
  final double frameTop;
}

class TimelapseCommandBuilder {
  const TimelapseCommandBuilder();

  String buildStabilizedFrameCommand({required ExportFramePlan framePlan}) {
    final filter = buildStabilizedCropAndScaleFilter(framePlan);

    return '-y -i ${_quote(framePlan.sourcePath)} -vf "$filter" -q:v 2 ${_quote(framePlan.outputPath)}';
  }

  String buildNormalizedFrameCommand({required ExportFramePlan framePlan}) {
    return buildStabilizedFrameCommand(framePlan: framePlan);
  }

  String buildStabilizedCropAndScaleFilter(ExportFramePlan framePlan) {
    final filters = <String>[];
    final preRotationFilter = _rotationFilter(framePlan.quarterTurns);
    if (preRotationFilter != null) {
      filters.add(preRotationFilter);
    }
    filters.addAll([
      'scale=${AppConstants.exportWidth}:${AppConstants.exportHeight}:force_original_aspect_ratio=decrease:flags=lanczos',
      'pad=${AppConstants.exportWidth}:${AppConstants.exportHeight}:${_format(framePlan.frameLeft)}:${_format(framePlan.frameTop)}:color=0xF3F2EE',
      'setsar=1',
    ]);
    return filters.join(',');
  }

  String buildCropAndScaleFilter(ExportFramePlan framePlan) {
    return buildStabilizedCropAndScaleFilter(framePlan);
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

  String? _rotationFilter(int quarterTurns) {
    switch (quarterTurns % 4) {
      case 1:
        return 'transpose=clock';
      case 3:
        return 'transpose=cclock';
      default:
        return null;
    }
  }
}
