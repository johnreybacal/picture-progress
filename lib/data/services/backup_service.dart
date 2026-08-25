import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

import '../models/capture_orientation.dart';
import '../models/capture_viewport_ratio.dart';
import '../models/lens_facing.dart';
import '../models/pose_bounding_box.dart';
import '../models/pose_landmark_point.dart';
import '../models/pose_point.dart';
import '../models/pose_record.dart';
import '../models/pose_series.dart';
import 'database_service.dart';
import 'file_storage_service.dart';

class BackupService {
  BackupService({
    required this.databaseService,
    required this.fileStorageService,
  });

  static const int _metadataVersion = 1;
  static const String _metadataFileName = 'metadata.json';
  static const String _photosRoot = 'photos';

  final DatabaseService databaseService;
  final FileStorageService fileStorageService;

  Future<BackupExportResult?> exportSeriesBackup({
    required PoseSeries series,
    required List<PoseRecord> records,
  }) async {
    final archiveBytes = await buildSeriesBackupArchive(
      series: series,
      records: records,
    );
    final fileName = _backupFileName(series);
    final destinationUri = await FilePicker.saveFile(
      dialogTitle: 'Save timeline backup',
      fileName: fileName,
      bytes: archiveBytes,
      mimeType: 'application/zip',
      type: FileType.custom,
      allowedExtensions: const ['zip'],
    );
    if (destinationUri == null) {
      return null;
    }

    return BackupExportResult(
      fileName: fileName,
      destinationUri: destinationUri,
      recordCount: records.length,
    );
  }

  Future<Uint8List> buildSeriesBackupArchive({
    required PoseSeries series,
    required List<PoseRecord> records,
  }) async {
    final orderedRecords = [...records]
      ..sort((first, second) => first.timestamp.compareTo(second.timestamp));
    final archive = Archive();
    final imageArchivePaths = <String, String>{};
    final serializedRecords = <Map<String, dynamic>>[];

    for (var index = 0; index < orderedRecords.length; index += 1) {
      final record = orderedRecords[index];
      final absoluteImagePath = await fileStorageService.resolveAbsolutePath(
        record.imagePath,
      );
      final imageFile = File(absoluteImagePath);
      if (!await imageFile.exists()) {
        throw StateError('Missing photo for backup: $absoluteImagePath');
      }

      final imageBytes = await imageFile.readAsBytes();
      final imageArchivePath = _archiveImagePath(
        record: record,
        absoluteImagePath: absoluteImagePath,
        index: index,
      );
      archive.add(ArchiveFile(imageArchivePath, imageBytes.length, imageBytes));
      imageArchivePaths[record.imagePath] = imageArchivePath;
      serializedRecords.add(_recordToJson(record, imageArchivePath));
    }

    final metadata = <String, dynamic>{
      'version': _metadataVersion,
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'series': _seriesToJson(
        series,
        thumbnailArchivePath: imageArchivePaths[series.thumbnailPath],
      ),
      'records': serializedRecords,
    };
    final metadataBytes = Uint8List.fromList(
      utf8.encode(const JsonEncoder.withIndent('  ').convert(metadata)),
    );
    archive.add(
      ArchiveFile(_metadataFileName, metadataBytes.length, metadataBytes),
    );

    final zipBytes = ZipEncoder().encode(archive);
    return Uint8List.fromList(zipBytes);
  }

  Future<BackupImportResult?> importSeriesBackup({
    String? preferredPhotoRootPath,
  }) async {
    final selectedFiles = await FilePicker.pickFiles(
      dialogTitle: 'Select timeline backup',
      type: FileType.custom,
      allowedExtensions: const ['zip'],
    );
    if (selectedFiles.isEmpty) {
      return null;
    }

    final selectedFile = selectedFiles.first;
    final archiveBytes = await selectedFile.readAsBytes();
    return importSeriesBackupArchive(
      archiveBytes,
      preferredPhotoRootPath: preferredPhotoRootPath,
    );
  }

