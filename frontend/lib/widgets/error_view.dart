/// Shared error/empty-state views with retry actions.
///
/// [ErrorView] distinguishes network failures ("Retry" button, offline icon)
/// from other API errors so the UI can be honest about what went wrong.
library;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;
  final bool isNetworkError;
  final String semanticsLabel;

  const ErrorView({
    super.key,
    required this.message,
    this.onRetry,
    this.isNetworkError = false,
    this.semanticsLabel = 'Error',
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$semanticsLabel: $message',
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isNetworkError ? Icons.cloud_off_outlined : Icons.error_outline,
                size: 56,
                color: AppColors.inkFaint,
                semanticLabel: isNetworkError ? 'Offline' : 'Error',
              ),
              const SizedBox(height: 16),
              Text(
                isNetworkError
                    ? 'Couldn\'t reach the server'
                    : 'Something went wrong',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: AppColors.ink,
                      fontWeight: FontWeight.w700,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                message,
                style: const TextStyle(color: AppColors.inkSoft, height: 1.4),
                textAlign: TextAlign.center,
              ),
              if (onRetry != null) ...[
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class EmptyView extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final String semanticsLabel;

  const EmptyView({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.semanticsLabel = 'Empty',
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$semanticsLabel: $title',
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 56, color: AppColors.inkFaint),
              const SizedBox(height: 16),
              Text(
                title,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: AppColors.ink,
                      fontWeight: FontWeight.w700,
                    ),
                textAlign: TextAlign.center,
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 8),
                Text(
                  subtitle!,
                  style:
                      const TextStyle(color: AppColors.inkSoft, height: 1.4),
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
