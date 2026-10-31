import 'clothing_analysis.dart';

enum ClothingCategory {
  all,
  tops,
  bottoms,
  shoes,
  outerwear,
  accessories,
}

class ClothingItem {
  final String id;
  final String imagePath;
  final ClothingCategory category;

  /// User-facing title (generated, editable)
  final String title;

  /// User notes / memory
  final String notes;

  /// System/AI analysis
  final ClothingAnalysis analysis;

  /// NEW: user overrides for styling intelligence (keeps UI + engine flexible)
  /// Example:
  /// {
  ///   "colorSeason": "Winter",
  ///   "formality": "Smart",
  ///   "structure": "Structured"
  /// }
  final Map<String, dynamic> overrides;

  ClothingItem({
    required this.id,
    required this.imagePath,
    required this.category,
    required this.title,
    required this.notes,
    required this.analysis,
    required this.overrides,
  });

  ClothingItem copyWith({
    String? id,
    String? imagePath,
    ClothingCategory? category,
    String? title,
    String? notes,
    ClothingAnalysis? analysis,
    Map<String, dynamic>? overrides,
  }) {
    return ClothingItem(
      id: id ?? this.id,
      imagePath: imagePath ?? this.imagePath,
      category: category ?? this.category,
      title: title ?? this.title,
      notes: notes ?? this.notes,
      analysis: analysis ?? this.analysis,
      overrides: overrides ?? this.overrides,
    );
  }

  /// Convenience: get "effective" analysis values (override wins).
  /// This is what the outfit engine should use.
  String get effectiveColorSeason =>
      (overrides['colorSeason'] as String?) ?? analysis.colorSeason;

  String get effectiveFormality =>
      (overrides['formality'] as String?) ?? analysis.formality;

  String get effectiveStructure =>
      (overrides['structure'] as String?) ?? analysis.structure;

  String get effectivePatternLevel =>
      (overrides['patternLevel'] as String?) ?? analysis.patternLevel;

  String get effectiveContrastLevel =>
      (overrides['contrastLevel'] as String?) ?? analysis.contrastLevel;

  String get effectiveTemperature =>
      (overrides['temperature'] as String?) ?? analysis.temperature;

  String get effectiveSeasonality =>
      (overrides['seasonality'] as String?) ?? analysis.seasonality;

  String get effectiveMaterial =>
      (overrides['material'] as String?)?.isNotEmpty == true
          ? overrides['material'] as String
          : analysis.material;

  List<String> get effectiveSubStyles {
    final v = overrides['subStyles'];
    if (v is List) return v.map((e) => e.toString()).toList();
    return analysis.subStyles;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'imagePath': imagePath,
        'category': category.name,
        'title': title,
        'notes': notes,
        'analysis': analysis.toJson(),
        'overrides': overrides, // NEW
      };

  factory ClothingItem.fromJson(Map<String, dynamic> json) {
    final savedCat = json['category'] as String?;
    final cat = ClothingCategory.values.firstWhere(
      (e) => e.name == savedCat,
      orElse: () => ClothingCategory.tops,
    );

    return ClothingItem(
      id: json['id'],
      imagePath: json['imagePath'],
      category: cat,
      title: (json['title'] as String?) ?? 'Untitled item',
      notes: (json['notes'] as String?) ?? '',
      analysis: ClothingAnalysis.fromJson(json['analysis'] ?? const <String, dynamic>{}),
      overrides: Map<String, dynamic>.from(json['overrides'] ?? const <String, dynamic>{}),
    );
  }
}
