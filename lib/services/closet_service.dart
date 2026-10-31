import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../core/config.dart';
import '../models/clothing_analysis.dart';
import '../models/clothing_analysis_result.dart';
import '../models/clothing_item.dart';
import 'clothing_item_analyzer.dart';
import 'gemini_vision_service.dart';
import 'huggingface_service.dart';
import 'local_analysis_service.dart';
import 'outfit_service.dart';
import 'storage_service.dart';
import '../services/fashion_analysis_mapper.dart';

class ClosetService extends ChangeNotifier {
  static final ClosetService _instance = ClosetService._internal();
  factory ClosetService() => _instance;
  ClosetService._internal();

  final List<ClothingItem> _items = [];

  // Newest first — most recently added item is at index 0.
  List<ClothingItem> get items => _items.reversed.toList();

  Future<void> addItem(File image, {ClothingCategory? categoryHint}) async {
    final directory = await getApplicationDocumentsDirectory();
    final id = DateTime.now().millisecondsSinceEpoch.toString();

    // Keep original extension if it's a png from cleanup; otherwise jpg
    final ext = image.path.toLowerCase().endsWith('.png') ? 'png' : 'jpg';
    final imagePath = '${directory.path}/$id.$ext';
    final savedImage = await image.copy(imagePath);

    // ── Add a placeholder immediately so the UI updates at once ──────────────
    _items.add(ClothingItem(
      id: id,
      imagePath: savedImage.path,
      category: categoryHint ?? ClothingCategory.tops,
      title: 'Analysing…',
      notes: '',
      analysis: LocalAnalysisService.analyze(categoryHint ?? ClothingCategory.tops),
      overrides: const {},
    ));
    notifyListeners();
    await save();

    // ── Run AI analysis in the background; update when done ──────────────────
    unawaited(_analyzeItem(id, savedImage, categoryHint));
  }

  Future<void> _analyzeItem(
    String id,
    File savedImage,
    ClothingCategory? categoryHint,
  ) async {
    ClothingAnalysis analysis = LocalAnalysisService.analyze(
      categoryHint ?? ClothingCategory.tops,
    );
    ClothingCategory finalCategory = categoryHint ?? ClothingCategory.tops;
    String title = 'New ${finalCategory.name}';

    try {
      bool aiSucceeded = false;

      // ── 1. Gemini (primary) ───────────────────────────────────────────────
      if (AppConfig.hasGeminiKey) {
        try {
          GeminiVisionService.apiKey = AppConfig.geminiApiKey;
          final geminiResult = await GeminiVisionService.analyseClothing(
            savedImage, hint: categoryHint,
          );
          if (geminiResult != null) {
            title = geminiResult.title;
            finalCategory = geminiResult.category;
            analysis = _analysisFromGemini(geminiResult);
            aiSucceeded = true;
            debugPrint('[Closet] Gemini succeeded → "$title"');
          }
        } catch (e) {
          debugPrint('[Closet] Gemini threw: $e');
        }
      }

      // ── 2. HuggingFace (fallback) ─────────────────────────────────────────
      if (!aiSucceeded) {
        try {
          final hfResult = await HuggingFaceService()
              .analyzeClothing(savedImage, hint: categoryHint);
          if (hfResult != null) {
            analysis = hfResult.toAnalysis();
            finalCategory = hfResult.category;
            title = hfResult.title;
            aiSucceeded = true;
            debugPrint('[Closet] HF succeeded → "$title"');
          }
        } catch (e) {
          debugPrint('[Closet] HF threw: $e');
        }
      }

      // ── 3. ML Kit (last resort — offline) ────────────────────────────────
      if (!aiSucceeded) {
        final analyzer = ClothingItemAnalyzer();
        final ClothingAnalysisResult result =
            await analyzer.analyze(savedImage, categoryHint: categoryHint);
        debugPrint('[MLKit] colors=${result.colors} strongTags=${result.strongTags} category=${result.inferredCategory}');
        analysis = FashionAnalysisMapper.map(result);
        finalCategory = result.inferredCategory;
        title = FashionAnalysisMapper.generateTitle(
          category: finalCategory,
          colors: result.colors,
          strongTags: result.strongTags,
        );
        debugPrint('[MLKit] title="$title"');
      }
    } catch (_) {
      finalCategory = categoryHint ?? ClothingCategory.tops;
      title = 'New ${finalCategory.name}';
    }

    // Update the placeholder in-place
    final idx = _items.indexWhere((i) => i.id == id);
    if (idx == -1) return; // deleted while analysing
    _items[idx] = _items[idx].copyWith(
      category: finalCategory,
      title: title,
      analysis: analysis,
    );
    notifyListeners();
    await save();

    // Back up image to Firebase Storage (non-blocking, non-fatal)
    unawaited(StorageService.uploadClosetImage(savedImage, id));
  }

