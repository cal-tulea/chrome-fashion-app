import 'dart:io';
import '../models/clothing_analysis_result.dart';
import '../models/clothing_item.dart';
import 'color_analysis_service.dart';
import 'mlkit_tagging_service.dart';

class CategoryPrediction {
  final ClothingCategory category;
  final double confidence; // 0..1
  final bool uncertain;

  const CategoryPrediction({
    required this.category,
    required this.confidence,
    required this.uncertain,
  });
}

class ClothingItemAnalyzer {
  ClothingItemAnalyzer({
    ColorAnalysisService? colorService,
    MlKitTaggingService? taggingService,
  })  : _colorService = colorService ?? ColorAnalysisService(),
        _taggingService = taggingService ?? MlKitTaggingService();

  final ColorAnalysisService _colorService;
  final MlKitTaggingService _taggingService;

  Future<CategoryPrediction> predictCategory(
    File imageFile, {
    ClothingCategory? categoryHint,
  }) async {
    final labelScores = await _taggingService.detectLabelScores(imageFile);
    final strongTags = _strongTags(labelScores);

    final scores = _scoreCategories(labelScores, strongTags: strongTags);
    final entries = scores.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    if (entries.isEmpty || entries.first.value < 0.18) {
      final fallback = (categoryHint != null && categoryHint != ClothingCategory.all)
          ? categoryHint
          : ClothingCategory.tops;

      return CategoryPrediction(category: fallback, confidence: 0.20, uncertain: true);
    }

    final best = entries[0];
    final second = entries.length > 1 ? entries[1] : null;

    final b = best.value;
    final s = second?.value ?? 0.0;
    final conf = (b / (b + s + 0.0001)).clamp(0.0, 1.0);

    final closeCall = second != null && (best.value - second.value) < 0.12;
    final lowSignal = best.value < 0.35;
    final uncertain = closeCall || lowSignal;

    ClothingCategory picked = best.key;
    if (uncertain && categoryHint != null && categoryHint != ClothingCategory.all) {
      picked = categoryHint;
    }

    return CategoryPrediction(category: picked, confidence: conf, uncertain: uncertain);
  }

  Future<ClothingAnalysisResult> analyze(
    File imageFile, {
    ClothingCategory? categoryHint,
  }) async {
    final labelScores = await _taggingService.detectLabelScores(imageFile);
    final tags = labelScores.map((e) => e.label).toList();
    final strongTags = _strongTags(labelScores);

    final colorSummary = await _colorService.analyze(imageFile, maxColors: 4);

    final scores = _scoreCategories(labelScores, strongTags: strongTags);
    final inferred = _pickCategory(scores, hint: categoryHint);

    final garmentType = _garmentTypeFrom(inferred, tags);
    final visualTags = _visualTagsFromStrongTags(strongTags);

    // NEW fashion signals
    final temperature = colorSummary.temperature;
    final contrastLevel = _contrastFromColors(colorSummary.colors);
    final patternLevel = _patternFromLabels(labelScores);
    final structure = _structureFrom(inferred, strongTags, labelScores);
    final formality = _formalityFrom(inferred, strongTags, labelScores);
    final seasonality = _seasonalityFrom(inferred, strongTags, labelScores);

    return ClothingAnalysisResult(
      garmentType: garmentType,
      visualTags: visualTags,
      strongTags: strongTags,
      colors: colorSummary.colors,
      colorSeasonGuess: colorSummary.seasonGuess,

      temperature: temperature,
      contrastLevel: contrastLevel,
      patternLevel: patternLevel,
      structure: structure,
      formality: formality,
      seasonality: seasonality,

      inferredCategory: inferred,
    );
  }

