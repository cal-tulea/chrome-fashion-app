import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Per-user daily AI call limiter.
///
/// Enforced locally via SharedPreferences (fast, offline-safe) and
/// synced to Firestore in the background so it can be enforced
/// server-side when Firebase Functions are deployed.
///
/// Limit: 50 AI calls/day per user.
class AIRateLimiter {
  AIRateLimiter._();

  static const int dailyLimit = 50;
  static const String _kCount = 'ai_call_count';
  static const String _kDate  = 'ai_call_date';
  static const String _kUid   = 'ai_call_uid';

  static String get _today =>
      DateTime.now().toIso8601String().substring(0, 10);

  /// Returns true if this call is allowed and increments the counter.
  /// Returns false if the daily limit has been reached.
  static Future<bool> checkAndIncrement() async {
    final prefs = await SharedPreferences.getInstance();
    final uid = FirebaseAuth.instance.currentUser?.uid ?? 'anon';

    final savedDate = prefs.getString(_kDate) ?? '';
    final savedUid  = prefs.getString(_kUid)  ?? '';

    // Reset counter if date changed or different user
    int count = (savedDate == _today && savedUid == uid)
        ? (prefs.getInt(_kCount) ?? 0)
        : 0;

    if (count >= dailyLimit) {
      debugPrint('[RateLimit] Daily limit reached ($count/$dailyLimit)');
      return false;
    }

    count++;
    await prefs.setString(_kDate, _today);
    await prefs.setString(_kUid, uid);
    await prefs.setInt(_kCount, count);

    debugPrint('[RateLimit] AI call $count/$dailyLimit');

    // Sync to Firestore silently (non-blocking)
    _syncToFirestore(uid, count);

    return true;
  }

  /// How many AI calls are left today.
  static Future<int> getRemainingCalls() async {
    final prefs = await SharedPreferences.getInstance();
    final uid = FirebaseAuth.instance.currentUser?.uid ?? 'anon';
    final savedDate = prefs.getString(_kDate) ?? '';
    final savedUid  = prefs.getString(_kUid)  ?? '';
    final count = (savedDate == _today && savedUid == uid)
        ? (prefs.getInt(_kCount) ?? 0)
        : 0;
    return (dailyLimit - count).clamp(0, dailyLimit);
  }

  static void _syncToFirestore(String uid, int count) async {
    if (uid == 'anon') return;
    try {
      await FirebaseFirestore.instance
          .doc('users/$uid/usage/aiCalls')
          .set({
            'count': count,
            'date': _today,
            'lastUsed': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
    } catch (_) {
      // Non-critical — local count is the source of truth
    }
  }
}
