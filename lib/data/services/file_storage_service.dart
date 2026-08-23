import 'dart:io';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

class FileStorageService {
  FileStorageService() : _uuid = const Uuid();

  static const String _androidPublicExportDirectory =
      '/storage/emulated/0/Picture Progress';

  final Uuid _uuid;

  Future<String> persistCameraCapture(
    XFile sourceFile, {
    required int seriesId,
  }) async {
    final documentsDirectory = await getApplicationDocumentsDirectory();
    final seriesDirectory = Directory(
      path.join(documentsDirectory.path, 'captures', 'series_$seriesId'),
    );
    await seriesDirectory.create(recursive: true);

    final extension = path.extension(sourceFile.path).isEmpty
        ? '.jpg'
        : path.extension(sourceFile.path);
    final filename =
        '${DateTime.now().millisecondsSinceEpoch}_${_uuid.v4().replaceAll('-', '')}$extension';
    final destination = File(path.join(seriesDirectory.path, filename));

    await File(sourceFile.path).copy(destination.path);

    return path.relative(destination.path, from: documentsDirectory.path);
  }

  Future<String> resolveAbsolutePath(String storedPath) async {
    if (storedPath.isEmpty || path.isAbsolute(storedPath)) {
      return storedPath;
    }

    final documentsDirectory = await getApplicationDocumentsDirectory();
    return path.join(documentsDirectory.path, storedPath);
  }

  Future<StoredImageDimensions> readImageDimensions(
    String storedOrAbsolutePath,
  ) async {
    final absolutePath = await resolveAbsolutePath(storedOrAbsolutePath);
    final bytes = await File(absolutePath).readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frameInfo = await codec.getNextFrame();
    return StoredImageDimensions(
      width: frameInfo.image.width,
      height: frameInfo.image.height,
    );
  }

  Future<void> deleteStoredFile(String storedPath) async {
    if (storedPath.isEmpty) {
      return;
    }

    final absolutePath = await resolveAbsolutePath(storedPath);
    final file = File(absolutePath);
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<void> deleteSeriesStorage(int seriesId) async {
    final documentsDirectory = await getApplicationDocumentsDirectory();
    final captureDirectory = Directory(
      path.join(documentsDirectory.path, 'captures', 'series_$seriesId'),
    );
    final exportDirectory = Directory(
      path.join(documentsDirectory.path, 'exports', 'series_$seriesId'),
    );

    if (await captureDirectory.exists()) {
      await captureDirectory.delete(recursive: true);
    }
    if (await exportDirectory.exists()) {
      await exportDirectory.delete(recursive: true);
    }
  }

  Future<String> defaultExportDirectoryPath() async {
    if (Platform.isAndroid) {
      final publicDirectory = Directory(_androidPublicExportDirectory);
      try {
        await publicDirectory.create(recursive: true);
        return publicDirectory.path;
      } catch (_) {}
    }

    final baseDirectory = await _resolveDefaultExportBaseDirectory();
    final fallbackDirectory = Directory(
      path.join(baseDirectory.path, 'Picture Progress'),
    );
    await fallbackDirectory.create(recursive: true);
    return fallbackDirectory.path;
  }

  Future<String> resolveExportDirectoryPath(String? preferredPath) async {
    final trimmed = preferredPath?.trim() ?? '';
    if (trimmed.isNotEmpty) {
      final directory = Directory(trimmed);
      await directory.create(recursive: true);
      return directory.path;
    }

    return defaultExportDirectoryPath();
  }

  Future<String?> pickExportDirectory() async {
    final selectedPath = await FilePicker.getDirectoryPath(
      dialogTitle: 'Select export directory',
    );
    if (selectedPath == null || selectedPath.trim().isEmpty) {
      return null;
    }

    return resolveExportDirectoryPath(selectedPath);
  }

  Future<ExportWorkspace> createExportWorkspace(
    int seriesId, {
    String? exportDirectoryPath,
  }) async {
    final outputDirectory = Directory(
      await resolveExportDirectoryPath(exportDirectoryPath),
    );
    await outputDirectory.create(recursive: true);
    final rootDirectory = Directory(
      path.join(
        outputDirectory.path,
        '.picture_progress_tmp',
        'series_$seriesId',
        DateTime.now().millisecondsSinceEpoch.toString(),
      ),
    );
    final framesDirectory = Directory(
      path.join(rootDirectory.path, 'normalized_frames'),
    );
    await framesDirectory.create(recursive: true);

    return ExportWorkspace(
      rootDirectory: rootDirectory,
      framesDirectory: framesDirectory,
      outputDirectory: outputDirectory,
    );
  }

  Future<void> deleteDirectory(String absolutePath) async {
    if (absolutePath.isEmpty) {
      return;
    }

    final directory = Directory(absolutePath);
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  }

  Future<Directory> _resolveDefaultExportBaseDirectory() async {
    if (Platform.isAndroid) {
      final externalDirectory = await getExternalStorageDirectory();
      if (externalDirectory != null) {
        return externalDirectory;
      }
    }

    return getApplicationDocumentsDirectory();
  }
}

class StoredImageDimensions {
  const StoredImageDimensions({required this.width, required this.height});

  final int width;
  final int height;
}

class ExportWorkspace {
  const ExportWorkspace({
    required this.rootDirectory,
    required this.framesDirectory,
    required this.outputDirectory,
  });

  final Directory rootDirectory;
  final Directory framesDirectory;
  final Directory outputDirectory;
}
