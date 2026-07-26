import 'package:flutter/material.dart';
import '../models/user_role.dart';

/// Holds the app's currently-active role for the signed-in session.
/// This is a UI convenience toggle, not a permissions system — any
/// signed-in user can switch to any of the 4 roles at will (product
/// decision, confirmed). Every screen's own API calls keep reading
/// role from wherever they already did (a hardcoded literal per role
/// screen, e.g. ChatScreen(userRole: 'technician')) — that stays
/// correct because HomeShell only ever mounts the screen matching the
/// current role, so a screen's hardcoded literal always matches
/// reality for as long as that screen exists on screen.
class RoleController extends ChangeNotifier {
  RoleController(this._role);

  UserRole _role;
  UserRole get role => _role;

  void setRole(UserRole newRole) {
    if (newRole == _role) return;
    _role = newRole;
    notifyListeners();
  }
}

/// InheritedNotifier wrapper so any descendant can read the current
/// role (`RoleScope.of(context).role`) and rebuild automatically when
/// it changes, or call `RoleScope.of(context).setRole(...)` to switch
/// roles from anywhere in the tree — e.g. RoleSwitcher's AppBar button
/// — without threading a callback down manually.
class RoleScope extends InheritedNotifier<RoleController> {
  const RoleScope({
    super.key,
    required RoleController controller,
    required super.child,
  }) : super(notifier: controller);

  static RoleController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<RoleScope>();
    assert(
      scope != null,
      'RoleScope.of() called with no RoleScope ancestor — '
      'make sure AuthGate wraps HomeShell in a RoleScope.',
    );
    return scope!.notifier!;
  }
}