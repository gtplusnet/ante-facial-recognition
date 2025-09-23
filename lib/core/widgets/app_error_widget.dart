import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:lottie/lottie.dart';

import '../error/failures.dart';

class AppErrorWidget extends StatelessWidget {
  final Failure? failure;
  final String? message;
  final VoidCallback? onRetry;
  final IconData? icon;
  final String? lottieAsset;

  const AppErrorWidget({
    super.key,
    this.failure,
    this.message,
    this.onRetry,
    this.icon,
    this.lottieAsset,
  });

  String get errorMessage {
    if (message != null) return message!;
    if (failure != null) return failure!.message;
    return 'An error occurred. Please try again.';
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(24.w),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (lottieAsset != null)
              Lottie.asset(
                lottieAsset!,
                width: 200.w,
                height: 200.h,
                repeat: false,
              )
            else
              Icon(
                icon ?? Icons.error_outline,
                size: 80.w,
                color: Theme.of(context).colorScheme.error,
              ),
            SizedBox(height: 24.h),
            Text(
              'Oops!',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            SizedBox(height: 12.h),
            Text(
              errorMessage,
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            if (failure?.code != null) ...[
              SizedBox(height: 8.h),
              Text(
                'Error Code: ${failure!.code}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
            if (onRetry != null) ...[
              SizedBox(height: 24.h),
              ElevatedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Try Again'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class AppErrorSnackbar extends SnackBar {
  AppErrorSnackbar({
    super.key,
    required BuildContext context,
    required String message,
    String? actionLabel,
    VoidCallback? onAction,
  }) : super(
          content: Row(
            children: [
              Icon(
                Icons.error_outline,
                color: Theme.of(context).colorScheme.onError,
                size: 20.w,
              ),
              SizedBox(width: 12.w),
              Expanded(
                child: Text(
                  message,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onError,
                  ),
                ),
              ),
            ],
          ),
          backgroundColor: Theme.of(context).colorScheme.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8.r),
          ),
          action: actionLabel != null && onAction != null
              ? SnackBarAction(
                  label: actionLabel,
                  onPressed: onAction,
                  textColor: Theme.of(context).colorScheme.onError,
                )
              : null,
        );
}

class AppEmptyState extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData? icon;
  final String? lottieAsset;
  final Widget? action;

  const AppEmptyState({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.lottieAsset,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(24.w),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (lottieAsset != null)
              Lottie.asset(
                lottieAsset!,
                width: 200.w,
                height: 200.h,
              )
            else
              Icon(
                icon ?? Icons.inbox_outlined,
                size: 80.w,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            SizedBox(height: 24.h),
            Text(
              title,
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            if (subtitle != null) ...[
              SizedBox(height: 12.h),
              Text(
                subtitle!,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                textAlign: TextAlign.center,
              ),
            ],
            if (action != null) ...[
              SizedBox(height: 24.h),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}