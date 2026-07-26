import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/user_role.dart';
import 'firestore_service.dart';

/// Day 4: real sign-up/login + role assignment, backed by Firestore
/// per SCHEMA.md's users/{uid} contract:
///   { email, role, displayName, createdAt }
class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirestoreService _firestore = FirestoreService();

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  User? get currentUser => _auth.currentUser;

  Future<UserCredential> signInWithEmail(String email, String password) {
    return _auth.signInWithEmailAndPassword(email: email, password: password);
  }

  Future<UserCredential> signUpWithEmail(
    String email,
    String password,
    UserRole role, {
    String displayName = '',
  }) async {
    final cred = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );

    await _firestore.users.doc(cred.user!.uid).set({
      'email': email,
      'role': role.name,
      'displayName': displayName,
      'createdAt': FieldValue.serverTimestamp(),
    });

    return cred;
  }

  /// Fetches the users/{uid} doc written at signup. Used after login
  /// (and on app relaunch, when Firebase Auth already has a session)
  /// to know which role-specific home screen to route to.
  ///
  /// Throws StateError if no profile exists yet — this can happen if
  /// signup was interrupted between the Auth account being created and
  /// the Firestore write completing. Callers should catch this and
  /// send the user back to login/signup rather than crash.
  Future<UserRole> fetchUserRole(String uid) async {
    final doc = await _firestore.users.doc(uid).get();
    final data = doc.data() as Map<String, dynamic>?;
    if (data == null || data['role'] == null) {
      throw StateError(
        'No profile found for uid=$uid. Sign-up may have been '
        'interrupted before the Firestore write completed.',
      );
    }
    return UserRoleX.fromString(data['role'] as String);
  }

  Future<void> signOut() => _auth.signOut();
}