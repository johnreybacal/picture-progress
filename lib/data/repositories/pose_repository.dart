import 'package:sqflite/sqflite.dart';

import '../models/capture_orientation.dart';
import '../models/capture_viewport_ratio.dart';
import '../models/lens_facing.dart';
import '../models/pose_bounding_box.dart';
import '../models/pose_landmark_point.dart';
import '../models/pose_point.dart';
import '../models/pose_record.dart';
import '../models/pose_record_update.dart';
import '../models/pose_series.dart';
import '../services/database_service.dart';
import '../services/file_storage_service.dart';

class PoseRepository {
  PoseRepository({
    required this.databaseService,
    required this.fileStorageService,
  });

  final DatabaseService databaseService;
  final FileStorageService fileStorageService;

  Future<List<PoseSeries>> fetchSeries() async {
    final db = await databaseService.database;
    final result = await db.query('pose_series', orderBy: 'created_at DESC');
    return result.map(PoseSeries.fromDatabaseMap).toList();
  }

  Future<PoseSeries> createSeries(String name) async {
    final db = await databaseService.database;
    final series = PoseSeries(
      name: name,
      createdAt: DateTime.now(),
      thumbnailPath: '',
      preferredLens: null,
      lastUsedZoomLevel: null,
      lastUsedAspectRatio: CaptureViewportRatio.full,
    );

    final id = await db.insert(
      'pose_series',
      series.toDatabaseMap()..remove('id'),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );

    return series.copyWith(id: id);
  }

  Future<PoseSeries?> getSeries(int seriesId) async {
    final db = await databaseService.database;
    final result = await db.query(
      'pose_series',
      where: 'id = ?',
      whereArgs: [seriesId],
      limit: 1,
    );

    if (result.isEmpty) {
      return null;
    }

    return PoseSeries.fromDatabaseMap(result.first);
  }

  Future<void> updateSeriesName(int seriesId, String name) async {
    final db = await databaseService.database;
    await db.update(
      'pose_series',
      {'name': name.trim()},
      where: 'id = ?',
      whereArgs: [seriesId],
    );
  }

  Future<void> deleteSeries(PoseSeries series) async {
    final db = await databaseService.database;
    final records = await fetchRecords(series.id!);
    for (final record in records) {
      await fileStorageService.deleteStoredFile(record.imagePath);
    }
    await db.delete('pose_series', where: 'id = ?', whereArgs: [series.id]);
    await fileStorageService.deleteSeriesStorage(
      series.id!,
      seriesName: series.name,
    );
  }

  Future<List<PoseRecord>> fetchRecords(int seriesId) async {
    final db = await databaseService.database;
    final result = await db.query(
      'pose_records',
      where: 'series_id = ?',
      whereArgs: [seriesId],
      orderBy: 'timestamp ASC',
    );

    return result.map(PoseRecord.fromDatabaseMap).toList();
  }

  Future<void> updateSeriesCapturePreferences(
    int seriesId, {
    LensFacing? preferredLens,
    double? lastUsedZoomLevel,
    CaptureViewportRatio? lastUsedAspectRatio,
  }) async {
    final updates = <String, Object?>{};
    if (preferredLens != null) {
      updates['preferred_lens'] = preferredLens.storageValue;
    }
    if (lastUsedZoomLevel != null) {
      updates['last_used_zoom_level'] = lastUsedZoomLevel > 0
          ? lastUsedZoomLevel
          : 0;
    }
    if (lastUsedAspectRatio != null) {
      updates['last_used_aspect_ratio'] = lastUsedAspectRatio.storageValue;
    }
    if (updates.isEmpty) {
      return;
    }

    final db = await databaseService.database;
    await db.update(
      'pose_series',
      updates,
      where: 'id = ?',
      whereArgs: [seriesId],
    );
  }

  Future<PoseRecord> addRecord({
    required int seriesId,
    required String imagePath,
    required String label,
    required DateTime timestamp,
    required List<PoseLandmarkPoint> landmarks,
    required PoseBoundingBox boundingBox,
    required PosePoint anchorCenter,
    required String cameraLens,
    required CaptureOrientation captureOrientation,
    required int imageWidth,
    required int imageHeight,
    double? captureZoomLevel,
    CaptureViewportRatio? captureViewportRatio,
  }) async {
    final db = await databaseService.database;

    final record = PoseRecord(
      seriesId: seriesId,
      imagePath: imagePath,
      label: label,
      timestamp: timestamp,
      landmarks: landmarks,
      boundingBox: boundingBox,
      anchorCenter: anchorCenter,
      cameraLens: cameraLens,
      captureOrientation: captureOrientation,
      imageWidth: imageWidth,
      imageHeight: imageHeight,
    );

    final id = await db.insert(
      'pose_records',
      record.toDatabaseMap()..remove('id'),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );

    final savedRecord = record.copyWith(id: id);
    final existingSeries = await getSeries(seriesId);
    if (existingSeries != null) {
      final preferredLens = LensFacing.fromCameraLensName(record.cameraLens);
      final updates = <String, Object?>{
        'thumbnail_path': imagePath,
        'preferred_lens': preferredLens.storageValue,
      };
      if (captureZoomLevel != null) {
        updates['last_used_zoom_level'] = captureZoomLevel > 0
            ? captureZoomLevel
            : 0;
      }
      if (captureViewportRatio != null) {
        updates['last_used_aspect_ratio'] = captureViewportRatio.storageValue;
      }
      await db.update(
        'pose_series',
        updates,
        where: 'id = ?',
        whereArgs: [seriesId],
      );
    }

    return savedRecord;
  }

  Future<void> updateRecordMetadata(
    int recordId,
    PoseRecordUpdate update,
  ) async {
    final db = await databaseService.database;
    await db.update(
      'pose_records',
      {
        'label': update.label.trim(),
        'timestamp': update.timestamp.millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [recordId],
    );
  }

  Future<void> deleteRecord(PoseRecord record) async {
    final db = await databaseService.database;
    await fileStorageService.deleteStoredFile(record.imagePath);
    await db.delete('pose_records', where: 'id = ?', whereArgs: [record.id]);
    await _rebuildThumbnail(db, record.seriesId);
  }

  Future<String> resolveImagePath(String storedPath) {
    return fileStorageService.resolveAbsolutePath(storedPath);
  }

  Future<void> _rebuildThumbnail(Database db, int seriesId) async {
    final result = await db.query(
      'pose_records',
      where: 'series_id = ?',
      whereArgs: [seriesId],
      orderBy: 'timestamp DESC',
      limit: 1,
    );
    final thumbnailPath = result.isEmpty
        ? ''
        : PoseRecord.fromDatabaseMap(result.first).imagePath;
    await db.update(
      'pose_series',
      {'thumbnail_path': thumbnailPath},
      where: 'id = ?',
      whereArgs: [seriesId],
    );
  }
}
