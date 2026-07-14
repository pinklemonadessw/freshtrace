import 'package:firebase_auth/firebase_auth.dart';

class AuthService {
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  static User? get currentUser => _auth.currentUser;

  static Stream<User?> get authStateChanges => _auth.authStateChanges();

  /// Like [authStateChanges], but also emits after profile updates and
  /// [User.reload] — needed so the app reacts when the email gets verified.
  static Stream<User?> get userChanges => _auth.userChanges();

  static Future<void> signIn(String email, String password) async {
    await _auth.signInWithEmailAndPassword(email: email, password: password);
  }

  static Future<void> register(String email, String password) async {
    final credential = await _auth.createUserWithEmailAndPassword(
        email: email, password: password);
    await credential.user?.sendEmailVerification();
  }

  static Future<void> resendVerificationEmail() async {
    await _auth.currentUser?.sendEmailVerification();
  }

  /// Reloads the current user and returns true once their email is verified.
  /// Forces an ID token refresh on success so Firestore security rules see
  /// the updated email_verified claim immediately.
  static Future<bool> refreshEmailVerifiedStatus() async {
    final user = _auth.currentUser;
    if (user == null) return false;
    await user.reload();
    final refreshed = _auth.currentUser;
    if (refreshed != null && refreshed.emailVerified) {
      await refreshed.getIdToken(true);
      return true;
    }
    return false;
  }

  static Future<void> sendPasswordReset(String email) async {
    await _auth.sendPasswordResetEmail(email: email);
  }

  static Future<void> signOut() async {
    await _auth.signOut();
  }
}
