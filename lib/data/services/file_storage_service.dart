import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../models/capture_orientation.dart';
import '../models/pose_series.dart';
import 'permission_service.dart';

class FileStorageService {
  FileStorageService({required this.permissionService}) : _uuid = const Uuid();

  static const String _androidPublicRootDirectory =
      '/storage/emulated/0/Picture Progress';
  static const String _exportsDirectoryName = 'exports';

  final PermissionService permissionService;
  final Uuid _uuid;

  Future<void> initializeStorageDirectories() async {
    await permissionService.ensureStorageAccess();
    await defaultPhotoLibraryRootPath();
    await defaultExportRootPath();
  }

  Future<String> persistCameraCapture(
    XFile sourceFile, {
    required int seriesId,
    required CaptureOrientation captureOrientation,
    String? preferredRootPath,
  }) async {
    await permissionService.ensureStorageAccess();
    final seriesDirectory = Directory(
      await resolveSeriesCaptureDirectoryPath(
        seriesId: seriesId,
        preferredRootPath: preferredRootPath,
      ),
    );
    await seriesDirectory.create(recursive: true);

    final extension = '.jpg';
    final filename =
        '${DateTime.now().millisecondsSinceEpoch}_${_uuid.v4().replaceAll('-', '')}$extension';
    final destination = File(path.join(seriesDirectory.path, filename));

    final sourceBytes = await File(sourceFile.path).readAsBytes();
    final uprightBytes = _buildUprightCaptureBytes(
      sourceBytes,
      captureOrientation,
    );
    await destination.writeAsBytes(uprightBytes, flush: true);

    return destination.path;
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

  Future<void> deleteSeriesStorage(int seriesId, {String? seriesName}) async {
    final captureDirectory = Directory(
      await resolveSeriesCaptureDirectoryPath(seriesId: seriesId),
    );
    if (await captureDirectory.exists()) {
      await captureDirectory.delete(recursive: true);
    }

    if (seriesName == null || seriesName.trim().isEmpty) {
      return;
    }

    final exportSeriesDirectory = Directory(
      path.join(await defaultExportRootPath(), _slugify(seriesName)),
    );
    if (await exportSeriesDirectory.exists()) {
      await exportSeriesDirectory.delete(recursive: true);
    }
  }

  Future<String> defaultPhotoLibraryRootPath() async {
    await permissionService.ensureStorageAccess();
    final rootDirectory = await _resolveDefaultRootDirectory();
    await rootDirectory.create(recursive: true);
    return rootDirectory.path;
  }

  Future<String> resolvePhotoLibraryRootPath(String? preferredPath) async {
    await permissionService.ensureStorageAccess();
    final trimmed = preferredPath?.trim() ?? '';
    if (trimmed.isNotEmpty) {
      final directory = Directory(trimmed);
      await directory.create(recursive: true);
      return directory.path;
    }

    return defaultPhotoLibraryRootPath();
  }

  Future<String?> pickPhotoStorageDirectory() async {
    await permissionService.ensureStorageAccess();
    final selectedPath = await FilePicker.getDirectoryPath(
      dialogTitle: 'Select photo storage folder',
    );
    if (selectedPath == null || selectedPath.trim().isEmpty) {
      return null;
    }

    return resolvePhotoLibraryRootPath(selectedPath);
  }

  Future<String> resolveSeriesCaptureDirectoryPath({
    required int seriesId,
    String? preferredRootPath,
  }) async {
    final rootPath = await resolvePhotoLibraryRootPath(preferredRootPath);
    final seriesDirectory = Directory(path.join(rootPath, seriesId.toString()));
    await seriesDirectory.create(recursive: true);
    return seriesDirectory.path;
  }

  Future<String> defaultExportRootPath() async {
    await permissionService.ensureStorageAccess();
    final rootPath = await defaultPhotoLibraryRootPath();
    final exportRoot = Directory(path.join(rootPath, _exportsDirectoryName));
    await exportRoot.create(recursive: true);
    return exportRoot.path;
  }

  Future<String> resolveExportRootPath(String? preferredPath) async {
    await permissionService.ensureStorageAccess();
    final trimmed = preferredPath?.trim() ?? '';
    if (trimmed.isNotEmpty) {
      final directory = Directory(trimmed);
      await directory.create(recursive: true);
      return directory.path;
    }

    return defaultExportRootPath();
  }

  Future<String> defaultExportDirectoryPath({
    required PoseSeries series,
    String? preferredRootPath,
    DateTime? exportedAt,
  }) async {
    await permissionService.ensureStorageAccess();
    final exportRootPath = await resolveExportRootPath(preferredRootPath);
    final exportDirectory = Directory(
      path.join(
        exportRootPath,
        _slugify(series.name),
        _dateFolder(exportedAt ?? DateTime.now()),
      ),
    );
    await exportDirectory.create(recursive: true);
    return exportDirectory.path;
  }

  Future<String> resolveExportDirectoryPath(String? preferredPath) async {
    return resolveExportRootPath(preferredPath);
  }

  Future<String?> pickExportDirectory() async {
    await permissionService.ensureStorageAccess();
    final selectedPath = await FilePicker.getDirectoryPath(
      dialogTitle: 'Select export folder',
    );
    if (selectedPath == null || selectedPath.trim().isEmpty) {
      return null;
    }

    return resolveExportRootPath(selectedPath);
  }

  Future<ExportWorkspace> createExportWorkspace(
    PoseSeries series, {
    String? exportDirectoryPath,
  }) async {
    final outputDirectory = Directory(
      await defaultExportDirectoryPath(
        series: series,
        preferredRootPath: exportDirectoryPath,
      ),
    );
    await outputDirectory.create(recursive: true);
    final rootDirectory = Directory(
      path.join(
        outputDirectory.path,
        '.picture_progress_tmp',
        DateTime.now().millisecondsSinceEpoch.toString(),
      ),
    );
    final framesDirectory = Directory(path.join(rootDirectory.path, 'frames'));
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

  Uint8List _buildUprightCaptureBytes(
    Uint8List sourceBytes,
    CaptureOrientation captureOrientation,
  ) {
    final decoded = img.decodeImage(sourceBytes);
    if (decoded == null) {
      return sourceBytes;
    }

    var normalized = img.bakeOrientation(decoded);
    if (captureOrientation.isLandscape &&
        normalized.width > normalized.height) {
      normalized = img.copyRotate(
        normalized,
        angle: captureOrientation == CaptureOrientation.landscapeLeft
            ? 90
            : 270,
      );
    }

    return Uint8List.fromList(img.encodeJpg(normalized, quality: 94));
  }

  Future<Directory> _resolveDefaultRootDirectory() async {
    if (Platform.isAndroid) {
      final publicDirectory = Directory(_androidPublicRootDirectory);
      try {
        await publicDirectory.create(recursive: true);
        return publicDirectory;
      } catch (_) {}
    }

    final documentsDirectory = await getApplicationDocumentsDirectory();
    return Directory(path.join(documentsDirectory.path, 'Picture Progress'));
  }

  String _dateFolder(DateTime value) {
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '${value.year}-$month-${day}_$hour$minute';
  }

  String _slugify(String value) {
    final slug = value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    return slug.isEmpty ? 'series' : slug;
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
