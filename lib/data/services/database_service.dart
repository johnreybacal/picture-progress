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
      version: 6,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async {
        await _createSchema(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute(
            "ALTER TABLE pose_series ADD COLUMN baseline_metadata_json TEXT NOT NULL DEFAULT ''",
          );
          await db.execute(
            "ALTER TABLE pose_records ADD COLUMN label TEXT NOT NULL DEFAULT ''",
          );
          await db.execute(
            "ALTER TABLE pose_records ADD COLUMN camera_lens TEXT NOT NULL DEFAULT 'front'",
          );
          await db.execute(
            'ALTER TABLE pose_records ADD COLUMN image_width INTEGER NOT NULL DEFAULT 0',
          );
          await db.execute(
            'ALTER TABLE pose_records ADD COLUMN image_height INTEGER NOT NULL DEFAULT 0',
          );
        }
        if (oldVersion < 3) {
          await db.execute(
            "ALTER TABLE pose_records ADD COLUMN capture_orientation TEXT NOT NULL DEFAULT 'portrait'",
          );
          await db.execute(
            'ALTER TABLE pose_records ADD COLUMN baseline_pose INTEGER NOT NULL DEFAULT 0',
          );
          await db.execute(
            'UPDATE pose_records SET baseline_pose = is_reference',
          );
        }
        if (oldVersion < 4) {
          await db.execute(
            "ALTER TABLE pose_series ADD COLUMN preferred_lens TEXT NOT NULL DEFAULT ''",
          );
          await db.execute('''
            UPDATE pose_series
            SET preferred_lens = COALESCE(
              (
                SELECT camera_lens
                FROM pose_records
                WHERE pose_records.series_id = pose_series.id
                  AND (pose_records.baseline_pose = 1 OR pose_records.is_reference = 1)
                ORDER BY pose_records.timestamp ASC
                LIMIT 1
              ),
              (
                SELECT camera_lens
                FROM pose_records
                WHERE pose_records.series_id = pose_series.id
                ORDER BY pose_records.timestamp ASC
                LIMIT 1
              ),
              ''
            )
            WHERE preferred_lens = ''
          ''');
        }
        if (oldVersion < 5) {
          await db.execute(
            'ALTER TABLE pose_series ADD COLUMN last_used_zoom_level REAL NOT NULL DEFAULT 0',
          );
        }
        if (oldVersion < 6) {
          await _migrateToVersion6(db);
        }
      },
    );
  }

  Future<void> _createSchema(Database db) async {
    await db.execute('''
      CREATE TABLE pose_series (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        thumbnail_path TEXT NOT NULL DEFAULT '',
        preferred_lens TEXT NOT NULL DEFAULT '',
        last_used_zoom_level REAL NOT NULL DEFAULT 0,
        last_used_aspect_ratio TEXT NOT NULL DEFAULT 'full'
      )
    ''');

    await db.execute('''
      CREATE TABLE pose_records (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        series_id INTEGER NOT NULL,
        image_path TEXT NOT NULL,
        label TEXT NOT NULL DEFAULT '',
        timestamp INTEGER NOT NULL,
        landmarks_json TEXT NOT NULL,
        bounding_box_json TEXT NOT NULL,
        anchor_center_json TEXT NOT NULL,
        camera_lens TEXT NOT NULL DEFAULT 'front',
        capture_orientation TEXT NOT NULL DEFAULT 'portrait',
        image_width INTEGER NOT NULL DEFAULT 0,
        image_height INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (series_id) REFERENCES pose_series(id) ON DELETE CASCADE
      )
    ''');

    await db.execute(
      'CREATE INDEX idx_pose_records_series_timestamp ON pose_records(series_id, timestamp)',
    );
  }

  Future<void> _migrateToVersion6(Database db) async {
    await db.execute('PRAGMA foreign_keys = OFF');
    try {
      await db.transaction((txn) async {
        await txn.execute(
          'DROP INDEX IF EXISTS idx_pose_records_series_timestamp',
        );

        await txn.execute('''
          CREATE TABLE pose_series_v6 (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            created_at INTEGER NOT NULL,
            thumbnail_path TEXT NOT NULL DEFAULT '',
            preferred_lens TEXT NOT NULL DEFAULT '',
            last_used_zoom_level REAL NOT NULL DEFAULT 0,
            last_used_aspect_ratio TEXT NOT NULL DEFAULT 'full'
          )
        ''');
        await txn.execute('''
          INSERT INTO pose_series_v6 (
            id,
            name,
            created_at,
            thumbnail_path,
            preferred_lens,
            last_used_zoom_level,
            last_used_aspect_ratio
          )
          SELECT
            id,
            name,
            created_at,
            COALESCE(thumbnail_path, ''),
            COALESCE(preferred_lens, ''),
            COALESCE(last_used_zoom_level, 0),
            'full'
          FROM pose_series
        ''');

        await txn.execute('''
          CREATE TABLE pose_records_v6 (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            series_id INTEGER NOT NULL,
            image_path TEXT NOT NULL,
            label TEXT NOT NULL DEFAULT '',
            timestamp INTEGER NOT NULL,
            landmarks_json TEXT NOT NULL,
            bounding_box_json TEXT NOT NULL,
            anchor_center_json TEXT NOT NULL,
            camera_lens TEXT NOT NULL DEFAULT 'front',
            capture_orientation TEXT NOT NULL DEFAULT 'portrait',
            image_width INTEGER NOT NULL DEFAULT 0,
            image_height INTEGER NOT NULL DEFAULT 0,
            FOREIGN KEY (series_id) REFERENCES pose_series(id) ON DELETE CASCADE
          )
        ''');
        await txn.execute('''
          INSERT INTO pose_records_v6 (
            id,
            series_id,
            image_path,
            label,
            timestamp,
            landmarks_json,
            bounding_box_json,
            anchor_center_json,
            camera_lens,
            capture_orientation,
            image_width,
            image_height
          )
          SELECT
            id,
            series_id,
            image_path,
            COALESCE(label, ''),
            timestamp,
            landmarks_json,
            bounding_box_json,
            anchor_center_json,
            COALESCE(camera_lens, 'front'),
            COALESCE(capture_orientation, 'portrait'),
            COALESCE(image_width, 0),
            COALESCE(image_height, 0)
          FROM pose_records
        ''');

        await txn.execute('DROP TABLE pose_records');
        await txn.execute('DROP TABLE pose_series');
        await txn.execute('ALTER TABLE pose_series_v6 RENAME TO pose_series');
        await txn.execute('ALTER TABLE pose_records_v6 RENAME TO pose_records');
        await txn.execute(
          'CREATE INDEX idx_pose_records_series_timestamp ON pose_records(series_id, timestamp)',
        );
      });
    } finally {
      await db.execute('PRAGMA foreign_keys = ON');
    }
  }
}
