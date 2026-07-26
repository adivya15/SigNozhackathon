import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

enum StatusPillState { loading, success, error }

/// Small inline status indicator — replaces the plain Text rows the
/// old inline _StatusCard used in Day 1's main.dart. Shows a spinner +
/// loadingText while pending, then a colored dot + label once resolved.
class StatusPill extends StatelessWidget {
  final StatusPillState state;
  final String loadingText;
  final String successText;
  final String errorText;

  const StatusPill({
    super.key,
    required this.state,
    required this.loadingText,
    required this.successText,
    required this.errorText,
  });

  @override
  Widget build(BuildContext context) {
    final (Color dotColor, Color bgColor, String label) = switch (state) {
      StatusPillState.loading => (AppColors.textFaint, AppColors.surfaceMuted, loadingText),
      StatusPillState.success => (AppColors.success, AppColors.successBg, successText),
      StatusPillState.error => (AppColors.danger, AppColors.dangerBg, errorText),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (state == StatusPillState.loading)
            const SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
            ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}