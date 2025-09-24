import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:path_provider/path_provider.dart';

import 'core/di/injection.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/utils/app_bloc_observer.dart';
import 'core/utils/logger.dart';
import 'features/authentication/presentation/bloc/auth_bloc.dart';
import 'features/authentication/presentation/bloc/auth_event.dart';
import 'features/employee/presentation/bloc/employee_bloc.dart';
import 'features/employee/presentation/bloc/employee_event.dart';

Future<void> main() async {
  await runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      // Setup orientation
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);

      // Setup status bar
      SystemChrome.setSystemUIOverlayStyle(
        const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarBrightness: Brightness.light,
          statusBarIconBrightness: Brightness.dark,
        ),
      );

      // Initialize Hydrated Storage
      final storageDirectory = await getApplicationDocumentsDirectory();
      HydratedBloc.storage = await HydratedStorage.build(
        storageDirectory: storageDirectory,
      );

      // Setup BLoC Observer
      Bloc.observer = AppBlocObserver();

      // Initialize Dependency Injection with error handling
      try {
        await configureDependencies();
        Logger.info('Dependency injection initialized successfully');
      } catch (e, stackTrace) {
        Logger.error('Failed to initialize dependencies',
          error: e,
          stackTrace: stackTrace
        );
        // Show error app if DI fails
        runApp(MaterialApp(
          home: Scaffold(
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 64, color: Colors.red),
                  const SizedBox(height: 16),
                  const Text(
                    'Failed to initialize app',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Error: ${e.toString()}',
                    style: const TextStyle(color: Colors.red),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ));
        return;
      }

      runApp(const AnteApp());
    },
    (error, stackTrace) {
      Logger.error('Uncaught error', error: error, stackTrace: stackTrace);
    },
  );
}

class AnteApp extends StatelessWidget {
  const AnteApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider<AuthBloc>(
          create: (_) => getIt<AuthBloc>()..add(const CheckAuthStatus()),
        ),
        BlocProvider<EmployeeBloc>(
          create: (_) => getIt<EmployeeBloc>(),
        ),
      ],
      child: ScreenUtilInit(
        designSize: const Size(375, 812), // iPhone X design size
        minTextAdapt: true,
        splitScreenMode: false,
        builder: (context, child) {
          return _DebugAutoTrigger(
            child: MaterialApp.router(
              title: 'ANTE Facial Recognition',
              debugShowCheckedModeBanner: false,
              theme: AppTheme.lightTheme,
              darkTheme: AppTheme.darkTheme,
              themeMode: ThemeMode.system,
              routerConfig: AppRouter.router,
            ),
          );
        },
      ),
    );
  }
}

class _DebugAutoTrigger extends StatefulWidget {
  final Widget child;

  const _DebugAutoTrigger({required this.child});

  @override
  State<_DebugAutoTrigger> createState() => _DebugAutoTriggerState();
}

class _DebugAutoTriggerState extends State<_DebugAutoTrigger> {
  @override
  void initState() {
    super.initState();
    // Trigger face encoding generation after 5 seconds
    Timer(const Duration(seconds: 5), () {
      Logger.info('=== DEBUG: Auto-triggering face encoding generation ===');
      try {
        final employeeBloc = context.read<EmployeeBloc>();
        employeeBloc.add(const GenerateAllFaceEmbeddings());
        Logger.info('=== DEBUG: Face encoding generation triggered successfully ===');
      } catch (e) {
        Logger.error('=== DEBUG: Failed to trigger face encoding generation ===', error: e);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}