  List<ClothingItem> byCategory(ClothingCategory category) {
    final list = category == ClothingCategory.all
        ? _items
        : _items.where((i) => i.category == category).toList();
    return list.reversed.toList(); // newest first
  }

  ClothingItem? getById(String id) {
    try {
      return _items.firstWhere((i) => i.id == id);
    } catch (_) {
      return null;
    }
  }

  Future<void> save() async {
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/closet.json');
    final jsonData = _items.map((e) => e.toJson()).toList();
    await file.writeAsString(jsonEncode(jsonData));
    notifyListeners();
  }

  Future<void> load() async {
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/closet.json');
    if (!await file.exists()) return;

    final data = jsonDecode(await file.readAsString()) as List;
    _items
      ..clear()
      ..addAll(data.map((e) => ClothingItem.fromJson(e)));

    await _runMigrations();
  }

  /// One-time data fixes applied on load.
  Future<void> _runMigrations() async {
    bool changed = false;

    // Fix 1: shoes that were incorrectly tagged with clothing materials
    const clothingOnlyMaterials = {'denim', 'cotton', 'wool', 'silk', 'linen',
        'velvet', 'chiffon', 'satin', 'lace', 'jersey', 'fleece', 'knit', 'spandex'};

    for (int i = 0; i < _items.length; i++) {
      final item = _items[i];
      if (item.category == ClothingCategory.shoes) {
        final mat = item.analysis.material.toLowerCase();
        if (clothingOnlyMaterials.contains(mat)) {
          debugPrint('[Migration] fixed shoe material "$mat" → "unknown" for "${item.title}"');
          _items[i] = item.copyWith(
            analysis: item.analysis.copyWith(material: 'unknown'),
          );
          changed = true;
        }
      }

      // Fix 2: backfill seasonality for items that have 'AllSeason' but
      // could be more specifically tagged based on their title/garment type.
      // This makes season filters useful for existing closet items.
      final item2 = _items[i];
      if (item2.analysis.seasonality == 'AllSeason' && item2.overrides['seasonality'] == null) {
        final title = item2.title.toLowerCase();
        String? inferredSeason;
        if (_containsAny(title, ['coat', 'puffer', 'sweater', 'cardigan'])) {
          inferredSeason = 'Winter';
        } else if (_containsAny(title, ['shorts', 'sandals', 'tank'])) {
          inferredSeason = 'Summer';
        } else if (_containsAny(title, ['jacket', 'blazer', 'boots', 'trouser', 'chino', 'hoodie', 'turtleneck'])) {
          inferredSeason = 'Autumn';
        } else if (_containsAny(title, ['shirt', 'blouse', 'skirt', 'loafer', 'flat'])) {
          inferredSeason = 'Spring';
        }
        if (inferredSeason != null) {
          debugPrint('[Migration] seasonality "${item2.title}" → $inferredSeason');
          _items[i] = item2.copyWith(
            analysis: item2.analysis.copyWith(seasonality: inferredSeason),
          );
          changed = true;
        }
      }
    }

    if (changed) await save();
  }

  static bool _containsAny(String text, List<String> keywords) =>
      keywords.any((k) => text.contains(k));

  Future<void> clearAll() async {
    final directory = await getApplicationDocumentsDirectory();
    final closetFile = File('${directory.path}/closet.json');

    for (final item in _items) {
      final f = File(item.imagePath);
      if (await f.exists()) await f.delete();
    }

    _items.clear();
    if (await closetFile.exists()) await closetFile.delete();
  }

  Future<void> updateItemCategory(String itemId, ClothingCategory newCategory) async {
    final idx = _items.indexWhere((i) => i.id == itemId);
    if (idx == -1) return;
    _items[idx] = _items[idx].copyWith(category: newCategory);
    await save();
  }

  Future<void> updateItemTitle(String itemId, String newTitle) async {
    final idx = _items.indexWhere((i) => i.id == itemId);
    if (idx == -1) return;
    _items[idx] = _items[idx].copyWith(title: newTitle.trim());
    await save();
  }

  Future<void> updateItemNotes(String itemId, String notes) async {
    final idx = _items.indexWhere((i) => i.id == itemId);
    if (idx == -1) return;
    _items[idx] = _items[idx].copyWith(notes: notes);
    await save();
  }

  Future<void> updateItemAnalysis(String itemId, ClothingAnalysis analysis) async {
    final idx = _items.indexWhere((i) => i.id == itemId);
    if (idx == -1) return;
    _items[idx] = _items[idx].copyWith(analysis: analysis);
    await save();
  }

