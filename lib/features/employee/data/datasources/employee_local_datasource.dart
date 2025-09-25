import 'dart:convert';
import 'dart:typed_data';

import 'package:injectable/injectable.dart';
import 'package:sqflite/sqflite.dart';

import '../../../../core/utils/logger.dart';
import '../../domain/entities/employee.dart';
import '../../domain/entities/face_image.dart';
import '../models/employee_model.dart';
import '../models/face_image_model.dart';

class EmployeeLocalDataSource {
  final Database _database;

  EmployeeLocalDataSource({@factoryParam Database? database})
      : assert(database != null, 'Database is required'),
        _database = database!;

  static const String _employeesTable = 'employees';
  static const String _timeRecordsTable = 'time_records';
  static const String _faceEncodingsTable = 'face_encodings';
  static const String _faceImagesTable = 'face_images';
  static const String _syncMetadataTable = 'sync_metadata';

  /// Helper method to build EmployeeModel from database map with face encodings and images
  EmployeeModel _buildEmployeeFromDatabase(
    Map<String, dynamic> map,
    List<FaceEncoding> encodings, [
    List<FaceImage>? faceImages,
  ]) {
    // Use the fromDatabase constructor for basic employee data
    final employee = EmployeeModel.fromDatabase(map);

    // Create a new instance with the face encodings and images
    return EmployeeModel(
      id: employee.id,
      name: employee.name,
      email: employee.email,
      phoneNumber: employee.phoneNumber,
      department: employee.department,
      position: employee.position,
      employeeCode: employee.employeeCode,
      photoUrl: employee.photoUrl,
      photoBytes: employee.photoBytes,
      faceEncodings: encodings,
      faceImages: faceImages ?? [],
      isActive: employee.isActive,
      metadata: employee.metadata,
      createdAt: employee.createdAt,
      updatedAt: employee.updatedAt,
      lastSyncedAt: employee.lastSyncedAt,
    );
  }

