import 'package:flutter/material.dart';
import '../models/user_role.dart';
import '../services/role_controller.dart';
import 'technician/technician_home.dart';
import 'engineer/engineer_home.dart';
import 'manager/manager_home.dart';
import 'auditor/auditor_home.dart';

/// Routes to a role-specific home screen.
///
/// CHANGE (role switching without logout): `role` is no longer a
/// constructor prop fetched once at login — it's read live from
/// RoleScope, so this widget rebuilds automatically (via the
/// InheritedNotifier dependency established by RoleScope.of) whenever
/// RoleSwitcher calls RoleController.setRole() anywhere in the tree.
/// No auth change, no navigation, no logout involved.
class HomeShell extends StatelessWidget {
  const HomeShell({super.key});

  @override
  Widget build(BuildContext context) {
    final role = RoleScope.of(context).role;

    switch (role) {
      case UserRole.technician:
        return const TechnicianHome();
      case UserRole.engineer:
        return const EngineerHome();
      case UserRole.manager:
        return const ManagerHome();
      case UserRole.auditor:
        return const AuditorHome();
    }
  }
}