  Future<void> updateItemOverrides(String itemId, Map<String, dynamic> overrides) async {
    final idx = _items.indexWhere((i) => i.id == itemId);
    if (idx == -1) return;
    _items[idx] = _items[idx].copyWith(overrides: overrides);
    await save();
  }

  Future<void> deleteItem(String itemId) async {
    final idx = _items.indexWhere((i) => i.id == itemId);
    if (idx == -1) return;

    final item = _items.removeAt(idx);
    final f = File(item.imagePath);
    if (await f.exists()) await f.delete();

    // Remove any saved outfits that contained this item
    await OutfitService().removeOutfitsContaining(itemId);

    // Delete from cloud storage (non-blocking)
    unawaited(StorageService.deleteClosetImage(itemId));

    await save();
  }

  Future<void> rerunAnalysis(String itemId) async {
    final idx = _items.indexWhere((i) => i.id == itemId);
    if (idx == -1) return;

    final item = _items[idx];
    final imageFile = File(item.imagePath);

    ClothingAnalysis? updatedAnalysis;
    String? updatedTitle;

    // 1. Gemini (primary)
    if (AppConfig.hasGeminiKey) {
      try {
        GeminiVisionService.apiKey = AppConfig.geminiApiKey;
        final r = await GeminiVisionService.analyseClothing(imageFile, hint: item.category);
        if (r != null) {
          updatedAnalysis = _analysisFromGemini(r);
          updatedTitle = r.title;
        }
      } catch (_) {}
    }

    // 2. HuggingFace (fallback)
    if (updatedAnalysis == null) {
      try {
        final hfResult = await HuggingFaceService()
            .analyzeClothing(imageFile, hint: item.category);
        if (hfResult != null) {
          updatedAnalysis = hfResult.toAnalysis();
          updatedTitle = hfResult.title;
        }
      } catch (_) {}
    }

    // 3. ML Kit (last resort)
    if (updatedAnalysis == null) {
      final analyzer = ClothingItemAnalyzer();
      final result = await analyzer.analyze(imageFile, categoryHint: item.category);
      updatedAnalysis = FashionAnalysisMapper.map(result);
      updatedTitle = FashionAnalysisMapper.generateTitle(
        category: item.category,
        colors: result.colors,
        strongTags: result.strongTags,
      );
    }

    _items[idx] = item.copyWith(
      analysis: updatedAnalysis,
      title: updatedTitle ?? item.title,
    );
    await save();
  }

  /// Builds a ClothingAnalysis from a Gemini result, providing rich descriptions.
  static const _shoeGarments = {
    'boots', 'sneakers', 'oxfords', 'heels', 'sandals', 'loafers', 'mules', 'flats'
  };
  static const _validShoeMaterials = {
    'canvas', 'mesh', 'leather', 'suede', 'rubber', 'synthetic', 'unknown'
  };
  static const _clothingOnlyMaterials = {
    'denim', 'cotton', 'wool', 'silk', 'linen', 'velvet', 'chiffon',
    'satin', 'lace', 'jersey', 'fleece', 'knit', 'spandex', 'nylon'
  };

  static ClothingAnalysis _analysisFromGemini(GeminiClothingResult r) {
    final isDenim = r.garment.contains('jean') || r.garment.contains('denim');
    final washLabel = isDenim && r.wash != 'none' ? r.wash.replaceAll('-', ' ') : '';

    final description = _buildGeminiDescription(r);

    // Never allow clothing-only materials on shoes — use 'unknown' instead
    final isShoe = _shoeGarments.contains(r.garment);
    final safeMaterial = isShoe && _clothingOnlyMaterials.contains(r.material)
        ? 'unknown'
        : r.material;

    return ClothingAnalysis(
      primaryStyle: _geminiStyle(r),
      subStyles: isDenim ? ['Denim'] : (r.pattern != 'solid' && r.pattern.isNotEmpty ? [_cap(r.pattern)] : []),
      colorSeason: 'Any',
      colors: [r.color],
      temperature: _geminiTemp(r.color),
      contrastLevel: (r.color == 'black' || r.color == 'white') ? 'High' : 'Medium',
      patternLevel: r.pattern.isEmpty ? 'Solid' : _cap(r.pattern),
      structure: (r.garment == 'blazer' || r.garment == 'coat' || r.garment == 'jacket') ? 'Structured' : 'Soft',
      formality: _geminiFormal(r.garment),
      seasonality: _geminiSeason(r.garment),
      bodyTypeFit: r.fit == 'regular' || r.fit.isEmpty ? 'Standard fit' : '${r.fit} fit',
      description: description,
      history: 'Added via Chromé AI analysis.',
      material: safeMaterial,
    );
  }

