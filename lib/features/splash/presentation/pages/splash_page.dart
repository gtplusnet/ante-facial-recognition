import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:get_it/get_it.dart';

import '../../../../core/services/initialization_service.dart';
import '../../../../core/utils/logger.dart';
import '../../../authentication/presentation/bloc/auth_bloc.dart';
import '../../../authentication/presentation/bloc/auth_event.dart';
import '../../../authentication/presentation/bloc/auth_state.dart';

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> with TickerProviderStateMixin {
  late AnimationController _fadeController;
  late AnimationController _scaleController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  InitializationStep _currentStep = InitializationStep.database;
  String _statusMessage = 'Starting up...';
  final Map<InitializationStep, bool> _completedSteps = {};
  bool _hasError = false;
  List<String> _errors = [];

  @override
  void initState() {
    super.initState();

    // Setup animations
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeIn,
    ));

    _scaleAnimation = Tween<double>(
      begin: 0.8,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _scaleController,
      curve: Curves.easeOutBack,
    ));

    // Start animations
    _fadeController.forward();
    _scaleController.forward();

    // Start initialization process
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    // Give splash screen some time to display
    await Future.delayed(const Duration(milliseconds: 500));

    try {
      // Get initialization service
      final initService = GetIt.instance<InitializationService>();

      // Initialize all services
      final result = await initService.initializeApp(
        onProgress: (step) {
          if (mounted) {
            setState(() {
              _currentStep = step;
              // Mark previous step as completed
              if (step.index > 0) {
                _completedSteps[InitializationStep.values[step.index - 1]] = true;
              }
            });
          }
        },
        onStatusUpdate: (message) {
          if (mounted) {
            setState(() {
              _statusMessage = message;
            });
          }
        },
      );

      // Mark all steps as completed on success
      if (result.success) {
        for (final step in InitializationStep.values) {
          _completedSteps[step] = true;
        }
      }

      if (!result.success) {
        Logger.error('Initialization had errors: ${result.errors.join(', ')}');
        setState(() {
          _hasError = true;
          _errors = result.errors;
        });

        // Check if this is a critical error (TFLite model loading failure)
        if (result.isCritical) {
          Logger.error('CRITICAL ERROR - Cannot continue without TFLite model');

          // Show blocking error dialog
          if (mounted) {
            await showDialog(
              context: context,
              barrierDismissible: false, // Cannot dismiss by tapping outside
              builder: (BuildContext dialogContext) => AlertDialog(
                title: const Row(
                  children: [
                    Icon(Icons.error_outline, color: Colors.red, size: 32),
                    SizedBox(width: 12),
                    Text('Critical Error'),
                  ],
                ),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Face recognition model failed to load. The app cannot function without the ML model.',
                      style: TextStyle(fontSize: 16),
                    ),
                    SizedBox(height: 16),
                    Text(
                      'Error details:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 8),
                    ...result.errors.map((error) => Padding(
                      padding: EdgeInsets.only(bottom: 4),
                      child: Text('• $error', style: TextStyle(fontSize: 14)),
                    )),
                    SizedBox(height: 16),
                    Text(
                      'Please contact support if this issue persists.',
                      style: TextStyle(fontStyle: FontStyle.italic, fontSize: 14),
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () {
                      Navigator.of(dialogContext).pop();
                      _retryInitialization();
                    },
                    child: Text('Retry', style: TextStyle(color: Colors.blue)),
                  ),
                ],
              ),
            );
          }
          return; // Don't continue to authentication
        }

        // Non-critical errors - continue after showing errors briefly
        await Future.delayed(const Duration(seconds: 2));
      }

      // Check authentication and navigate (only if not critical error)
      if (mounted && result.success || !result.isCritical) {
        _checkAuthenticationStatus();
      }
    } catch (e) {
      Logger.error('Fatal initialization error', error: e);
      if (mounted) {
        setState(() {
          _hasError = true;
          _errors = ['Fatal error: ${e.toString()}'];
        });
      }
      // Try to continue anyway after delay
      await Future.delayed(const Duration(seconds: 2));
      if (mounted) {
        _checkAuthenticationStatus();
      }
    }
  }

  Future<void> _checkAuthenticationStatus() async {
    if (mounted) {
      // Check authentication status
      context.read<AuthBloc>().add(const CheckAuthStatus());
    }
  }

  Future<void> _retryInitialization() async {
    setState(() {
      _hasError = false;
      _errors = [];
      _completedSteps.clear();
      _statusMessage = 'Retrying...';
    });
    await _initializeApp();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _scaleController.dispose();
    super.dispose();
  }

  Widget _buildStepIndicator(InitializationStep step) {
    final isCompleted = _completedSteps[step] ?? false;
    final isCurrent = _currentStep == step;
    final isPending = !isCompleted && !isCurrent;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isCompleted
                  ? Colors.green
                  : isCurrent
                      ? Colors.blue
                      : Colors.grey.shade600,
            ),
            child: isCompleted
                ? const Icon(Icons.check, size: 16, color: Colors.white)
                : isCurrent
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              step.displayName,
              style: TextStyle(
                color: isCompleted
                    ? Colors.green.shade300
                    : isCurrent
                        ? Colors.white
                        : Colors.grey.shade500,
                fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
          if (isCompleted)
            Icon(
              Icons.check_circle,
              size: 20,
              color: Colors.green.shade300,
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<AuthBloc, AuthState>(
      listener: (context, state) {
        if (state is AuthAuthenticated) {
          // Device is authenticated, go to daily logs (now the default)
          context.go('/daily-logs');
        } else if (state is AuthUnauthenticated) {
          // Device is not authenticated, go to setup
          context.go('/device-setup');
        } else if (state is AuthError) {
          // On error, go to device setup
          context.go('/device-setup');
        }
      },
      child: Scaffold(
        body: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Theme.of(context).primaryColor,
                Theme.of(context).primaryColor.withOpacity(0.8),
              ],
            ),
          ),
          child: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Logo and title
                      FadeTransition(
                        opacity: _fadeAnimation,
                        child: ScaleTransition(
                          scale: _scaleAnimation,
                          child: Column(
                            children: [
                              const Icon(
                                Icons.face,
                                size: 80,
                                color: Colors.white,
                              ),
                              const SizedBox(height: 16),
                              const Text(
                                'ANTE',
                                style: TextStyle(
                                  fontSize: 40,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                  letterSpacing: 2,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Facial Recognition',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.white.withOpacity(0.9),
                                  letterSpacing: 1,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 48),

                      // Initialization steps
                      if (!_hasError) ...[
                        Container(
                          constraints: const BoxConstraints(maxWidth: 400),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            children: [
                              const SizedBox(height: 16),
                              Text(
                                'Initializing Services',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.9),
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 8),
                              ...InitializationStep.values
                                  .where((step) => step != InitializationStep.complete)
                                  .map(_buildStepIndicator),
                              const SizedBox(height: 16),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                        // Status message
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 300),
                          child: Text(
                            _statusMessage,
                            key: ValueKey(_statusMessage),
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.8),
                              fontSize: 14,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],

                      // Error state
                      if (_hasError) ...[
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.red.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.red.withOpacity(0.5),
                            ),
                          ),
                          child: Column(
                            children: [
                              const Icon(
                                Icons.warning_amber_rounded,
                                size: 48,
                                color: Colors.orange,
                              ),
                              const SizedBox(height: 16),
                              const Text(
                                'Initialization Warning',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Some services failed to initialize:',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.8),
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 8),
                              ..._errors.map((error) => Padding(
                                padding: const EdgeInsets.symmetric(vertical: 2),
                                child: Text(
                                  '• $error',
                                  style: TextStyle(
                                    color: Colors.orange.shade200,
                                    fontSize: 12,
                                  ),
                                ),
                              )),
                              const SizedBox(height: 16),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  ElevatedButton.icon(
                                    onPressed: _retryInitialization,
                                    icon: const Icon(Icons.refresh),
                                    label: const Text('Retry'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.orange,
                                      foregroundColor: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  TextButton(
                                    onPressed: _checkAuthenticationStatus,
                                    child: const Text(
                                      'Continue Anyway',
                                      style: TextStyle(color: Colors.white70),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}