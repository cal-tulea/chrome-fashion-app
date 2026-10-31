import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/outfit.dart';
import '../models/clothing_item.dart';

class OutfitService {
  static final OutfitService _instance = OutfitService._internal();
  factory OutfitService() => _instance;
  OutfitService._internal();

  final List<Map<String, dynamic>> _saved = [];

  /// Returns raw saved outfits (ids), for later UI if you want.
  List<Map<String, dynamic>> get saved => _saved;

  Future<void> saveOutfit(Outfit outfit) async {
    final json = {
      'topId': outfit.top.id,
      'bottomId': outfit.bottom.id,
      'shoesId': outfit.shoes?.id,
      'outerwearId': outfit.outerwear?.id,
      'score': outfit.score,
      'reasons': outfit.reasons,
      'createdAt': DateTime.now().toIso8601String(),
    };

    _saved.add(json);
    await _persist();
  }

  Future<void> load() async {
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/outfits.json');
    if (!await file.exists()) return;

    final data = jsonDecode(await file.readAsString()) as List;
    _saved
      ..clear()
      ..addAll(data.cast<Map<String, dynamic>>());
  }

  Future<void> removeOutfitsContaining(String itemId) async {
    _saved.removeWhere((json) =>
      json['topId'] == itemId ||
      json['bottomId'] == itemId ||
      json['shoesId'] == itemId ||
      json['outerwearId'] == itemId);
    await _persist();
  }

  Future<void> removeOutfitByItems(Outfit outfit) async {
    _saved.removeWhere((json) =>
      json['topId'] == outfit.top.id &&
      json['bottomId'] == outfit.bottom.id &&
      json['shoesId'] == outfit.shoes?.id &&
      json['outerwearId'] == outfit.outerwear?.id);
    await _persist();
  }

  Future<void> clearAll() async {
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/outfits.json');
    _saved.clear();
    if (await file.exists()) await file.delete();
  }

  Future<void> _persist() async {
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/outfits.json');
    await file.writeAsString(jsonEncode(_saved));
  }

  /// Helper: resolve a saved outfit into actual ClothingItem objects.
  /// Returns null if any item is missing.
  Outfit? resolveOutfit(Map<String, dynamic> json, List<ClothingItem> closet) {
    ClothingItem? findById(String? id) {
      if (id == null) return null;
      try {
        return closet.firstWhere((i) => i.id == id);
      } catch (_) {
        return null;
      }
    }

    final top = findById(json['topId']);
    final bottom = findById(json['bottomId']);
    final shoes = findById(json['shoesId']);
    final outer = findById(json['outerwearId']);

    if (top == null || bottom == null) return null;

    return Outfit(
      top: top,
      bottom: bottom,
      shoes: shoes,
      outerwear: outer,
      score: (json['score'] ?? 0) as int,
      reasons: List<String>.from(json['reasons'] ?? const []),
    );
  }
}