  // --------------------------
  // Strong tags (high confidence only)
  // --------------------------
  List<String> _strongTags(List<LabelScore> labels) {
    final out = <String>{};

    for (final l in labels) {
      if (l.confidence < 0.50) continue;
      final s = l.label.toLowerCase();

      // shoes
      if (s.contains('sneaker')) out.add('sneakers');
      if (s.contains('boot')) out.add('boots');
      if (s.contains('heel')) out.add('heels');
      if (s.contains('shoe') || s.contains('footwear')) out.add('shoes');

      // tops
      if (s.contains('hoodie')) out.add('hoodie');
      if (s.contains('sweater') || s.contains('knit') || s.contains('jumper') || s.contains('pullover')) out.add('sweater');
      if (s.contains('shirt') || s.contains('t-shirt') || s.contains('tee')) out.add('shirt');

      // bottoms
      if (s.contains('trouser') || s.contains('pants') || s.contains('pant')) out.add('trousers');
      if (s.contains('skirt')) out.add('skirt');
      if (s.contains('shorts') || s.contains('short')) out.add('shorts');
      if (s.contains('jeans') || s.contains('jean')) out.add('jeans');

      // outerwear
      if (s.contains('coat')) out.add('coat');
      if (s.contains('jacket')) out.add('jacket');
      if (s.contains('blazer')) out.add('blazer');

      // accessories
      if (s.contains('bag') || s.contains('handbag') || s.contains('purse')) out.add('bag');
      if (s.contains('belt')) out.add('belt');
      if (s.contains('hat') || s.contains('cap')) out.add('hat');

      // materials only if explicit
      if (s.contains('denim') || s.contains('jeans') || s.contains('jean')) out.add('denim');
      if (s.contains('leather')) out.add('leather');

      // patterns (explicit)
      if (s.contains('stripe') || s.contains('striped')) out.add('striped');
      if (s.contains('plaid') || s.contains('check')) out.add('plaid');
      if (s.contains('floral')) out.add('floral');
      if (s.contains('polka')) out.add('polka');
    }

    return out.toList();
  }

  List<String> _visualTagsFromStrongTags(List<String> strong) {
    final s = strong.map((e) => e.toLowerCase()).toSet();
    final out = <String>[];

    if (s.contains('denim')) out.add('denim');
    if (s.contains('leather')) out.add('leather');
    if (s.contains('sweater')) out.add('knitwear');

    return out;
  }

  // --------------------------
  // Category scoring (same as your current logic)
  // --------------------------
  Map<ClothingCategory, double> _scoreCategories(
    List<LabelScore> labels, {
    required List<String> strongTags,
  }) {
    double scoreFor(Set<String> keywords) {
      double s = 0;
      for (final l in labels) {
        if (keywords.any((k) => l.label.contains(k))) {
          s += l.confidence * (l.confidence >= 0.70 ? 1.4 : 1.0);
        }
      }
      return s;
    }

    final shoesKw = <String>{
      'shoe', 'shoes', 'sneaker', 'sneakers', 'boot', 'boots', 'heel', 'heels',
      'loafer', 'loafers', 'sandals', 'sandal', 'footwear', 'trainer', 'trainers',
    };

    final topKw = <String>{
      'shirt', 't-shirt', 'tee', 'blouse', 'top', 'sweater', 'jumper',
      'pullover', 'hoodie', 'sweatshirt', 'cardigan', 'knit',
    };

    final bottomKw = <String>{
      'pants', 'pant', 'trouser', 'trousers', 'jean', 'jeans', 'denim',
      'skirt', 'short', 'shorts', 'leggings',
    };

    final outerKw = <String>{'coat', 'jacket', 'parka', 'trench', 'overcoat', 'raincoat', 'blazer'};

    final accessoryKw = <String>{'bag', 'handbag', 'purse', 'belt', 'hat', 'cap', 'scarf', 'watch', 'jewelry'};

    var shoesScore = scoreFor(shoesKw);
    var topScore = scoreFor(topKw);
    var bottomScore = scoreFor(bottomKw);
    var outerScore = scoreFor(outerKw);
    var accessoryScore = scoreFor(accessoryKw);

    final strong = strongTags.map((e) => e.toLowerCase()).toSet();

    if (strong.contains('sweater') || strong.contains('shirt') || strong.contains('hoodie')) {
      bottomScore *= 0.45;
      outerScore *= 0.70;
      topScore += 0.30;
    }

    final anyShoeHit = labels.any((l) => shoesKw.any((k) => l.label.contains(k)));
    if (anyShoeHit) shoesScore += 0.35;

    final clothingEvidence = topScore + bottomScore + shoesScore + outerScore;
    if (clothingEvidence > 0.35) accessoryScore *= 0.30;

    if (topScore >= 0.30 && outerScore >= 0.30) outerScore *= 0.75;
    if (shoesScore >= 0.45 && topScore >= 0.25) topScore *= 0.65;

    return {
      ClothingCategory.shoes: shoesScore,
      ClothingCategory.tops: topScore,
      ClothingCategory.bottoms: bottomScore,
      ClothingCategory.outerwear: outerScore,
      ClothingCategory.accessories: accessoryScore,
    };
  }

