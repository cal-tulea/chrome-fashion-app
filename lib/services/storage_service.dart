import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

/// Handles Firebase Storage uploads for closet images.
///
/// Images are stored at: users/{uid}/closet/{itemId}.jpg
/// This backs up local closet images to the cloud so they survive
/// device changes or reinstalls.
///
/// Setup required:
///   Firebase console → Storage → Get started → Choose region → Start in production mode
///   Then paste the rules from storage.rules into Firebase console → Storage → Rules
class StorageService {
  StorageService._();

  static final _storage = FirebaseStorage.instance;
  static String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  /// Uploads a clothing image to Firebase Storage.
  /// Returns the public download URL, or null on failure.
  static Future<String?> uploadClosetImage(File imageFile, String itemId) async {
    final uid = _uid;
    if (uid == null) {
      debugPrint('[Storage] No user signed in — skipping upload');
      return null;
    }

    try {
      final ref = _storage.ref('users/$uid/closet/$itemId.jpg');

      await ref.putFile(
        imageFile,
        SettableMetadata(
          contentType: 'image/jpeg',
          customMetadata: {
            'uploadedAt': DateTime.now().toIso8601String(),
            'itemId': itemId,
          },
        ),
      );

      final url = await ref.getDownloadURL();
      debugPrint('[Storage] Uploaded $itemId → $url');
      return url;
    } catch (e) {
      debugPrint('[Storage] Upload failed for $itemId: $e');
      return null; // Non-fatal — local image still works
    }
  }

  /// Deletes a clothing image from cloud storage.
  /// Silently ignores errors (file may already be deleted).
  static Future<void> deleteClosetImage(String itemId) async {
    final uid = _uid;
    if (uid == null) return;

    try {
      await _storage.ref('users/$uid/closet/$itemId.jpg').delete();
      debugPrint('[Storage] Deleted $itemId');
    } catch (_) {
      // File may not exist in cloud — this is fine
    }
  }

  /// Downloads all closet image URLs for the current user.
  /// Used for cross-device sync.
  static Future<Map<String, String>> getAllClosetImageUrls() async {
    final uid = _uid;
    if (uid == null) return {};

    try {
      final result = await _storage.ref('users/$uid/closet').listAll();
      final urls = <String, String>{};

      await Future.wait(result.items.map((ref) async {
        final itemId = ref.name.replaceAll('.jpg', '');
        try {
          urls[itemId] = await ref.getDownloadURL();
        } catch (_) {}
      }));

      return urls;
    } catch (e) {
      debugPrint('[Storage] Failed to list closet images: $e');
      return {};
    }
  }
}
