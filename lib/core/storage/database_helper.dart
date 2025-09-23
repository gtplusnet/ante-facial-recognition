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
  static const int _databaseVersion = 1;

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
        employee_id TEXT,
        confidence REAL NOT NULL,
        recognition_time INTEGER NOT NULL,
        success INTEGER NOT NULL,
        error_message TEXT,
        created_at TEXT NOT NULL
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
      // Example migration for version 2
      // await db.execute('ALTER TABLE employees ADD COLUMN email TEXT');
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