  ClothingCategory _pickCategory(Map<ClothingCategory, double> scores, {ClothingCategory? hint}) {
    final entries = scores.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final best = entries.first;
    final second = entries.length > 1 ? entries[1] : null;

    if (best.value < 0.18) {
      if (hint != null && hint != ClothingCategory.all) return hint;
      return ClothingCategory.tops;
    }

    if (second != null && (best.value - second.value) < 0.12) {
      if (hint != null && hint != ClothingCategory.all) return hint;
    }

    return best.key;
  }

  String _garmentTypeFrom(ClothingCategory cat, List<String> tags) {
    switch (cat) {
      case ClothingCategory.shoes:
        return 'shoes';
      case ClothingCategory.outerwear:
        return 'outerwear';
      case ClothingCategory.bottoms:
        return 'bottom';
      case ClothingCategory.accessories:
        return 'accessory';
      case ClothingCategory.tops:
      case ClothingCategory.all:
        break;
    }
    final t = tags.join(' ');
    if (t.contains('dress')) return 'dress';
    return 'top';
  }

  // --------------------------
  // Fashion signal heuristics (safe + editable later)
  // --------------------------
  String _contrastFromColors(List<String> colors) {
    final c = colors.map((e) => e.toLowerCase()).toSet();
    final hasBlack = c.contains('black');
    final hasWhite = c.contains('white');

    if (hasBlack && hasWhite) return 'High';
    if (c.length <= 2) return 'Low';
    return 'Medium';
  }

  String _patternFromLabels(List<LabelScore> labels) {
    // Only if explicitly detected at decent confidence
    bool hit(String needle) =>
        labels.any((l) => l.confidence >= 0.55 && l.label.contains(needle));

    if (hit('plaid') || hit('check') || hit('floral') || hit('polka')) return 'Busy';
    if (hit('striped') || hit('stripe')) return 'Subtle';
    return 'Solid';
  }

  String _structureFrom(ClothingCategory cat, List<String> strongTags, List<LabelScore> labels) {
    final s = strongTags.map((e) => e.toLowerCase()).toSet();
    if (s.contains('blazer') || s.contains('coat') || s.contains('jacket')) return 'Structured';
    if (cat == ClothingCategory.outerwear) return 'Structured';
    return 'Soft';
  }

  String _formalityFrom(ClothingCategory cat, List<String> strongTags, List<LabelScore> labels) {
    final s = strongTags.map((e) => e.toLowerCase()).toSet();
    if (s.contains('blazer')) return 'Smart';
    if (cat == ClothingCategory.outerwear) return 'Smart';
    if (cat == ClothingCategory.shoes && (s.contains('heels'))) return 'Smart';
    return 'Casual';
  }

  String _seasonalityFrom(ClothingCategory cat, List<String> strongTags, List<LabelScore> labels) {
    final s = strongTags.map((e) => e.toLowerCase()).toSet();
    if (s.contains('coat') || s.contains('boots') || s.contains('sweater')) return 'Winter';
    if (s.contains('shorts') || labels.any((l) => l.label.contains('sandal') && l.confidence > 0.55)) return 'Summer';
    if (cat == ClothingCategory.outerwear) return 'Transitional';
    return 'AllSeason';
  }
}
