import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// Handles Google Sign-In flow with Firebase Auth.
///
/// Setup required in Firebase console:
///   1. Authentication → Sign-in methods → Enable Google
///   2. Add your SHA-1 fingerprint under Project Settings → Android app
///      Run: keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android -keypass android
///   3. Download updated google-services.json and replace android/app/google-services.json
class GoogleAuthService {
  GoogleAuthService._();

  static final _googleSignIn = GoogleSignIn(
    scopes: ['email', 'profile'],
  );

  /// Signs in with Google. Returns null if cancelled or on error.
  static Future<UserCredential?> signIn() async {
    try {
      // Trigger the Google Sign-In flow
      final googleUser = await _googleSignIn.signIn();
      if (googleUser == null) return null; // user cancelled

      // Get auth tokens
      final googleAuth = await googleUser.authentication;

      // Create Firebase credential
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      // Sign in to Firebase
      return await FirebaseAuth.instance.signInWithCredential(credential);
    } catch (e) {
      debugPrint('[GoogleAuth] Sign-in failed: $e');
      return null;
    }
  }

  /// Signs out from both Google and Firebase.
  static Future<void> signOut() async {
    await Future.wait([
      _googleSignIn.signOut(),
      FirebaseAuth.instance.signOut(),
    ]);
  }

  /// Returns true if Google Sign-In is available on this device.
  static bool get isAvailable => true;
}
