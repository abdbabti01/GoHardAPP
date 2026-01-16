import 'package:flutter/material.dart';

/// Reusable loading indicator widget
/// Provides consistent loading UI across the app
class LoadingIndicator extends StatelessWidget {
  final String? message;
  final double size;

  const LoadingIndicator({super.key, this.message, this.size = 40});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: size,
            height: size,
            child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(
                theme.colorScheme.primary, // Green loading indicator
              ),
            ),
          ),
          if (message != null) ...[
            const SizedBox(height: 16),
            Text(
              message!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: const Color(0xFF8E8E93), // Medium grey for loading text
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}
