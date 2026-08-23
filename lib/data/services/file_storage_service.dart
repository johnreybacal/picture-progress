import 'dart:io';

import 'package:camera/camera.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

class FileStorageService {
  FileStorageService() : _uuid = const Uuid();

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

  Future<ExportWorkspace> createExportWorkspace(int seriesId) async {
    final documentsDirectory = await getApplicationDocumentsDirectory();
    final rootDirectory = Directory(
      path.join(
        documentsDirectory.path,
        'exports',
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
    );
  }
}

class ExportWorkspace {
  const ExportWorkspace({
    required this.rootDirectory,
    required this.framesDirectory,
  });

  final Directory rootDirectory;
  final Directory framesDirectory;
}