  Future<BackupImportResult> importSeriesBackupArchive(
    Uint8List archiveBytes, {
    String? preferredPhotoRootPath,
  }) async {
    final archive = ZipDecoder().decodeBytes(archiveBytes, verify: true);
    final archiveEntries = <String, ArchiveFile>{};
    ArchiveFile? metadataEntry;
    for (final entry in archive) {
      if (!entry.isFile) {
        continue;
      }
      final normalizedName = entry.name.replaceAll('\\', '/');
      archiveEntries[normalizedName] = entry;
      if (path.basename(normalizedName) == _metadataFileName) {
        metadataEntry = entry;
      }
    }

    if (metadataEntry == null) {
      throw const FormatException('Backup archive is missing metadata.json.');
    }

    final metadataJson = jsonDecode(
      utf8.decode(_archiveFileBytes(metadataEntry)),
    ) as Map<String, dynamic>;
    final metadata = _BackupMetadata.fromJson(metadataJson);

    final db = await databaseService.database;
    final importedSeriesName = await _resolveImportedSeriesName(
      db,
      metadata.series.name,
    );

    int? importedSeriesId;
    try {
      importedSeriesId = await db.insert('pose_series', {
        'name': importedSeriesName,
        'created_at': metadata.series.createdAt.millisecondsSinceEpoch,
        'thumbnail_path': '',
        'preferred_lens': metadata.series.preferredLens?.storageValue ?? '',
        'last_used_zoom_level': metadata.series.lastUsedZoomLevel ?? 0,
        'last_used_aspect_ratio':
            metadata.series.lastUsedAspectRatio.storageValue,
      }, conflictAlgorithm: ConflictAlgorithm.abort);

      final importedRecords = <PoseRecord>[];
      String thumbnailPath = '';
      for (final recordPayload in metadata.records) {
        final imageEntry = archiveEntries[recordPayload.imageArchivePath];
        if (imageEntry == null || !imageEntry.isFile) {
          throw FormatException(
            'Backup archive is missing ${recordPayload.imageArchivePath}.',
          );
        }

        final storedPath = await fileStorageService.persistCaptureBytes(
          _archiveFileBytes(imageEntry),
          seriesId: importedSeriesId,
          preferredRootPath: preferredPhotoRootPath,
          extension: _imageExtension(recordPayload.imageArchivePath),
        );
        if (thumbnailPath.isEmpty &&
            metadata.series.thumbnailArchivePath ==
                recordPayload.imageArchivePath) {
          thumbnailPath = storedPath;
        }

        importedRecords.add(
          PoseRecord(
            seriesId: importedSeriesId,
            imagePath: storedPath,
            label: recordPayload.label,
            timestamp: recordPayload.timestamp,
            landmarks: recordPayload.landmarks,
            boundingBox: recordPayload.boundingBox,
            anchorCenter: recordPayload.anchorCenter,
            cameraLens: recordPayload.cameraLens,
            captureOrientation: recordPayload.captureOrientation,
            imageWidth: recordPayload.imageWidth,
            imageHeight: recordPayload.imageHeight,
          ),
        );
      }

      if (thumbnailPath.isEmpty && importedRecords.isNotEmpty) {
        thumbnailPath = importedRecords.last.imagePath;
      }

      await db.transaction((txn) async {
        for (final record in importedRecords) {
          await txn.insert(
            'pose_records',
            record.toDatabaseMap()..remove('id'),
            conflictAlgorithm: ConflictAlgorithm.abort,
          );
        }
        await txn.update(
          'pose_series',
          {'thumbnail_path': thumbnailPath},
          where: 'id = ?',
          whereArgs: [importedSeriesId],
        );
      });

      return BackupImportResult(
        series: PoseSeries(
          id: importedSeriesId,
          name: importedSeriesName,
          createdAt: metadata.series.createdAt,
          thumbnailPath: thumbnailPath,
          preferredLens: metadata.series.preferredLens,
          lastUsedZoomLevel: metadata.series.lastUsedZoomLevel,
          lastUsedAspectRatio: metadata.series.lastUsedAspectRatio,
        ),
        recordCount: importedRecords.length,
      );
    } catch (_) {
      if (importedSeriesId != null) {
        await db.delete(
          'pose_series',
          where: 'id = ?',
          whereArgs: [importedSeriesId],
        );
        await fileStorageService.deleteSeriesStorage(importedSeriesId);
      }
      rethrow;
    }
  }

