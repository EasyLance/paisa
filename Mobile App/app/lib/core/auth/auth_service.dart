import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';

import '../api/api_client.dart';

/// Who is signed in, and the headers that prove it. One interface so the app,
/// the tests and the local-development path all go through the same door.
abstract class AuthService implements AuthSource {
  bool get isSignedIn;

  /// The signed-in address, used only to prefill a form.
  String? get currentEmail;

  /// Emits the current state first, then every change.
  Stream<bool> get signedInChanges;

  Future<void> signIn(String email, String password);
  Future<void> sendPasswordReset(String email);
  Future<void> signOut();
}

/// A failure the sign-in form can show, already worded for a person.
class AuthFailure implements Exception {
  const AuthFailure(this.message);
  final String message;

  @override
  String toString() => 'AuthFailure($message)';
}

const _notRecognised = 'That email and password combination is not recognised.';

// Same wording as the web's sign-in form (apps/web/app/sign-in.tsx).
const _messages = {
  'invalid-credential': _notRecognised,
  'wrong-password': _notRecognised,
  'user-not-found': _notRecognised,
  'invalid-email': 'Enter a valid email address.',
  'user-disabled': 'This account has been disabled. Ask the workspace owner to restore it.',
  'too-many-requests': 'Too many attempts. Wait a few minutes before trying again.',
  'network-request-failed': 'Cannot reach the authentication service. Check your connection.',
  'operation-not-allowed': 'Email sign-in is not enabled for this Firebase project.',
};

AuthFailure authFailureFromCode(String code) =>
    AuthFailure(_messages[code] ?? 'Sign-in failed. Verify your email and check your credentials.');

class FirebaseAuthService implements AuthService {
  FirebaseAuthService([FirebaseAuth? auth]) : _auth = auth ?? FirebaseAuth.instance;
  final FirebaseAuth _auth;

  @override
  bool get isSignedIn => _auth.currentUser != null;

  @override
  String? get currentEmail => _auth.currentUser?.email;

  @override
  Stream<bool> get signedInChanges => _auth.authStateChanges().map((user) => user != null);

  @override
  Future<Map<String, String>> headers({bool forceRefresh = false}) async {
    final token = await _auth.currentUser?.getIdToken(forceRefresh);
    return token == null ? const {} : {'authorization': 'Bearer $token'};
  }

  @override
  Future<void> signIn(String email, String password) async {
    try {
      await _auth.signInWithEmailAndPassword(email: email.trim(), password: password);
    } on FirebaseAuthException catch (error) {
      throw authFailureFromCode(error.code);
    }
  }

  @override
  Future<void> sendPasswordReset(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
    } on FirebaseAuthException catch (error) {
      throw authFailureFromCode(error.code);
    }
  }

  @override
  Future<void> signOut() => _auth.signOut();
}

/// Local development only (`AppConfig.devAuth`, which a release build cannot
/// turn on). Starts signed in as the default dev user. The "email" typed into the
/// sign-in form is taken as a dev user id, so `user_spouse` or `user_ca` can be
/// tried without a Firebase account.
class DevAuthService implements AuthService {
  DevAuthService(String userId) : _userId = userId, _signedIn = true;

  String _userId;
  bool _signedIn;
  final _changes = StreamController<bool>.broadcast();

  @override
  bool get isSignedIn => _signedIn;

  @override
  String? get currentEmail => null;

  @override
  Stream<bool> get signedInChanges async* {
    yield _signedIn;
    yield* _changes.stream;
  }

  @override
  Future<Map<String, String>> headers({bool forceRefresh = false}) async => _signedIn ? {'x-dev-user-id': _userId} : const {};

  @override
  Future<void> signIn(String email, String password) async {
    _userId = email.trim();
    _signedIn = true;
    _changes.add(true);
  }

  @override
  Future<void> sendPasswordReset(String email) async {}

  @override
  Future<void> signOut() async {
    _signedIn = false;
    _changes.add(false);
  }
}
