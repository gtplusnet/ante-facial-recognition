import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get_it/get_it.dart';
import 'package:injectable/injectable.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../../features/employee/data/datasources/employee_local_datasource.dart';
import '../../features/employee/data/datasources/face_encoding_cache.dart';
import '../bloc/global_error/global_error_bloc.dart';
import '../navigation/navigation_service.dart';
import '../network/api_client.dart';
import '../network/dio_factory.dart';
import '../router/app_router.dart';
import '../services/offline_queue_manager.dart';
import '../storage/database_helper.dart';
import '../storage/secure_storage_helper.dart';
import 'injection.config.dart';

final GetIt getIt = GetIt.instance;

@InjectableInit(
  initializerName: 'init',
  preferRelativeImports: true,
  asExtension: true,
)
Future<void> configureDependencies() async {
  // Register external dependencies BEFORE init
  await _registerExternalDependencies();

  // Initialize generated dependencies
  getIt.init();

  // Setup navigation service
  getIt<NavigationService>().setRouter(AppRouter.router);
}

Future<void> _registerExternalDependencies() async {
  // SharedPreferences
  final sharedPreferences = await SharedPreferences.getInstance();
  getIt.registerSingleton<SharedPreferences>(sharedPreferences);

  // FlutterSecureStorage
  const flutterSecureStorage = FlutterSecureStorage();
  getIt.registerSingleton<FlutterSecureStorage>(flutterSecureStorage);

  // Dio
  final dio = DioFactory.create();
  getIt.registerSingleton<Dio>(dio);

  // Database - DatabaseHelper is registered automatically by injectable
  // We only need to manually register the Database instance
  final databaseHelper = DatabaseHelper();
  final database = await databaseHelper.initializeDatabase();
  getIt.registerSingleton<Database>(database);
}

@module
abstract class RegisterModule {
  @singleton
  ApiClient get apiClient => ApiClient(getIt<Dio>());

  @singleton
  SecureStorageHelper get secureStorage => SecureStorageHelper(
        getIt<FlutterSecureStorage>(),
      );

  // Provide factory for FaceEncodingCache with dependencies
  @singleton
  FaceEncodingCache faceEncodingCache(DatabaseHelper databaseHelper) =>
      FaceEncodingCache(
        databaseHelper: databaseHelper,
        secureStorage: getIt<FlutterSecureStorage>(),
      );

  // Provide factory for EmployeeLocalDataSource
  @singleton
  EmployeeLocalDataSource employeeLocalDataSource() =>
      EmployeeLocalDataSource(database: getIt<Database>());

  // Provide factory for OfflineQueueManager
  @singleton
  OfflineQueueManager offlineQueueManager() =>
      OfflineQueueManager(
        database: getIt<Database>(),
        dio: getIt<Dio>(),
      );
}