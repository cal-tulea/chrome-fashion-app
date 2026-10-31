import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/outfit.dart';

class PreferenceService {
  static final PreferenceService _instance = PreferenceService._internal();
  factory PreferenceService() => _instance;
  PreferenceService._internal();

  static const _kLikedOutfits = 'liked_outfits_v1';
  static const _kDislikedOutfits = 'disliked_outfits_v1';
  static const _kItemLikes = 'item_likes_v1';
  static const _kRecentItems = 'recent_item_ids_v1';

  String signatureForOutfit(Outfit o) {
    final ids = o.items.map((i) => i.id).toList()..sort();
    return ids.join('|');
  }

  Future<Set<String>> getLikedOutfits() async {
    final sp = await SharedPreferences.getInstance();
    return (sp.getStringList(_kLikedOutfits) ?? const []).toSet();
  }

  Future<Set<String>> getDislikedOutfits() async {
    final sp = await SharedPreferences.getInstance();
    return (sp.getStringList(_kDislikedOutfits) ?? const []).toSet();
  }

  Future<Map<String, int>> getItemLikeWeights() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_kItemLikes);
    if (raw == null || raw.isEmpty) return {};
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    return decoded.map((k, v) => MapEntry(k, (v as num).toInt()));
  }

  Future<void> likeOutfit(Outfit o) async {
    final sp = await SharedPreferences.getInstance();
    final sig = signatureForOutfit(o);

    final liked = (sp.getStringList(_kLikedOutfits) ?? const []).toSet();
    final disliked = (sp.getStringList(_kDislikedOutfits) ?? const []).toSet();

    liked.add(sig);
    disliked.remove(sig);

    final weights = await getItemLikeWeights();
    for (final item in o.items) {
      weights[item.id] = (weights[item.id] ?? 0) + 1;
    }

    await sp.setStringList(_kLikedOutfits, liked.toList());
    await sp.setStringList(_kDislikedOutfits, disliked.toList());
    await sp.setString(_kItemLikes, jsonEncode(weights));
  }

  Future<void> dislikeOutfit(Outfit o) async {
    final sp = await SharedPreferences.getInstance();
    final sig = signatureForOutfit(o);

    final liked = (sp.getStringList(_kLikedOutfits) ?? const []).toSet();
    final disliked = (sp.getStringList(_kDislikedOutfits) ?? const []).toSet();

    disliked.add(sig);
    liked.remove(sig);

    final weights = await getItemLikeWeights();
    for (final item in o.items) {
      final cur = (weights[item.id] ?? 0);
      weights[item.id] = cur <= 0 ? 0 : cur - 1;
    }

    await sp.setStringList(_kLikedOutfits, liked.toList());
    await sp.setStringList(_kDislikedOutfits, disliked.toList());
    await sp.setString(_kItemLikes, jsonEncode(weights));
  }

  Future<List<String>> getRecentItemIds() async {
    final sp = await SharedPreferences.getInstance();
    return sp.getStringList(_kRecentItems) ?? const [];
  }

  Future<void> markOutfitsShown(List<Outfit> outfits, {int maxRecent = 30}) async {
    final sp = await SharedPreferences.getInstance();
    final existing = (sp.getStringList(_kRecentItems) ?? const []).toList();

    final newIds = outfits.expand((o) => o.items.map((i) => i.id)).toList();
    existing.insertAll(0, newIds);

    final seen = <String>{};
    final deduped = <String>[];
    for (final id in existing) {
      if (seen.add(id)) deduped.add(id);
      if (deduped.length >= maxRecent) break;
    }

    await sp.setStringList(_kRecentItems, deduped);
  }

  Future<void> clearAll() async {
    final sp = await SharedPreferences.getInstance();
    await sp.remove(_kLikedOutfits);
    await sp.remove(_kDislikedOutfits);
    await sp.remove(_kItemLikes);
    await sp.remove(_kRecentItems);
  }
}