  Map<String, dynamic> _seriesToJson(
    PoseSeries series, {
    String? thumbnailArchivePath,
  }) {
    return {
      'name': series.name,
      'createdAt': series.createdAt.toUtc().toIso8601String(),
      'preferredLens': series.preferredLens?.storageValue,
      'lastUsedZoomLevel': series.lastUsedZoomLevel,
      'lastUsedAspectRatio': series.lastUsedAspectRatio.storageValue,
      'thumbnailArchivePath': thumbnailArchivePath,
    };
  }

  Map<String, dynamic> _recordToJson(
    PoseRecord record,
    String imageArchivePath,
  ) {
    return {
      'label': record.label,
      'timestamp': record.timestamp.toUtc().toIso8601String(),
      'cameraLens': record.cameraLens,
      'captureOrientation': record.captureOrientation.storageValue,
      'imageWidth': record.imageWidth,
      'imageHeight': record.imageHeight,
      'imageArchivePath': imageArchivePath,
      'landmarks': record.landmarks
          .map((landmark) => landmark.toJson())
          .toList(growable: false),
      'boundingBox': record.boundingBox.toJson(),
      'anchorCenter': record.anchorCenter.toJson(),
    };
  }

  Future<String> _resolveImportedSeriesName(Database db, String rawName) async {
    final baseName = rawName.trim().isEmpty
        ? 'Imported timeline'
        : rawName.trim();
    final existingRows = await db.query('pose_series', columns: ['name']);
    final existingNames = existingRows
        .map((row) => (row['name'] as String).toLowerCase())
        .toSet();
    if (!existingNames.contains(baseName.toLowerCase())) {
      return baseName;
    }

    final importedBaseName = '$baseName (Imported)';
    if (!existingNames.contains(importedBaseName.toLowerCase())) {
      return importedBaseName;
    }

    var suffix = 2;
    while (existingNames.contains(
      '$baseName (Imported $suffix)'.toLowerCase(),
    )) {
      suffix += 1;
    }
    return '$baseName (Imported $suffix)';
  }

  String _backupFileName(PoseSeries series) {
    final timestamp = DateTime.now().toUtc();
    final datePart = [
      timestamp.year.toString().padLeft(4, '0'),
      timestamp.month.toString().padLeft(2, '0'),
      timestamp.day.toString().padLeft(2, '0'),
    ].join();
    final timePart = [
      timestamp.hour.toString().padLeft(2, '0'),
      timestamp.minute.toString().padLeft(2, '0'),
      timestamp.second.toString().padLeft(2, '0'),
    ].join();
    return '${_slugify(series.name)}_$datePart$timePart.zip';
  }

  String _archiveImagePath({
    required PoseRecord record,
    required String absoluteImagePath,
    required int index,
  }) {
    final extension = _imageExtension(absoluteImagePath);
    final filename =
        '${(index + 1).toString().padLeft(4, '0')}_${record.timestamp.millisecondsSinceEpoch}$extension';
    return '$_photosRoot/$filename';
  }

  String _imageExtension(String filePath) {
    final extension = path.extension(filePath).trim().toLowerCase();
    return extension.isEmpty ? '.jpg' : extension;
  }

  Uint8List _archiveFileBytes(ArchiveFile file) {
    final bytes = file.readBytes();
    if (bytes == null) {
      throw FormatException('Archive entry ${file.name} did not contain data.');
    }
    return bytes;
  }

  String _slugify(String value) {
    final slug = value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    return slug.isEmpty ? 'timeline_backup' : slug;
  }
}

class BackupExportResult {
  const BackupExportResult({
    required this.fileName,
    required this.destinationUri,
    required this.recordCount,
  });

  final String fileName;
  final Uri destinationUri;
  final int recordCount;
}

class BackupImportResult {
  const BackupImportResult({required this.series, required this.recordCount});

  final PoseSeries series;
  final int recordCount;
}

class _BackupMetadata {
  const _BackupMetadata({required this.series, required this.records});

