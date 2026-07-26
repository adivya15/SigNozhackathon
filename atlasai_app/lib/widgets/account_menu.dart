import 'package:flutter/material.dart';
import '../models/user_role.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';

/// Role badge + sign-out menu shown in the chat screen's AppBar.
/// Signing out doesn't navigate anywhere itself — AuthGate listens to
/// authStateChanges and routes back to LoginScreen automatically, same
/// pattern LoginScreen already relies on for sign-in.
class AccountMenu extends StatelessWidget {
  final UserRole role;
  const AccountMenu({super.key, required this.role});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Account',
      onSelected: (value) {
        if (value == 'sign_out') {
          AuthService().signOut();
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem<String>(
          enabled: false,
          child: Text(
            'Signed in as ${role.label}',
            style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem<String>(
          value: 'sign_out',
          child: Row(
            children: [
              Icon(Icons.logout, size: 18, color: AppColors.danger),
              SizedBox(width: 8),
              Text('Sign out'),
            ],
          ),
        ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.surfaceMuted,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.person_outline, size: 16, color: AppColors.primary),
            const SizedBox(width: 6),
            Text(role.label, style: const TextStyle(fontSize: 12.5, color: AppColors.textPrimary)),
          ],
        ),
      ),
    );
  }
}