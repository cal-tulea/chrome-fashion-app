import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';

/// Thin wrapper around Firebase Analytics.
/// All events are no-ops in debug mode so dev usage doesn't pollute analytics.
class AnalyticsService {
  AnalyticsService._();

  static final _analytics = FirebaseAnalytics.instance;

  static Future<void> _log(String name, [Map<String, Object>? params]) async {
    if (kDebugMode) return; // don't track dev sessions
    try {
      await _analytics.logEvent(name: name, parameters: params);
    } catch (_) {
      // Never crash the app due to analytics
    }
  }

  // ── Closet events ──────────────────────────────────────────────────────────

  static Future<void> logAddItem(String category) =>
      _log('add_item', {'category': category});

  static Future<void> logDeleteItem() => _log('delete_item');

  static Future<void> logEditItem() => _log('edit_item');

  // ── Outfit events ──────────────────────────────────────────────────────────

  static Future<void> logGenerateOutfit({
    String occasion = 'Any',
    String weather = 'Any',
  }) =>
      _log('generate_outfit', {'occasion': occasion, 'weather': weather});

  static Future<void> logSaveOutfit() => _log('save_outfit');

  static Future<void> logSwipeOutfit(bool liked) =>
      _log('swipe_outfit', {'liked': liked ? 'yes' : 'no'});

  // ── Auth events ────────────────────────────────────────────────────────────

  static Future<void> logLogin(String method) async {
    if (kDebugMode) return;
    try {
      await _analytics.logLogin(loginMethod: method);
    } catch (_) {}
  }

  static Future<void> logSignUp(String method) async {
    if (kDebugMode) return;
    try {
      await _analytics.logSignUp(signUpMethod: method);
    } catch (_) {}
  }

  // ── Screen tracking ────────────────────────────────────────────────────────

  static Future<void> logScreen(String screenName) async {
    if (kDebugMode) return;
    try {
      await _analytics.logScreenView(screenName: screenName);
    } catch (_) {}
  }
}
