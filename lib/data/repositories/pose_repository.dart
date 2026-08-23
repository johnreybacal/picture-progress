import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../models/baseline_pose_metadata.dart';
import '../models/capture_orientation.dart';
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
      baselineMetadata: null,
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
    await fileStorageService.deleteSeriesStorage(series.id!);
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

  Future<PoseRecord?> fetchBaselineRecord(int seriesId) async {
    final db = await databaseService.database;
    final result = await db.query(
      'pose_records',
      where: 'series_id = ? AND (baseline_pose = 1 OR is_reference = 1)',
      whereArgs: [seriesId],
      orderBy: 'timestamp ASC',
      limit: 1,
    );

    if (result.isEmpty) {
      return null;
    }

    return PoseRecord.fromDatabaseMap(result.first);
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
    bool baselinePose = false,
  }) async {
    final db = await databaseService.database;
    if (baselinePose) {
      await db.update(
        'pose_records',
        {'baseline_pose': 0, 'is_reference': 0},
        where: 'series_id = ? AND (baseline_pose = 1 OR is_reference = 1)',
        whereArgs: [seriesId],
      );
    }

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
      baselinePose: baselinePose,
    );

    final id = await db.insert(
      'pose_records',
      record.toDatabaseMap()..remove('id'),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );

    final savedRecord = record.copyWith(id: id);
    final existingSeries = await getSeries(seriesId);
    if (existingSeries != null &&
        (existingSeries.thumbnailPath.isEmpty || baselinePose)) {
      await db.update(
        'pose_series',
        {'thumbnail_path': imagePath},
        where: 'id = ?',
        whereArgs: [seriesId],
      );
    }

    if (baselinePose) {
      await _updateBaselineMetadata(db, seriesId, savedRecord);
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
    await _rebuildBaselineMetadata(db, record.seriesId);
  }

  Future<String> resolveImagePath(String storedPath) {
    return fileStorageService.resolveAbsolutePath(storedPath);
  }

  Future<void> _updateBaselineMetadata(
    Database db,
    int seriesId,
    PoseRecord record,
  ) async {
    final metadata = BaselinePoseMetadata(
      recordId: record.id!,
      imagePath: record.imagePath,
      capturedAt: record.timestamp,
      anchorCenter: record.anchorCenter,
      boundingBox: record.boundingBox,
      cameraLens: record.cameraLens,
      captureOrientation: record.captureOrientation,
    );
    await db.update(
      'pose_series',
      {'baseline_metadata_json': jsonEncode(metadata.toJson())},
      where: 'id = ?',
      whereArgs: [seriesId],
    );
  }

  Future<void> _rebuildThumbnail(Database db, int seriesId) async {
    final result = await db.query(
      'pose_records',
      where: 'series_id = ?',
      whereArgs: [seriesId],
      orderBy: 'baseline_pose DESC, is_reference DESC, timestamp DESC',
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

  Future<void> _rebuildBaselineMetadata(Database db, int seriesId) async {
    final result = await db.query(
      'pose_records',
      where: 'series_id = ? AND (baseline_pose = 1 OR is_reference = 1)',
      whereArgs: [seriesId],
      limit: 1,
      orderBy: 'timestamp DESC',
    );
    if (result.isEmpty) {
      await db.update(
        'pose_series',
        {'baseline_metadata_json': ''},
        where: 'id = ?',
        whereArgs: [seriesId],
      );
      return;
    }

    await _updateBaselineMetadata(
      db,
      seriesId,
      PoseRecord.fromDatabaseMap(result.first),
    );
  }
}
