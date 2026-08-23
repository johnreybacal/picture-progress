import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

class DatabaseService {
  Database? _database;

  Future<Database> get database async {
    if (_database != null) {
      return _database!;
    }

    _database = await _open();
    return _database!;
  }

  Future<Database> _open() async {
    final documentsDirectory = await getApplicationDocumentsDirectory();
    final databasePath = path.join(
      documentsDirectory.path,
      'picture_progress.db',
    );

    return openDatabase(
      databasePath,
      version: 1,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE pose_series (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            created_at INTEGER NOT NULL,
            thumbnail_path TEXT NOT NULL DEFAULT ''
          )
        ''');

        await db.execute('''
          CREATE TABLE pose_records (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            series_id INTEGER NOT NULL,
            image_path TEXT NOT NULL,
            timestamp INTEGER NOT NULL,
            landmarks_json TEXT NOT NULL,
            bounding_box_json TEXT NOT NULL,
            anchor_center_json TEXT NOT NULL,
            is_reference INTEGER NOT NULL DEFAULT 0,
            FOREIGN KEY (series_id) REFERENCES pose_series(id) ON DELETE CASCADE
          )
        ''');

        await db.execute(
          'CREATE INDEX idx_pose_records_series_timestamp ON pose_records(series_id, timestamp)',
        );
      },
    );
  }
}
