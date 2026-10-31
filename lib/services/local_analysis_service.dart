import '../models/clothing_analysis.dart';
import '../models/clothing_item.dart';

class LocalAnalysisService {
  static ClothingAnalysis analyze(ClothingCategory category) {
    // Conservative defaults (safe + editable)
    return const ClothingAnalysis(
      primaryStyle: 'Everyday',
      subStyles: [],
      colorSeason: 'Any',
      colors: [],

      temperature: 'Neutral',
      contrastLevel: 'Medium',
      patternLevel: 'Solid',
      structure: 'Soft',
      formality: 'Casual',
      seasonality: 'AllSeason',

      bodyTypeFit: 'Standard fit',
      description: 'A versatile wardrobe piece. Add details you care about here.',
      history: 'A modern wardrobe staple.',
    );
  }
}
