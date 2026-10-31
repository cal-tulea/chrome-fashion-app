class ClothingAnalysis {
  final String primaryStyle;
  final List<String> subStyles;

  /// User-facing season (Winter/Summer/Autumn/Spring/Any)
  final String colorSeason;

  /// Detected color names like ["black", "white", "beige"]
  final List<String> colors;

  /// NEW: Warm / Cool / Neutral
  final String temperature;

  /// NEW: Low / Medium / High
  final String contrastLevel;

  /// NEW: Solid / Subtle / Busy
  final String patternLevel;

  /// NEW: Soft / Structured
  final String structure;

  /// NEW: Casual / Smart / Formal
  final String formality;

  /// NEW: AllSeason / Summer / Winter / Transitional
  final String seasonality;

  final String bodyTypeFit;
  final String description;
  final String history;

  /// NEW: detected fabric material (cotton, denim, wool, etc.)
  final String material;

  const ClothingAnalysis({
    required this.primaryStyle,
    required this.subStyles,
    required this.colorSeason,
    required this.colors,
    required this.temperature,
    required this.contrastLevel,
    required this.patternLevel,
    required this.structure,
    required this.formality,
    required this.seasonality,
    required this.bodyTypeFit,
    required this.description,
    required this.history,
    this.material = 'Unknown',
  });

  ClothingAnalysis copyWith({
    String? primaryStyle,
    List<String>? subStyles,
    String? colorSeason,
    List<String>? colors,
    String? temperature,
    String? contrastLevel,
    String? patternLevel,
    String? structure,
    String? formality,
    String? seasonality,
    String? bodyTypeFit,
    String? description,
    String? history,
    String? material,
  }) {
    return ClothingAnalysis(
      primaryStyle: primaryStyle ?? this.primaryStyle,
      subStyles: subStyles ?? this.subStyles,
      colorSeason: colorSeason ?? this.colorSeason,
      colors: colors ?? this.colors,
      temperature: temperature ?? this.temperature,
      contrastLevel: contrastLevel ?? this.contrastLevel,
      patternLevel: patternLevel ?? this.patternLevel,
      structure: structure ?? this.structure,
      formality: formality ?? this.formality,
      seasonality: seasonality ?? this.seasonality,
      bodyTypeFit: bodyTypeFit ?? this.bodyTypeFit,
      description: description ?? this.description,
      history: history ?? this.history,
      material: material ?? this.material,
    );
  }

  Map<String, dynamic> toJson() => {
        'primaryStyle': primaryStyle,
        'subStyles': subStyles,
        'colorSeason': colorSeason,
        'colors': colors,
        'temperature': temperature,
        'contrastLevel': contrastLevel,
        'patternLevel': patternLevel,
        'structure': structure,
        'formality': formality,
        'seasonality': seasonality,
        'bodyTypeFit': bodyTypeFit,
        'description': description,
        'history': history,
        'material': material,
      };

  factory ClothingAnalysis.fromJson(Map<String, dynamic> json) {
    return ClothingAnalysis(
      primaryStyle: (json['primaryStyle'] as String?) ?? 'Everyday',
      subStyles: List<String>.from(json['subStyles'] ?? const <String>[]),
      colorSeason: (json['colorSeason'] as String?) ?? 'Any',
      colors: List<String>.from(json['colors'] ?? const <String>[]),

      // Backwards-safe defaults:
      temperature: (json['temperature'] as String?) ?? 'Neutral',
      contrastLevel: (json['contrastLevel'] as String?) ?? 'Medium',
      patternLevel: (json['patternLevel'] as String?) ?? 'Solid',
      structure: (json['structure'] as String?) ?? 'Soft',
      formality: (json['formality'] as String?) ?? 'Casual',
      seasonality: (json['seasonality'] as String?) ?? 'AllSeason',

      bodyTypeFit: (json['bodyTypeFit'] as String?) ?? 'Standard fit',
      description: (json['description'] as String?) ?? 'A versatile wardrobe piece.',
      history: (json['history'] as String?) ?? 'A modern wardrobe staple.',
      material: (json['material'] as String?) ?? 'Unknown',
    );
  }
}
