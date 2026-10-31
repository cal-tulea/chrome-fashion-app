import '../models/clothing_analysis.dart';
import '../models/clothing_analysis_result.dart';
import '../models/clothing_item.dart';

class FashionAnalysisMapper {
  static ClothingAnalysis map(ClothingAnalysisResult r) {
    final primaryStyle = _primaryStyle(r);
    final subStyles = _subStyles(r);

    final season = (r.colorSeasonGuess.trim().isEmpty) ? 'Any' : r.colorSeasonGuess.trim();
    final description = _nonBlank(_description(r, primaryStyle, season));
    final history = _nonBlank(_history(r));

    return ClothingAnalysis(
      primaryStyle: primaryStyle,
      subStyles: subStyles,
      colorSeason: season,
      colors: r.colors,

      // ✅ new fashion fields
      temperature: r.temperature,
      contrastLevel: r.contrastLevel,
      patternLevel: r.patternLevel,
      structure: r.structure,
      formality: r.formality,
      seasonality: r.seasonality,

      bodyTypeFit: _fit(r),
      description: description,
      history: history,
    );
  }

  static String generateTitle({
    required ClothingCategory category,
    required List<String> colors,
    required List<String> strongTags,
  }) {
    final color = colors.isNotEmpty ? _cap(colors.first) : 'Neutral';
    final t = strongTags.map((e) => e.toLowerCase()).toSet();

    String noun = switch (category) {
      ClothingCategory.shoes => 'shoes',
      ClothingCategory.bottoms => 'bottoms',
      ClothingCategory.outerwear => 'outerwear',
      ClothingCategory.accessories => 'accessory',
      ClothingCategory.tops => 'top',
      ClothingCategory.all => 'item',
    };

    if (category == ClothingCategory.shoes) {
      if (t.contains('boots')) {
        noun = 'boots';
      } else if (t.contains('sneakers')) noun = 'sneakers';
      else if (t.contains('heels')) noun = 'heels';
      else if (t.contains('shoes')) noun = 'shoes';
    }

    if (category == ClothingCategory.bottoms) {
      if (t.contains('trousers')) {
        noun = 'trousers';
      } else if (t.contains('skirt')) noun = 'skirt';
      else if (t.contains('shorts')) noun = 'shorts';
    }

    if (category == ClothingCategory.tops) {
      if (t.contains('sweater')) {
        noun = 'sweater';
      } else if (t.contains('hoodie')) noun = 'hoodie';
      else if (t.contains('shirt')) noun = 'shirt';
    }

    if (category == ClothingCategory.outerwear) {
      if (t.contains('coat')) {
        noun = 'coat';
      } else if (t.contains('jacket')) noun = 'jacket';
      else if (t.contains('blazer')) noun = 'blazer';
    }

    if (category == ClothingCategory.accessories) {
      if (t.contains('bag')) {
        noun = 'bag';
      } else if (t.contains('belt')) noun = 'belt';
      else if (t.contains('hat')) noun = 'hat';
    }

    final material = _materialWord(t);
    if (material != null && (noun == 'sweater' || noun == 'trousers' || noun == 'boots')) {
      return '$color $material $noun';
    }

    return '$color $noun';
  }

  static String _primaryStyle(ClothingAnalysisResult r) {
    final tags = r.visualTags.map((e) => e.toLowerCase()).toSet();
    if (tags.contains('tailored')) return 'Classic';
    if (tags.contains('sporty')) return 'Athleisure';
    if (tags.contains('oversized')) return 'Streetwear';
    return 'Everyday';
  }

  static List<String> _subStyles(ClothingAnalysisResult r) {
    final tags = r.visualTags.map((e) => e.toLowerCase()).toSet();
    final subs = <String>[];
    if (tags.contains('knitwear')) subs.add('Knit');
    if (tags.contains('denim')) subs.add('Denim');
    if (tags.contains('leather')) subs.add('Leather');
    return subs;
  }

  static String _fit(ClothingAnalysisResult r) {
    final tags = r.visualTags.map((e) => e.toLowerCase()).toSet();
    if (tags.contains('oversized')) return 'Relaxed fit';
    if (tags.contains('tailored')) return 'Structured fit';
    return 'Standard fit';
  }

  static String _description(ClothingAnalysisResult r, String style, String season) {
    final garment = _prettyGarment(r);
    final palette = _paletteSentence(r.colors, season);
    final detail = _detailSentence(r);
    final styling = _stylingSentence(r, style, season);

    final parts = <String>[
      'This is a $garment.',
      palette,
      if (detail.isNotEmpty) detail,
      styling,
    ];

    return parts.where((s) => s.trim().isNotEmpty).join(' ');
  }

