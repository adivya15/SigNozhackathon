import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/user_role.dart';
import '../services/auth_service.dart';
import '../services/role_controller.dart';
import 'auth/login_screen.dart';
import 'home_shell.dart';

/// Listens to Firebase Auth state and routes to the right screen.
/// This is the real app entry point (main.dart points `home:` at
/// this widget).
///
///   no session          -> LoginScreen
///   session, has role    -> HomeShell wrapped in RoleScope
///   session, no role doc -> back to LoginScreen (interrupted signup —
///                           see AuthService.fetchUserRole)
///
/// CHANGE (role switching without logout): fetchUserRole(uid) now only
/// runs ONCE per sign-in — its result seeds a RoleController that's
/// created once and reused across rebuilds for the same uid, rather
/// than being re-fetched (and silently discarding any in-app role
/// switch) every time this widget rebuilds. HomeShell no longer takes
/// a `role` param; it reads the live role from RoleScope instead, so
/// switching roles (via RoleSwitcher, anywhere in the tree) rebuilds
/// HomeShell in place without touching auth at all.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final _authService = AuthService();

  RoleController? _roleController;
  String? _roleControllerForUid;

  @override
  void dispose() {
    _roleController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: _authService.authStateChanges,
      builder: (context, authSnapshot) {
        if (authSnapshot.connectionState == ConnectionState.waiting) {
          return const _LoadingScreen();
        }

        final user = authSnapshot.data;
        if (user == null) {
          // Signed out: drop any existing controller so a different
          // account signing in next doesn't inherit a stale role
          // selection from whoever used the app before them.
          _roleController?.dispose();
          _roleController = null;
          _roleControllerForUid = null;
          return const LoginScreen();
        }

        // Already have a live controller for this exact user — reuse
        // it across rebuilds instead of re-fetching/re-creating. This
        // is what lets an in-app role switch persist through any
        // rebuild of AuthGate (parent rebuilds, hot reload, etc.)
        // instead of being silently reset back to the Firestore value
        // every time.
        if (_roleController != null && _roleControllerForUid == user.uid) {
          return RoleScope(
            controller: _roleController!,
            child: const HomeShell(),
          );
        }

        return FutureBuilder<UserRole>(
          future: _authService.fetchUserRole(user.uid),
          builder: (context, roleSnapshot) {
            if (roleSnapshot.connectionState == ConnectionState.waiting) {
              return const _LoadingScreen();
            }
            if (roleSnapshot.hasError) {
              // Profile doc missing (interrupted signup) — sign out
              // and send back to login rather than get stuck on a
              // spinner.
              _authService.signOut();
              return const LoginScreen();
            }

            _roleController = RoleController(roleSnapshot.data!);
            _roleControllerForUid = user.uid;

            return RoleScope(
              controller: _roleController!,
              child: const HomeShell(),
            );
          },
        );
      },
    );
  }
}

class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}