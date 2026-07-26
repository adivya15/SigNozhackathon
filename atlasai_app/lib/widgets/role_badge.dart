import 'package:flutter/material.dart';
import '../models/user_role.dart';

class RoleBadge extends StatelessWidget {
  final UserRole role;
  const RoleBadge({super.key, required this.role});

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text(role.label),
      backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
    );
  }
}
