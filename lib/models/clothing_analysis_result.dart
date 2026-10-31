import 'clothing_item.dart';

class ClothingAnalysisResult {
  final String garmentType;
  final List<String> visualTags;
  final List<String> strongTags;

  final List<String> colors;
  final String colorSeasonGuess;

  // NEW fashion signals
  final String temperature;     // Warm/Cool/Neutral
  final String contrastLevel;   // Low/Medium/High
  final String patternLevel;    // Solid/Subtle/Busy
  final String structure;       // Soft/Structured
  final String formality;       // Casual/Smart/Formal
  final String seasonality;     // AllSeason/Summer/Winter/Transitional

  final ClothingCategory inferredCategory;

  ClothingAnalysisResult({
    required this.garmentType,
    required this.visualTags,
    required this.strongTags,
    required this.colors,
    required this.colorSeasonGuess,

    required this.temperature,
    required this.contrastLevel,
    required this.patternLevel,
    required this.structure,
    required this.formality,
    required this.seasonality,

    required this.inferredCategory,
  });
}
