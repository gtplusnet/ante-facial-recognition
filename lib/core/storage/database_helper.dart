import 'package:injectable/injectable.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../../features/employee/data/datasources/employee_local_datasource.dart';
import '../utils/logger.dart';

@singleton
class DatabaseHelper {
  Database? _database;

  DatabaseHelper();

  static const String _databaseName = 'ante_facial_recognition.db';
  static const int _databaseVersion = 3; // Incremented for image_bytes column in face_encodings

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await initializeDatabase();
    return _database!;
  }

  Future<Database> initializeDatabase() async {
    final databasesPath = await getDatabasesPath();
    final path = join(databasesPath, _databaseName);

    Logger.database('Initializing database at: $path');

    return await openDatabase(
      path,
      version: _databaseVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
      onOpen: (db) {
        Logger.database('Database opened successfully');
      },
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    Logger.database('Creating database tables...');

    // Create tables using EmployeeLocalDataSource
    await EmployeeLocalDataSource.createTables(db);

    // Additional app-specific tables
    // Offline queue table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS offline_queue (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        endpoint TEXT NOT NULL,
        method TEXT NOT NULL,
        data TEXT,
        headers TEXT,
        retry_count INTEGER DEFAULT 0,
        max_retries INTEGER DEFAULT 3,
        created_at TEXT NOT NULL
      )
    ''');

    // Face recognition logs table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS face_recognition_logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        timestamp TEXT NOT NULL,
        result_type TEXT NOT NULL,
        employee_id TEXT,
        employee_name TEXT,
        confidence REAL,
        quality REAL,
        processing_time_ms INTEGER NOT NULL,
        face_bounds TEXT,
        face_image BLOB,
        thumbnail_image BLOB,
        image_width INTEGER,
        image_height INTEGER,
        error_message TEXT,
        metadata TEXT,
        device_id TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT
      )
    ''');

    // Settings table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    Logger.database('Database tables created successfully');
  }

  Future<void> _onUpgrade(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    Logger.database(
      'Upgrading database from version $oldVersion to $newVersion',
    );

    // Handle database migrations here
    if (oldVersion < 2) {
      // Migration for version 2: Add timestamp column to face_recognition_logs if it doesn't exist
      Logger.database('Migrating to version 2: Checking face_recognition_logs table...');

      try {
        // Check if the timestamp column exists
        final tableInfo = await db.rawQuery('PRAGMA table_info(face_recognition_logs)');
        final hasTimestamp = tableInfo.any((column) => column['name'] == 'timestamp');

        if (!hasTimestamp) {
          Logger.database('Adding timestamp column to face_recognition_logs table...');

          // Since SQLite doesn't support adding NOT NULL columns without default values,
          // we need to recreate the table
          await db.execute('DROP TABLE IF EXISTS face_recognition_logs_backup');

          // Create a backup table with the new schema
          await db.execute('''
            CREATE TABLE face_recognition_logs_backup (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              timestamp TEXT NOT NULL,
              result_type TEXT NOT NULL,
              employee_id TEXT,
              employee_name TEXT,
              confidence REAL,
              quality REAL,
              processing_time_ms INTEGER NOT NULL,
              face_bounds TEXT,
              face_image BLOB,
              thumbnail_image BLOB,
              image_width INTEGER,
              image_height INTEGER,
              error_message TEXT,
              metadata TEXT,
              device_id TEXT,
              created_at TEXT NOT NULL,
              updated_at TEXT
            )
          ''');

          // Check if old table exists and has data
          final oldTableExists = tableInfo.isNotEmpty;
          if (oldTableExists) {
            // Copy data from old table to new table, using created_at as timestamp if needed
            await db.execute('''
              INSERT INTO face_recognition_logs_backup
              SELECT id,
                     COALESCE(created_at, datetime('now')) as timestamp,
                     result_type, employee_id, employee_name, confidence, quality,
                     processing_time_ms, face_bounds, face_image, thumbnail_image,
                     image_width, image_height, error_message, metadata, device_id,
                     created_at, created_at as updated_at
              FROM face_recognition_logs
            ''');

            // Drop old table
            await db.execute('DROP TABLE face_recognition_logs');
          }

          // Rename backup table to original name
          await db.execute('ALTER TABLE face_recognition_logs_backup RENAME TO face_recognition_logs');

          Logger.database('Successfully added timestamp column to face_recognition_logs table');
        } else {
          Logger.database('Timestamp column already exists in face_recognition_logs table');
        }
      } catch (e) {
        Logger.error('Failed to migrate face_recognition_logs table', error: e);

        // As a fallback, recreate the table with the correct schema
        Logger.database('Recreating face_recognition_logs table with correct schema...');

        // Drop the old table completely
        await db.execute('DROP TABLE IF EXISTS face_recognition_logs');

        // Create the new table with proper schema
        await db.execute('''
          CREATE TABLE face_recognition_logs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            timestamp TEXT NOT NULL,
            result_type TEXT NOT NULL,
            employee_id TEXT,
            employee_name TEXT,
            confidence REAL,
            quality REAL,
            processing_time_ms INTEGER NOT NULL,
            face_bounds TEXT,
            face_image BLOB,
            thumbnail_image BLOB,
            image_width INTEGER,
            image_height INTEGER,
            error_message TEXT,
            metadata TEXT,
            device_id TEXT,
            created_at TEXT NOT NULL,
            updated_at TEXT
          )
        ''');
        Logger.database('Successfully recreated face_recognition_logs table with timestamp column');
      }
    }

    if (oldVersion < 3) {
      // Migration for version 3: Add image_bytes column to face_encodings table
      Logger.database('Migrating to version 3: Adding image_bytes column to face_encodings table...');

      try {
        // Check if face_encodings table exists
        final tables = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name='face_encodings'"
        );

        if (tables.isNotEmpty) {
          // Check if the image_bytes column exists
          final tableInfo = await db.rawQuery('PRAGMA table_info(face_encodings)');
          final hasImageBytes = tableInfo.any((column) => column['name'] == 'image_bytes');

          if (!hasImageBytes) {
            Logger.database('Adding image_bytes column to face_encodings table...');

            // Add the column (SQLite allows adding nullable columns)
            await db.execute('ALTER TABLE face_encodings ADD COLUMN image_bytes BLOB');

            Logger.database('Successfully added image_bytes column to face_encodings table');
          } else {
            Logger.database('Image_bytes column already exists in face_encodings table');
          }
        } else {
          Logger.database('face_encodings table does not exist, will be created with new schema');
        }

        // Also ensure face_images table exists
        final faceImagesTables = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name='face_images'"
        );

        if (faceImagesTables.isEmpty) {
          Logger.database('Creating face_images table...');

          await db.execute('''
            CREATE TABLE IF NOT EXISTS face_images (
              id TEXT PRIMARY KEY,
              employee_id TEXT NOT NULL,
              image_bytes BLOB NOT NULL,
              source TEXT,
              captured_at TEXT NOT NULL,
              encoding_id TEXT,
              quality REAL,
              created_at TEXT NOT NULL,
              updated_at TEXT,
              FOREIGN KEY (employee_id) REFERENCES employees(id) ON DELETE CASCADE
            )
          ''');

          // Create index for faster queries
          await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_face_images_employee_id ON face_images(employee_id)'
          );

          Logger.database('Successfully created face_images table');
        } else {
          Logger.database('face_images table already exists');
        }

      } catch (e) {
        Logger.error('Failed to migrate to version 3', error: e);
        // Continue anyway - the app will work with the new schema for new installs
      }
    }
  }

  // Helper methods for common database operations
  Future<List<Map<String, dynamic>>> query(
    Database db,
    String table, {
    String? where,
    List<Object?>? whereArgs,
    String? orderBy,
    int? limit,
  }) async {
    try {
      final results = await db.query(
        table,
        where: where,
        whereArgs: whereArgs,
        orderBy: orderBy,
        limit: limit,
      );
      Logger.database('Query successful on table: $table, rows: ${results.length}');
      return results;
    } catch (e) {
      Logger.error('Database query failed on table: $table', error: e);
      rethrow;
    }
  }

  Future<int> insert(
    Database db,
    String table,
    Map<String, dynamic> values,
  ) async {
    try {
      values['created_at'] = DateTime.now().toIso8601String();
      values['updated_at'] = DateTime.now().toIso8601String();
      final id = await db.insert(
        table,
        values,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      Logger.database('Insert successful on table: $table, id: $id');
      return id;
    } catch (e) {
      Logger.error('Database insert failed on table: $table', error: e);
      rethrow;
    }
  }

  Future<int> update(
    Database db,
    String table,
    Map<String, dynamic> values, {
    String? where,
    List<Object?>? whereArgs,
  }) async {
    try {
      values['updated_at'] = DateTime.now().toIso8601String();
      final count = await db.update(
        table,
        values,
        where: where,
        whereArgs: whereArgs,
      );
      Logger.database('Update successful on table: $table, rows affected: $count');
      return count;
    } catch (e) {
      Logger.error('Database update failed on table: $table', error: e);
      rethrow;
    }
  }

  Future<int> delete(
    Database db,
    String table, {
    String? where,
    List<Object?>? whereArgs,
  }) async {
    try {
      final count = await db.delete(
        table,
        where: where,
        whereArgs: whereArgs,
      );
      Logger.database('Delete successful on table: $table, rows affected: $count');
      return count;
    } catch (e) {
      Logger.error('Database delete failed on table: $table', error: e);
      rethrow;
    }
  }

  Future<void> clearTable(Database db, String table) async {
    try {
      await db.delete(table);
      Logger.database('Table cleared: $table');
    } catch (e) {
      Logger.error('Failed to clear table: $table', error: e);
      rethrow;
    }
  }

  Future<void> closeDatabase(Database db) async {
    try {
      await db.close();
      Logger.database('Database closed');
    } catch (e) {
      Logger.error('Failed to close database', error: e);
      rethrow;
    }
  }
}