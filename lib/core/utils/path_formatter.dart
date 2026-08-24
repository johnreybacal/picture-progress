import 'package:path/path.dart' as path;

class PathFormatter {
  const PathFormatter._();

  static String formatDirectoryLabel(String rawPath) {
    final normalized = path.normalize(rawPath).replaceAll('\\', '/');
    if (normalized.trim().isEmpty) {
      return 'Not set';
    }

    final segments = normalized
        .split('/')
        .where((segment) => segment.trim().isNotEmpty)
        .toList(growable: false);
    if (segments.isEmpty) {
      return rawPath;
    }

    if (normalized.startsWith('/storage/emulated/0')) {
      final visibleSegments = segments.skip(3).map(_prettifySegment).toList();
      return visibleSegments.isEmpty
          ? 'Internal Storage'
          : 'Internal Storage > ${visibleSegments.join(' > ')}';
    }

    final documentsIndex = segments.indexWhere(
      (segment) => segment.toLowerCase() == 'documents',
    );
    if (documentsIndex >= 0) {
      final visibleSegments = segments
          .skip(documentsIndex)
          .map(_prettifySegment)
          .toList();
      return 'On My Device > ${visibleSegments.join(' > ')}';
    }

    if (RegExp(r'^[A-Za-z]:$').hasMatch(segments.first)) {
      final drive = segments.first.toUpperCase();
      final visibleSegments = segments.skip(1).map(_prettifySegment).toList();
      return visibleSegments.isEmpty
          ? drive
          : '$drive > ${visibleSegments.join(' > ')}';
    }

    return segments.map(_prettifySegment).join(' > ');
  }

  static String _prettifySegment(String value) {
    if (value == '.picture_progress_tmp') {
      return 'Temporary exports';
    }
    if (value == 'exports') {
      return 'Exports';
    }
    if (RegExp(r'^\d+$').hasMatch(value)) {
      return 'Series $value';
    }
    if (RegExp(r'^series_\d+$').hasMatch(value)) {
      return 'Series ${value.substring(7)}';
    }
    if (RegExp(r'^\d{4}-\d{2}-\d{2}_\d{4}$').hasMatch(value)) {
      return value.replaceFirst('_', ' ');
    }

    final words = value
        .replaceAll('-', ' ')
        .replaceAll('_', ' ')
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .map(
          (word) => word.length <= 2
              ? word.toUpperCase()
              : '${word[0].toUpperCase()}${word.substring(1)}',
        )
        .toList(growable: false);
    return words.isEmpty ? value : words.join(' ');
  }
}