  factory _BackupMetadata.fromJson(Map<String, dynamic> json) {
    final version = (json['version'] as num?)?.toInt() ?? 0;
    if (version != BackupService._metadataVersion) {
      throw FormatException('Unsupported backup version: $version');
    }

    final seriesJson = Map<String, dynamic>.from(
      json['series'] as Map<dynamic, dynamic>,
    );
    final recordsJson = (json['records'] as List<dynamic>? ?? const [])
        .cast<Map<dynamic, dynamic>>()
        .map((entry) => Map<String, dynamic>.from(entry))
        .toList(growable: false);
    final records =
        recordsJson.map(_BackupRecordPayload.fromJson).toList(growable: false)
          ..sort(
            (first, second) => first.timestamp.compareTo(second.timestamp),
          );

    return _BackupMetadata(
      series: _BackupSeriesPayload.fromJson(seriesJson),
      records: records,
    );
  }

  final _BackupSeriesPayload series;
  final List<_BackupRecordPayload> records;
}

class _BackupSeriesPayload {
  const _BackupSeriesPayload({
    required this.name,
    required this.createdAt,
    required this.preferredLens,
    required this.lastUsedZoomLevel,
    required this.lastUsedAspectRatio,
    required this.thumbnailArchivePath,
  });

  factory _BackupSeriesPayload.fromJson(Map<String, dynamic> json) {
    return _BackupSeriesPayload(
      name: json['name'] as String? ?? 'Imported timeline',
      createdAt: DateTime.parse(json['createdAt'] as String).toLocal(),
      preferredLens: LensFacing.fromStorage(json['preferredLens'] as String?),
      lastUsedZoomLevel: (json['lastUsedZoomLevel'] as num?)?.toDouble(),
      lastUsedAspectRatio: CaptureViewportRatio.fromStorage(
        json['lastUsedAspectRatio'] as String?,
      ),
      thumbnailArchivePath: json['thumbnailArchivePath'] as String?,
    );
  }

  final String name;
  final DateTime createdAt;
  final LensFacing? preferredLens;
  final double? lastUsedZoomLevel;
  final CaptureViewportRatio lastUsedAspectRatio;
  final String? thumbnailArchivePath;
}

class _BackupRecordPayload {
  const _BackupRecordPayload({
    required this.label,
    required this.timestamp,
    required this.landmarks,
    required this.boundingBox,
    required this.anchorCenter,
    required this.cameraLens,
    required this.captureOrientation,
    required this.imageWidth,
    required this.imageHeight,
    required this.imageArchivePath,
  });

  factory _BackupRecordPayload.fromJson(Map<String, dynamic> json) {
    final landmarks = (json['landmarks'] as List<dynamic>? ?? const [])
        .cast<Map<dynamic, dynamic>>()
        .map(
          (entry) =>
              PoseLandmarkPoint.fromJson(Map<String, dynamic>.from(entry)),
        )
        .toList(growable: false);
    return _BackupRecordPayload(
      label: json['label'] as String? ?? '',
      timestamp: DateTime.parse(json['timestamp'] as String).toLocal(),
      landmarks: landmarks,
      boundingBox: PoseBoundingBox.fromJson(
        Map<String, dynamic>.from(json['boundingBox'] as Map<dynamic, dynamic>),
      ),
      anchorCenter: PosePoint.fromJson(
        Map<String, dynamic>.from(
          json['anchorCenter'] as Map<dynamic, dynamic>,
        ),
      ),
      cameraLens: json['cameraLens'] as String? ?? 'front',
      captureOrientation: CaptureOrientation.fromStorage(
        json['captureOrientation'] as String?,
      ),
      imageWidth: (json['imageWidth'] as num?)?.toInt() ?? 0,
      imageHeight: (json['imageHeight'] as num?)?.toInt() ?? 0,
      imageArchivePath: json['imageArchivePath'] as String,
    );
  }

  final String label;
  final DateTime timestamp;
  final List<PoseLandmarkPoint> landmarks;
  final PoseBoundingBox boundingBox;
  final PosePoint anchorCenter;
  final String cameraLens;
  final CaptureOrientation captureOrientation;
  final int imageWidth;
  final int imageHeight;
  final String imageArchivePath;
}