  static String _history(ClothingAnalysisResult r) {
    final g = r.garmentType.toLowerCase();
    if (g.contains('shoes')) {
      return 'Footwear shapes the tone of an outfit—keep the rest simple and let the silhouette do the work.';
    }
    if (g.contains('outerwear')) {
      return 'Outer layers finish the look. A clean line and consistent palette make outfits feel instantly more polished.';
    }
    if (g.contains('bottom')) {
      return 'Bottoms set the silhouette. Pair with a simpler top for balance, then echo one color in your shoes or bag.';
    }
    if (g.contains('accessory')) {
      return 'Accessories are best used to repeat a color or add a small contrast—one strong piece is usually enough.';
    }
    return 'A reliable piece that becomes more versatile the more you keep the palette cohesive and the proportions balanced.';
  }

  static String _prettyGarment(ClothingAnalysisResult r) {
    final t = r.strongTags.map((e) => e.toLowerCase()).toSet();
    if (t.contains('boots')) return 'pair of boots';
    if (t.contains('sneakers')) return 'pair of sneakers';
    if (t.contains('heels')) return 'pair of heels';
    if (t.contains('shoes')) return 'pair of shoes';
    if (t.contains('trousers')) return 'pair of trousers';
    if (t.contains('skirt')) return 'skirt';
    if (t.contains('shorts')) return 'pair of shorts';
    if (t.contains('sweater')) return 'sweater';
    if (t.contains('hoodie')) return 'hoodie';
    if (t.contains('shirt')) return 'shirt';
    if (t.contains('coat')) return 'coat';
    if (t.contains('jacket')) return 'jacket';
    if (t.contains('blazer')) return 'blazer';
    if (t.contains('bag')) return 'bag';
    if (t.contains('belt')) return 'belt';
    if (t.contains('hat')) return 'hat';
    final g = r.garmentType.trim().isEmpty ? 'piece' : r.garmentType.trim();
    return g;
  }

  static String _paletteSentence(List<String> colors, String season) {
    if (colors.isEmpty) {
      return season == 'Any'
          ? 'The palette reads neutral and easy to style.'
          : 'The palette reads $season and easy to style.';
    }

    final colorPhrase = _prettyColors(colors);

    if (season == 'Any') return 'Colors: $colorPhrase.';
    return 'Colors: $colorPhrase. The overall palette reads $season.';
  }

  static String _detailSentence(ClothingAnalysisResult r) {
    final t = r.strongTags.map((e) => e.toLowerCase()).toSet();
    final material = _materialWord(t);
    if (material == null) return '';
    if (material == 'denim') return 'Material: denim (adds structure and a casual, timeless feel).';
    if (material == 'leather') return 'Material: leather (adds contrast and a sharper finish).';
    return '';
  }

  static String _stylingSentence(ClothingAnalysisResult r, String style, String season) {
    final g = r.garmentType.toLowerCase();
    final colors = r.colors;
    final neutralBase = _isMostlyNeutral(colors);

    if (g.contains('shoes')) {
      if (neutralBase) return 'Styling tip: use these as a base for tonal outfits or let them be the single accent.';
      return 'Styling tip: keep the outfit simple and repeat one shoe color somewhere small (bag/belt) for cohesion.';
    }
    if (g.contains('bottom')) {
      return 'Styling tip: pair with a simpler top and match one color with your shoes for a clean silhouette.';
    }
    if (g.contains('outerwear')) {
      return 'Styling tip: keep the layer slightly more structured than what’s underneath for a finished look.';
    }
    if (g.contains('accessory')) {
      return 'Styling tip: use this to repeat a color from your outfit or add one small contrast—avoid stacking too many statements.';
    }

    if (style == 'Minimal' || season == 'Winter') {
      return 'Styling tip: this works especially well in tonal outfits (black/white/grey) or clean neutrals.';
    }
    return 'Styling tip: build around it with one main color family + one neutral for an effortless look.';
  }

  static String? _materialWord(Set<String> strongTagsLower) {
    if (strongTagsLower.contains('denim')) return 'denim';
    if (strongTagsLower.contains('leather')) return 'leather';
    return null;
  }

  static bool _isMostlyNeutral(List<String> colors) {
    final neutrals = {'black', 'white', 'grey', 'beige', 'brown'};
    if (colors.isEmpty) return true;
    final neutralCount = colors.where(neutrals.contains).length;
    return neutralCount / colors.length >= 0.7;
  }

  static String _prettyColors(List<String> colors) {
    if (colors.isEmpty) return 'neutrals';
    if (colors.length == 1) return colors.first;
    if (colors.length == 2) return '${colors[0]} and ${colors[1]}';
    return '${colors[0]}, ${colors[1]} and ${colors[2]}';
  }

  static String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  static String _nonBlank(String s) {
    final t = s.trim();
    if (t.isNotEmpty) return t;
    return 'A versatile wardrobe piece. Add details you care about here.';
  }
}
