import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class UserProfile {
  final String uid;
  final String email;
  final String? colorSeason;
  final Map<String, dynamic> stylePreferences;
  final DateTime createdAt;

  const UserProfile({
    required this.uid,
    required this.email,
    this.colorSeason,
    required this.stylePreferences,
    required this.createdAt,
  });

  factory UserProfile.fromMap(String uid, Map<String, dynamic> data) {
    return UserProfile(
      uid: uid,
      email: data['email'] as String? ?? '',
      colorSeason: data['colorSeason'] as String?,
      stylePreferences: Map<String, dynamic>.from(data['stylePreferences'] as Map? ?? {}),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() => {
    'email': email,
    'colorSeason': colorSeason,
    'stylePreferences': stylePreferences,
    'createdAt': Timestamp.fromDate(createdAt),
  };
}

class UserProfileService {
  UserProfileService._();
  static final UserProfileService instance = UserProfileService._();

  final _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _col => _db.collection('users');

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  /// Creates a profile document for a newly signed-up user if one doesn't exist.
  Future<void> ensureProfile() async {
    final uid = _uid;
    if (uid == null) return;

    final doc = await _col.doc(uid).get();
    if (!doc.exists) {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return; // signed out mid-flight — nothing to do

      await _col.doc(uid).set(
        UserProfile(
          uid: uid,
          email: user.email ?? '',
          stylePreferences: const {},
          createdAt: DateTime.now(),
        ).toMap(),
      );
    }
  }

  Future<UserProfile?> getProfile() async {
    final uid = _uid;
    if (uid == null) return null;

    final doc = await _col.doc(uid).get();
    if (!doc.exists) return null;
    final data = doc.data();
    if (data == null) return null;
    return UserProfile.fromMap(uid, data);
  }

  Future<void> updateColorSeason(String season) async {
    final uid = _uid;
    if (uid == null) return;
    await _col.doc(uid).update({'colorSeason': season});
  }

  Future<void> updateStylePreferences(Map<String, dynamic> prefs) async {
    final uid = _uid;
    if (uid == null) return;
    await _col.doc(uid).update({'stylePreferences': prefs});
  }
}
