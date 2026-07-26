import 'package:flutter/material.dart';
import '../models/user_role.dart';
import '../services/role_controller.dart';
import '../theme/app_theme.dart';

/// Lets the signed-in user switch which role's screen is shown,
/// without signing out. Visually mirrors AccountMenu/RoleBadge's
/// pill-in-AppBar convention so it sits naturally alongside them.
class RoleSwitcher extends StatelessWidget {
  const RoleSwitcher({super.key});

  @override
  Widget build(BuildContext context) {
    // Establishes the InheritedNotifier dependency — this widget
    // rebuilds automatically whenever RoleController.setRole() fires,
    // no separate AnimatedBuilder/setState needed.
    final controller = RoleScope.of(context);
    final current = controller.role;

    return PopupMenuButton<UserRole>(
      tooltip: 'Switch role',
      onSelected: (role) => controller.setRole(role),
      itemBuilder: (context) => UserRole.values.map((role) {
        final selected = role == current;
        return PopupMenuItem<UserRole>(
          value: role,
          child: Row(
            children: [
              Icon(
                selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                size: 18,
                color: selected ? AppColors.primary : AppColors.textSecondary,
              ),
              const SizedBox(width: 10),
              Text(role.label),
            ],
          ),
        );
      }).toList(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.surfaceMuted,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.swap_horiz, size: 16, color: AppColors.primary),
            const SizedBox(width: 6),
            Text(
              current.label,
              style: const TextStyle(fontSize: 12.5, color: AppColors.textPrimary, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}