  static String _cap(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  static String _buildGeminiDescription(GeminiClothingResult r) {
    final c = r.color == 'neutral' || r.color.isEmpty ? '' : '${r.color} ';
    final hasPattern = r.pattern.isNotEmpty && r.pattern != 'solid';
    final patternPrefix = hasPattern ? '${r.pattern} ' : '';
    final isDenim = r.garment.contains('jean') || r.garment.contains('denim');

    if (r.garment == 'shorts') {
      return 'A pair of ${c}shorts with a ${r.fit == 'regular' ? 'relaxed' : r.fit} cut. '
          'Easy to style — pair with a fitted tee or loose shirt for a casual look.';
    }
    if (isDenim) {
      final wash = r.wash != 'none' ? '${r.wash.replaceAll('-', ' ')} ' : c;
      final fitDesc = r.fit == 'wide-leg' ? 'wide-leg silhouette' : r.fit == 'slim' ? 'slim cut' : 'classic cut';
      return 'A $fitDesc in ${wash}denim. '
          'Style with a tucked-in tee or a structured blazer for a polished look.';
    }
    if (r.garment == 'hoodie' || r.garment == 'sweatshirt') {
      return 'A ${r.fit == 'oversized' ? 'relaxed oversized' : r.fit} ${c}hoodie. '
          'Layer over a long-sleeve tee or wear alone with straight-leg trousers.';
    }
    if (r.garment == 'sweater' || r.garment == 'cardigan') {
      return 'A ${c}knit piece that adds texture and warmth. '
          'Works layered over a shirt or alone with tailored bottoms.';
    }
    if (r.garment == 'blazer') {
      return 'A ${c}blazer — the single piece that elevates any outfit. '
          'Wear over a tee for smart-casual or a dress shirt for formal.';
    }
    if (r.garment == 'boots') {
      return '${c.isEmpty ? '' : '${c[0].toUpperCase()}${c.substring(1)}'}Boots — versatile and grounding. '
          'Pair with jeans, a midi skirt, or straight trousers.';
    }
    if (r.garment == 'sneakers') {
      return '${c.isEmpty ? '' : '${c[0].toUpperCase()}${c.substring(1)}'}Sneakers — the casual anchor. '
          'Best with relaxed or mid-weight bottoms.';
    }
    final fml = _geminiFormal(r.garment).toLowerCase();
    final patternNote = hasPattern ? ', featuring a ${r.pattern} pattern' : '';
    return 'A $c$patternPrefix${r.garment} with a $fml feel$patternNote. '
        'Style with complementary pieces and balanced proportions.';
  }

  static String _geminiStyle(GeminiClothingResult r) {
    // Formal/smart pieces
    if (r.garment == 'blazer' || r.garment == 'trousers' || r.garment == 'chinos' ||
        r.garment == 'oxfords' || r.garment == 'loafers') {
      return 'Classic';
    }
    // Athletic/comfort pieces
    if (r.garment == 'leggings' || r.garment == 'joggers') return 'Athleisure';
    // Romantic: floral or lace pattern
    if (r.pattern == 'floral' || r.pattern == 'lace') return 'Romantic';
    // Streetwear: oversized fit, hoodies
    if (r.garment == 'hoodie' || r.fit == 'oversized') return 'Streetwear';
    return 'Everyday';
  }

  static String _geminiTemp(String color) {
    const warm = ['red', 'orange', 'yellow', 'coral', 'burgundy', 'camel', 'brown'];
    const cool = ['blue', 'navy', 'teal', 'purple', 'grey'];
    if (warm.contains(color)) return 'Warm';
    if (cool.contains(color)) return 'Cool';
    return 'Neutral';
  }

  static String _geminiFormal(String garment) {
    const formal = ['blazer', 'trousers', 'heels', 'loafers'];
    const casual = ['shorts', 'hoodie', 'sneakers', 'joggers', 'leggings', 't-shirt'];
    if (formal.contains(garment)) return 'Smart';
    if (casual.contains(garment)) return 'Casual';
    return 'Casual';
  }

  static String _geminiSeason(String garment) {
    // Heavy winter pieces
    const winter = ['coat', 'puffer', 'sweater', 'cardigan'];
    // Light summer pieces
    const summer = ['shorts', 'sandals', 'tank-top'];
    // Autumn/transitional pieces
    const autumn = ['jacket', 'blazer', 'boots', 'trousers', 'chinos', 'hoodie', 'turtleneck'];
    // Spring/transitional pieces
    const spring = ['shirt', 'blouse', 'skirt', 'loafers', 'flats'];
    if (winter.contains(garment)) return 'Winter';
    if (summer.contains(garment)) return 'Summer';
    if (autumn.contains(garment)) return 'Autumn';
    if (spring.contains(garment)) return 'Spring';
    return 'AllSeason'; // jeans, t-shirts, sneakers etc. go with any season
  }
}
