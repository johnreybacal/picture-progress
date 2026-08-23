import 'package:sqflite/sqflite.dart';

import '../models/pose_bounding_box.dart';
import '../models/pose_landmark_point.dart';
import '../models/pose_point.dart';
import '../models/pose_record.dart';
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
      where: 'series_id = ? AND is_reference = 1',
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
    required DateTime timestamp,
    required List<PoseLandmarkPoint> landmarks,
    required PoseBoundingBox boundingBox,
    required PosePoint anchorCenter,
    bool isReference = false,
  }) async {
    final db = await databaseService.database;
    final record = PoseRecord(
      seriesId: seriesId,
      imagePath: imagePath,
      timestamp: timestamp,
      landmarks: landmarks,
      boundingBox: boundingBox,
      anchorCenter: anchorCenter,
      isReference: isReference,
    );

    final id = await db.insert(
      'pose_records',
      record.toDatabaseMap()..remove('id'),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );

    final existingSeries = await getSeries(seriesId);
    if (existingSeries != null &&
        (existingSeries.thumbnailPath.isEmpty || isReference)) {
      await db.update(
        'pose_series',
        {'thumbnail_path': imagePath},
        where: 'id = ?',
        whereArgs: [seriesId],
      );
    }

    return record.copyWith(id: id);
  }

  Future<String> resolveImagePath(String storedPath) {
    return fileStorageService.resolveAbsolutePath(storedPath);
  }
}