  /// Initialize database tables
  static Future<void> createTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_employeesTable (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        email TEXT,
        phone_number TEXT,
        department TEXT,
        position TEXT,
        employee_code TEXT,
        photo_url TEXT,
        photo_bytes BLOB,
        is_active INTEGER DEFAULT 1,
        metadata TEXT,
        created_at TEXT,
        updated_at TEXT,
        last_synced_at TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_timeRecordsTable (
        id TEXT PRIMARY KEY,
        employee_id TEXT NOT NULL,
        employee_name TEXT NOT NULL,
        clock_in_time TEXT,
        clock_out_time TEXT,
        clock_in_photo TEXT,
        clock_out_photo TEXT,
        clock_in_confidence REAL,
        clock_out_confidence REAL,
        clock_in_location TEXT,
        clock_out_location TEXT,
        status TEXT NOT NULL,
        total_hours INTEGER,
        metadata TEXT,
        created_at TEXT,
        synced INTEGER DEFAULT 0,
        FOREIGN KEY (employee_id) REFERENCES $_employeesTable(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_faceEncodingsTable (
        id TEXT PRIMARY KEY,
        employee_id TEXT NOT NULL,
        embedding TEXT NOT NULL,
        quality REAL NOT NULL,
        source TEXT,
        metadata TEXT,
        image_bytes BLOB,
        created_at TEXT NOT NULL,
        FOREIGN KEY (employee_id) REFERENCES $_employeesTable(id)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_syncMetadataTable (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_faceImagesTable (
        id TEXT PRIMARY KEY,
        employee_id TEXT NOT NULL,
        image_bytes BLOB NOT NULL,
        source TEXT NOT NULL,
        captured_at TEXT NOT NULL,
        encoding_id TEXT,
        quality REAL,
        metadata TEXT,
        FOREIGN KEY (employee_id) REFERENCES $_employeesTable(id),
        FOREIGN KEY (encoding_id) REFERENCES $_faceEncodingsTable(id)
      )
    ''');

    // Create indexes for better performance
    await db.execute('CREATE INDEX IF NOT EXISTS idx_employee_code ON $_employeesTable(employee_code)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_time_records_employee ON $_timeRecordsTable(employee_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_time_records_date ON $_timeRecordsTable(clock_in_time)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_face_encodings_employee ON $_faceEncodingsTable(employee_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_face_images_employee ON $_faceImagesTable(employee_id)');
  }

  /// Get all employees
  Future<List<EmployeeModel>> getEmployees() async {
    try {
      final List<Map<String, dynamic>> maps = await _database.query(
        _employeesTable,
        where: 'is_active = ?',
        whereArgs: [1],
        orderBy: 'name ASC',
      );

      final employees = <EmployeeModel>[];
      for (final map in maps) {
        // Get face encodings for each employee
        final encodings = await getFaceEncodings(map['id']);

        // Use the helper method to build employee with encodings
        final employee = _buildEmployeeFromDatabase(map, encodings);
        employees.add(employee);
      }

      Logger.debug('Retrieved ${employees.length} employees from local storage');
      return employees;
    } catch (e) {
      Logger.error('Failed to get employees from local storage', error: e);
      throw Exception('Failed to get employees: $e');
    }
  }

  /// Get single employee by ID
  Future<EmployeeModel?> getEmployee(String id) async {
    try {
      final List<Map<String, dynamic>> maps = await _database.query(
        _employeesTable,
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );

      if (maps.isEmpty) return null;

      final map = maps.first;
      final encodings = await getFaceEncodings(id);

      // Use the helper method to build employee with encodings
      return _buildEmployeeFromDatabase(map, encodings);
    } catch (e) {
      Logger.error('Failed to get employee $id', error: e);
      return null;
    }
  }

  /// Save employees
  Future<void> saveEmployees(List<EmployeeModel> employees) async {
    try {
      final batch = _database.batch();

      for (final employee in employees) {
        batch.insert(
          _employeesTable,
          {
            'id': employee.id,
            'name': employee.name,
            'email': employee.email,
            'phone_number': employee.phoneNumber,
            'department': employee.department,
            'position': employee.position,
            'employee_code': employee.employeeCode,
            'photo_url': employee.photoUrl,
            'photo_bytes': employee.photoBytes,
            'is_active': employee.isActive ? 1 : 0,
            'metadata': employee.metadata != null ? json.encode(employee.metadata) : null,
            'created_at': employee.createdAt?.toIso8601String(),
            'updated_at': employee.updatedAt?.toIso8601String(),
            'last_synced_at': DateTime.now().toIso8601String(),
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );

        // Save face encodings
        for (final encoding in employee.faceEncodings) {
          batch.insert(
            _faceEncodingsTable,
            {
              'id': encoding.id,
              'employee_id': employee.id,
              'embedding': encoding.embedding.join(','),
              'quality': encoding.quality,
              'source': encoding.source,
              'metadata': encoding.metadata != null ? json.encode(encoding.metadata) : null,
              'created_at': encoding.createdAt.toIso8601String(),
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      }

      await batch.commit(noResult: true);
      Logger.debug('Saved ${employees.length} employees to local storage');
    } catch (e) {
      Logger.error('Failed to save employees', error: e);
      throw Exception('Failed to save employees: $e');
    }
  }

  /// Save single employee
  Future<void> saveEmployee(EmployeeModel employee) async {
    await saveEmployees([employee]);
  }

  /// Delete employee
  Future<void> deleteEmployee(String id) async {
    try {
      await _database.delete(
        _employeesTable,
        where: 'id = ?',
        whereArgs: [id],
      );
      Logger.debug('Deleted employee $id');
    } catch (e) {
      Logger.error('Failed to delete employee $id', error: e);
      throw Exception('Failed to delete employee: $e');
    }
  }

  /// Clear all employees
  Future<void> clearEmployees() async {
    try {
      await _database.delete(_employeesTable);
      await _database.delete(_faceEncodingsTable);
      Logger.debug('Cleared all employees');
    } catch (e) {
      Logger.error('Failed to clear employees', error: e);
      throw Exception('Failed to clear employees: $e');
    }
  }

  /// Get face encodings for employee
  Future<List<FaceEncodingModel>> getFaceEncodings(String employeeId) async {
    try {
      final List<Map<String, dynamic>> maps = await _database.query(
        _faceEncodingsTable,
        where: 'employee_id = ?',
        whereArgs: [employeeId],
        orderBy: 'created_at DESC',
      );

      return maps.map((map) {
        final embeddingStr = map['embedding'] as String;
        final embeddingValues = embeddingStr.split(',').map((e) => double.parse(e)).toList();

        return FaceEncodingModel(
          id: map['id'],
          embedding: Float32List.fromList(embeddingValues),
          quality: map['quality'],
          createdAt: DateTime.parse(map['created_at']),
          source: map['source'],
          imageBytes: map['image_bytes'] as Uint8List?,
          metadata: map['metadata'] != null ? json.decode(map['metadata']) : null,
        );
      }).toList();
    } catch (e) {
      Logger.error('Failed to get face encodings for $employeeId', error: e);
      return [];
    }
  }

  /// Save face encoding
  Future<void> saveFaceEncoding(String employeeId, FaceEncodingModel encoding) async {
    try {
      await _database.insert(
        _faceEncodingsTable,
        {
          'id': encoding.id,
          'employee_id': employeeId,
          'embedding': encoding.embedding.join(','),
          'quality': encoding.quality,
          'source': encoding.source,
          'metadata': encoding.metadata != null ? json.encode(encoding.metadata) : null,
          'image_bytes': encoding.imageBytes, // Store the image bytes
          'created_at': encoding.createdAt.toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      Logger.debug('Saved face encoding for employee $employeeId');
    } catch (e) {
      Logger.error('Failed to save face encoding', error: e);
      throw Exception('Failed to save face encoding: $e');
    }
  }

  /// Get time records
  Future<List<EmployeeTimeRecordModel>> getTimeRecords({
    DateTime? date,
    String? employeeId,
  }) async {
    try {
      String where = '1=1';
      final whereArgs = <dynamic>[];

      if (employeeId != null) {
        where += ' AND employee_id = ?';
        whereArgs.add(employeeId);
      }

      if (date != null) {
        final startOfDay = DateTime(date.year, date.month, date.day);
        final endOfDay = startOfDay.add(const Duration(days: 1));
        where += ' AND clock_in_time >= ? AND clock_in_time < ?';
        whereArgs.add(startOfDay.toIso8601String());
        whereArgs.add(endOfDay.toIso8601String());
      }

      final List<Map<String, dynamic>> maps = await _database.query(
        _timeRecordsTable,
        where: where,
        whereArgs: whereArgs,
        orderBy: 'clock_in_time DESC',
      );

      return maps.map((map) => EmployeeTimeRecordModel(
        id: map['id'],
        employeeId: map['employee_id'],
        employeeName: map['employee_name'],
        clockInTime: map['clock_in_time'] != null ? DateTime.parse(map['clock_in_time']) : null,
        clockOutTime: map['clock_out_time'] != null ? DateTime.parse(map['clock_out_time']) : null,
        clockInPhoto: map['clock_in_photo'],
        clockOutPhoto: map['clock_out_photo'],
        clockInConfidence: map['clock_in_confidence'],
        clockOutConfidence: map['clock_out_confidence'],
        clockInLocation: map['clock_in_location'] != null ? json.decode(map['clock_in_location']) : null,
        clockOutLocation: map['clock_out_location'] != null ? json.decode(map['clock_out_location']) : null,
        status: map['status'],
        totalHours: map['total_hours'] != null ? Duration(milliseconds: map['total_hours']) : null,
        metadata: map['metadata'] != null ? json.decode(map['metadata']) : null,
      )).toList();
    } catch (e) {
      Logger.error('Failed to get time records', error: e);
      return [];
    }
  }

  /// Save time record
  Future<void> saveTimeRecord(EmployeeTimeRecordModel record) async {
    try {
      await _database.insert(
        _timeRecordsTable,
        {
          'id': record.id,
          'employee_id': record.employeeId,
          'employee_name': record.employeeName,
          'clock_in_time': record.clockInTime?.toIso8601String(),
          'clock_out_time': record.clockOutTime?.toIso8601String(),
          'clock_in_photo': record.clockInPhoto,
          'clock_out_photo': record.clockOutPhoto,
          'clock_in_confidence': record.clockInConfidence,
          'clock_out_confidence': record.clockOutConfidence,
          'clock_in_location': record.clockInLocation != null ? json.encode(record.clockInLocation) : null,
          'clock_out_location': record.clockOutLocation != null ? json.encode(record.clockOutLocation) : null,
          'status': record.status,
          'total_hours': record.totalHours?.inMilliseconds,
          'metadata': record.metadata != null ? json.encode(record.metadata) : null,
          'created_at': DateTime.now().toIso8601String(),
          'synced': 0,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      Logger.debug('Saved time record ${record.id}');
    } catch (e) {
      Logger.error('Failed to save time record', error: e);
      throw Exception('Failed to save time record: $e');
    }
  }

  /// Get last sync date
  Future<DateTime?> getLastSyncDate() async {
    try {
      final List<Map<String, dynamic>> maps = await _database.query(
        _syncMetadataTable,
        where: 'key = ?',
        whereArgs: ['last_employee_sync'],
        limit: 1,
      );

      if (maps.isEmpty) return null;

      return DateTime.parse(maps.first['value']);
    } catch (e) {
      Logger.error('Failed to get last sync date', error: e);
      return null;
    }
  }

  /// Update last sync date
  Future<void> updateLastSyncDate(DateTime date) async {
    try {
      await _database.insert(
        _syncMetadataTable,
        {
          'key': 'last_employee_sync',
          'value': date.toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      Logger.debug('Updated last sync date to $date');
    } catch (e) {
      Logger.error('Failed to update last sync date', error: e);
      throw Exception('Failed to update last sync date: $e');
    }
  }

  /// Clear all employees from local storage
  Future<void> clearAllEmployees() async {
    try {
      await _database.delete(_employeesTable);
      Logger.info('Cleared all employees from local storage');
    } catch (e) {
      Logger.error('Failed to clear employees', error: e);
      throw Exception('Failed to clear employees: $e');
    }
  }

  /// Get all employees from local storage
  Future<List<Employee>> getAllEmployees() async {
    try {
      final List<Map<String, dynamic>> maps = await _database.query(
        _employeesTable,
        orderBy: 'name ASC',
      );

      if (maps.isEmpty) {
        return [];
      }

      final employees = <Employee>[];
      for (final map in maps) {
        try {
          // Get face encodings for each employee
          final encodings = await getFaceEncodings(map['id']);
          // Get face images for each employee
          final faceImages = await getFaceImages(map['id']);

          // Use the helper method to build employee with encodings and images
          final employee = _buildEmployeeFromDatabase(map, encodings, faceImages);
          employees.add(employee);
        } catch (e) {
          Logger.error('Failed to parse employee from database', error: e);
        }
      }

      Logger.debug('Loaded ${employees.length} employees from local storage');
      return employees;
    } catch (e) {
      Logger.error('Failed to get all employees', error: e);
      throw Exception('Failed to get all employees: $e');
    }
  }

  /// Get a single employee by ID
  Future<Employee?> getEmployeeById(String employeeId) async {
    try {
      final List<Map<String, dynamic>> maps = await _database.query(
        _employeesTable,
        where: 'id = ?',
        whereArgs: [employeeId],
        limit: 1,
      );

      if (maps.isEmpty) {
        return null;
      }

      // Get face encodings for the employee
      final encodings = await getFaceEncodings(employeeId);
      // Get face images for the employee
      final faceImages = await getFaceImages(employeeId);

      // Use the helper method to build employee with encodings and images
      return _buildEmployeeFromDatabase(maps.first, encodings, faceImages);
    } catch (e) {
      Logger.error('Failed to get employee by ID', error: e);
      return null;
    }
  }

  /// Delete a face encoding
  Future<void> deleteFaceEncoding(String encodingId) async {
    try {
      await _database.delete(
        _faceEncodingsTable,
        where: 'id = ?',
        whereArgs: [encodingId],
      );
      Logger.debug('Deleted face encoding $encodingId');
    } catch (e) {
      Logger.error('Failed to delete face encoding', error: e);
      throw Exception('Failed to delete face encoding: $e');
    }
  }

  /// Get face images for an employee
  Future<List<FaceImage>> getFaceImages(String employeeId) async {
    try {
      final List<Map<String, dynamic>> maps = await _database.query(
        _faceImagesTable,
        where: 'employee_id = ?',
        whereArgs: [employeeId],
        orderBy: 'captured_at DESC',
      );

      return maps.map((map) => FaceImageModel.fromDatabase(map)).toList();
    } catch (e) {
      Logger.error('Failed to get face images for $employeeId', error: e);
      return [];
    }
  }

  /// Save a face image
  Future<void> saveFaceImage(FaceImageModel faceImage) async {
    try {
      await _database.insert(
        _faceImagesTable,
        faceImage.toDatabase(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      Logger.debug('Saved face image ${faceImage.id} for employee ${faceImage.employeeId}');
    } catch (e) {
      Logger.error('Failed to save face image', error: e);
      throw Exception('Failed to save face image: $e');
    }
  }

  /// Delete a face image
  Future<void> deleteFaceImage(String imageId) async {
    try {
      await _database.delete(
        _faceImagesTable,
        where: 'id = ?',
        whereArgs: [imageId],
      );
      Logger.debug('Deleted face image $imageId');
    } catch (e) {
      Logger.error('Failed to delete face image', error: e);
      throw Exception('Failed to delete face image: $e');
    }
  }

  /// Get a single face image by ID
  Future<FaceImage?> getFaceImageById(String imageId) async {
    try {
      final List<Map<String, dynamic>> maps = await _database.query(
        _faceImagesTable,
        where: 'id = ?',
        whereArgs: [imageId],
        limit: 1,
      );

      if (maps.isEmpty) return null;
      return FaceImageModel.fromDatabase(maps.first);
    } catch (e) {
      Logger.error('Failed to get face image by ID', error: e);
      return null;
    }
  }

  /// Clear all face encodings from database (useful for dimension migration)
  Future<void> clearAllFaceEncodings() async {
    try {
      await _database.delete(_faceEncodingsTable);
      Logger.info('Cleared all face encodings from database');
    } catch (e) {
      Logger.error('Failed to clear face encodings', error: e);
      throw Exception('Failed to clear face encodings: $e');
    }
  }
}