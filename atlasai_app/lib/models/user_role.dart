enum UserRole { technician, engineer, manager, auditor }

extension UserRoleX on UserRole {
  String get label {
    switch (this) {
      case UserRole.technician:
        return 'Technician';
      case UserRole.engineer:
        return 'Maintenance Engineer';
      case UserRole.manager:
        return 'Plant Manager';
      case UserRole.auditor:
        return 'Auditor';
    }
  }

  static UserRole fromString(String value) {
    return UserRole.values.firstWhere(
      (r) => r.name == value,
      orElse: () => UserRole.technician,
    );
  }
}
