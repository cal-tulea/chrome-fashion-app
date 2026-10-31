import 'dart:math';
import '../models/clothing_item.dart';
import '../models/outfit.dart';

/// Result of a generation pass.
///
/// [exhausted] is true when every outfit in the closet has already been
/// shown this session and we've fallen back to repeating the best ones.
/// The UI should surface this so the user understands why looks repeat.
class GeneratedOutfits {
  final List<Outfit> outfits;
  final bool exhausted;
  const GeneratedOutfits(this.outfits, {this.exhausted = false});
}

class OutfitGenerator {
  GeneratedOutfits generate({
    required List<ClothingItem> closet,

    String? desiredStyle,
    String? desiredSeason,
    String? colorMode,
    String? desiredOccasion,

    // ✅ NEW WEATHER CONTEXT
    String weatherTemp = 'Any', // Any / Cold / Mild / Hot
    bool isRaining = false,
    bool isWindy = false,

    int maxResults = 12,
    bool allowOuterwear = true,

    Set<String>? dislikedOutfitSignatures,
    Set<String>? shownSignatures,       // outfits already seen this session
    Map<String, int>? itemLikeWeights,
    Set<String>? recentItemIds,
    String Function(Outfit o)? signatureFn,
  }) {
    final tops = closet.where((i) => i.category == ClothingCategory.tops).toList();
    final bottoms = closet.where((i) => i.category == ClothingCategory.bottoms).toList();
    final shoes = closet.where((i) => i.category == ClothingCategory.shoes).toList();
    final outerwear = closet.where((i) => i.category == ClothingCategory.outerwear).toList();

    if (tops.isEmpty || bottoms.isEmpty) return const GeneratedOutfits([]);

    final disliked = dislikedOutfitSignatures ?? <String>{};
    final weights = itemLikeWeights ?? <String, int>{};
    final recent = recentItemIds ?? <String>{};
    final sig = signatureFn ?? _defaultSignature;

    final shoeList = shoes.isEmpty ? <ClothingItem?>[null] : shoes.cast<ClothingItem?>();

    final all = <Outfit>[];
    for (final top in tops) {
      for (final bottom in bottoms) {
        for (final shoe in shoeList) {
          all.add(_makeOutfit(top, bottom, shoe, null));
          if (allowOuterwear && outerwear.isNotEmpty) {
            for (final outer in outerwear) {
              all.add(_makeOutfit(top, bottom, shoe, outer));
            }
          }
        }
      }
    }

    final scored = all.map((o) {
      final score = _scoreOutfit(
        o,
        desiredStyle: desiredStyle,
        desiredSeason: desiredSeason,
        colorMode: colorMode,
        desiredOccasion: desiredOccasion,
        weatherTemp: weatherTemp,
        isRaining: isRaining,
        isWindy: isWindy,
        itemLikeWeights: weights,
        recentItemIds: recent,
      );
      return o.copyWithScore(score);
    }).toList();

    var filtered = scored.where((o) => !disliked.contains(sig(o))).toList();
    if (filtered.isEmpty) filtered = scored;

    // Exclude already-shown outfits so regenerate gives fresh results.
    // If all outfits have been shown, fall back to showing the full pool —
    // and flag it as `exhausted` so the UI can explain the repeat to the user.
    bool exhausted = false;
    if (shownSignatures != null && shownSignatures.isNotEmpty) {
      final fresh = filtered.where((o) => !shownSignatures.contains(sig(o))).toList();
      if (fresh.isNotEmpty) {
        filtered = fresh;
      } else {
        exhausted = true;
      }
    }

    filtered.sort((a, b) => b.score.compareTo(a.score));
    return GeneratedOutfits(_diversify(filtered, maxResults), exhausted: exhausted);
  }

  Outfit _makeOutfit(ClothingItem top, ClothingItem bottom, ClothingItem? shoes, ClothingItem? outerwear) {
    return Outfit(
      top: top,
      bottom: bottom,
      shoes: shoes,
      outerwear: outerwear,
      score: 0,
      reasons: const [],
    );
  }

  int _scoreOutfit(
    Outfit o, {
    required String? desiredStyle,
    required String? desiredSeason,
    required String? colorMode,
    required String? desiredOccasion,
    required String weatherTemp,
    required bool isRaining,
    required bool isWindy,
    required Map<String, int> itemLikeWeights,
    required Set<String> recentItemIds,
  }) {
    final items = o.items;
    int score = 0;

    score += _occasionScore(items, desiredOccasion);
    score += _seasonScore(items, desiredSeason);
    score += _styleScore(items, desiredStyle);
    score += _modeScore(items, colorMode);

    // ✅ WEATHER
    score += _weatherScore(o, weatherTemp: weatherTemp, isRaining: isRaining, isWindy: isWindy);

    // aesthetics
    score += _colorHarmonyScore(items);
    score += _substyleCoherence(items);

    // new fashion-intelligence scoring
    score += _patternScore(items);
    score += _materialScore(items);
    score += _proportionScore(o);
    score += _formalityGapScore(items);

    // learning
    score += _likeBoost(items, itemLikeWeights);
    score -= _recentPenalty(items, recentItemIds);

    return score;
  }

  // --------------------------
  // Pattern clash scoring
  // --------------------------
  int _patternScore(List<ClothingItem> items) {
    final busy = items.where((i) {
      final p = i.analysis.patternLevel.toLowerCase();
      return p != 'solid' && p.isNotEmpty && p != 'unknown';
    }).length;
    if (busy >= 2) return -7; // clash
    if (busy == 0) return 2;  // all-solid = clean
    return 0; // one pattern + solids = fine
  }

  // --------------------------
  // Material compatibility scoring
  // --------------------------
  int _materialScore(List<ClothingItem> items) {
    const tier1   = {'cotton', 'denim', 'jersey', 'linen', 'corduroy', 'fleece', 'nylon', 'spandex', 'synthetic'};
    const tier2   = {'wool', 'knit', 'tweed', 'polyester', 'chino'};
    const tier3   = {'silk', 'satin', 'velvet', 'chiffon', 'lace'};
    const leather = {'leather', 'suede'};
    // Shoe-specific materials are neutral — don't penalise outfit for shoe material
    const neutral = {'canvas', 'mesh', 'rubber', 'fabric'};

    int tier(String m) {
      if (neutral.contains(m))  return -1; // skip from scoring
      if (tier1.contains(m))    return 1;
      if (tier2.contains(m))    return 2;
      if (tier3.contains(m))    return 3;
      if (leather.contains(m))  return 0; // special/versatile
      return -1; // unknown — skip
    }

    final tiers = items
        .map((i) => tier(i.effectiveMaterial.toLowerCase()))
        .where((t) => t != -1)
        .toList();

    if (tiers.length < 2) return 0;

    int score = 0;
    for (int a = 0; a < tiers.length; a++) {
      for (int b = a + 1; b < tiers.length; b++) {
        final ta = tiers[a]; final tb = tiers[b];
        if (ta == 0 || tb == 0) { score += 1; continue; } // leather is versatile
        if (ta == tb)           { score += 2; continue; } // same tier = compatible
        if ((ta - tb).abs() == 1) { score += 0; continue; } // adjacent = neutral
        score -= 4; // tier 1 + tier 3 = formal/casual clash
      }
    }
    return score;
  }

  // --------------------------
  // Proportion rules scoring
  // --------------------------
  int _proportionScore(Outfit o) {
    String fit(ClothingItem i) {
      final b = i.analysis.bodyTypeFit.toLowerCase();
      if (b.contains('oversized')) return 'oversized';
      if (b.contains('wide-leg') || b.contains('wide leg')) return 'wide-leg';
      if (b.contains('slim') || b.contains('skinny')) return 'slim';
      if (b.contains('fitted') || b.contains('cropped')) return 'fitted';
      if (b.contains('flared')) return 'flared';
      if (b.contains('straight')) return 'straight';
      // fallback: check title
      final t = i.title.toLowerCase();
      if (t.contains('oversized')) return 'oversized';
      if (t.contains('wide-leg') || t.contains('wide leg')) return 'wide-leg';
      if (t.contains('slim')) return 'slim';
      if (t.contains('flared')) return 'flared';
      if (t.contains('cropped') || t.contains('crop')) return 'fitted';
      return 'regular';
    }

    final topFit = fit(o.top);
    final botFit = fit(o.bottom);

    if (topFit == 'oversized' && (botFit == 'slim' || botFit == 'skinny' || botFit == 'fitted')) return 5;
    if (botFit == 'wide-leg' && (topFit == 'fitted' || topFit == 'oversized')) return 4;
    if (botFit == 'flared' && (topFit == 'fitted' || topFit == 'slim')) return 4;
    if (topFit == 'oversized' && (botFit == 'wide-leg' || botFit == 'flared')) return -5;
    if (topFit == 'oversized' && botFit == 'oversized') return -4;
    if (topFit == 'regular' && botFit == 'straight') return 2;

    return 0;
  }

  // --------------------------
  // Formality gap scoring
  // --------------------------
  int _formalityGapScore(List<ClothingItem> items) {
    const rank = {'Casual': 0, 'Smart': 1, 'Formal': 2};
    final ranks = items.map((i) => rank[i.effectiveFormality] ?? 0).toList();
    if (ranks.isEmpty) return 0;
    final spread = ranks.reduce(max) - ranks.reduce(min);
    if (spread == 0) return 3;  // all same formality = coherent
    if (spread == 1) return 1;  // one step = intentional smart-casual
    return -3; // two steps gap = mismatch
  }

  // --------------------------
  // Occasion (formality)
  // --------------------------
  int _occasionScore(List<ClothingItem> items, String? desiredOccasion) {
    final occ = (desiredOccasion ?? 'Any').trim();
    if (occ.isEmpty || occ == 'Any') return 0;

    final target = switch (occ) {
      'Work' => 'Smart',
      'Date' => 'Smart',
      'Party' => 'Formal',
      'Travel' => 'Casual',
      'Casual' => 'Casual',
      'Sport' => 'Casual',
      _ => 'Casual',
    };

    int matches = 0;
    for (final i in items) {
      final f = i.effectiveFormality;
      if (f == target) matches++;
      if (target == 'Formal' && f == 'Smart') matches++; // close enough
    }

    if (matches >= (items.length * 0.75).ceil()) return 6;
    if (matches >= (items.length * 0.5).ceil()) return 3;
    return 0;
  }

  // --------------------------
  // Weather scoring
  // --------------------------
  int _weatherScore(
    Outfit o, {
    required String weatherTemp,
    required bool isRaining,
    required bool isWindy,
  }) {
    int score = 0;

    final top = o.top;
    final bottom = o.bottom;
    final shoes = o.shoes;
    final outer = o.outerwear;

    // Temperature: use seasonality override/analysis
    score += _tempFitScore(top, weatherTemp);
    score += _tempFitScore(bottom, weatherTemp);
    if (shoes != null) score += _tempFitScore(shoes, weatherTemp);
    if (outer != null) score += _tempFitScore(outer, weatherTemp);

    // Rain: reward rain-safe tags (especially shoes + outerwear)
    if (isRaining) {
      final shoesRainSafe = shoes != null && _hasWeatherTag(shoes, 'Rain-safe');
      final outerRainSafe = outer != null && _hasWeatherTag(outer, 'Rain-safe');

      if (shoesRainSafe) {
        score += 6;
      } else {
        score -= 4;
      }

      if (outer != null) {
        if (outerRainSafe) {
          score += 3;
        } else {
          score -= 1;
        }
      }
    }

    // Wind: structured outerwear helps
    if (isWindy) {
      if (outer != null) {
        if (outer.effectiveStructure == 'Structured') {
          score += 2;
        } else {
          score -= 1;
        }
      }
    }

    return score;
  }

  int _tempFitScore(ClothingItem item, String weatherTemp) {
    final t = weatherTemp.trim();
    if (t.isEmpty || t == 'Any') return 0;

    final seasonality = item.effectiveSeasonality;

    // simple but effective
    if (t == 'Cold') {
      if (seasonality == 'Winter') return 4;
      if (seasonality == 'Transitional') return 2;
      if (seasonality == 'AllSeason') return 1;
      if (seasonality == 'Summer') return -3;
    }

    if (t == 'Hot') {
      if (seasonality == 'Summer') return 4;
      if (seasonality == 'AllSeason') return 1;
      if (seasonality == 'Transitional') return 0;
      if (seasonality == 'Winter') return -4;
    }

    if (t == 'Mild') {
      if (seasonality == 'Transitional') return 2;
      if (seasonality == 'AllSeason') return 1;
      return 0;
    }

    return 0;
  }

  bool _hasWeatherTag(ClothingItem item, String tag) {
    final v = item.overrides['weatherTags'];
    if (v is List) {
      return v.map((e) => e.toString()).contains(tag);
    }
    return false;
  }

  // --------------------------
  // Existing scoring pieces
  // --------------------------
  int _modeScore(List<ClothingItem> items, String? mode) {
    final m = (mode ?? 'Any').trim();
    if (m.isEmpty || m == 'Any') return 0;

    final colors = _allColors(items);
    if (m == 'Neutral') return _isMostlyNeutral(colors) ? 4 : -1;
    if (m == 'Monochrome') return _isMonochromeFriendly(colors) ? 4 : -1;

    return 0;
  }

  int _seasonScore(List<ClothingItem> items, String? desiredSeason) {
    final season = (desiredSeason ?? 'Any').trim();
    if (season.isEmpty || season == 'Any') return 0;

    // Use effectiveSeasonality (set by _geminiSeason) not colorSeason (always 'Any')
    // 'AllSeason' items are compatible with every season filter
    final matches = items.where((i) {
      final s = i.effectiveSeasonality;
      return s == season || s == 'AllSeason';
    }).length;

    if (matches == items.length) return 6;
    if (matches >= (items.length * 0.6).ceil()) return 4;
    if (matches >= 1) return 2;
    return 0;
  }

  int _styleScore(List<ClothingItem> items, String? desiredStyle) {
    final style = (desiredStyle ?? '').trim();
    if (style.isEmpty || style == 'Any') return 0;

    final matches = items.where((i) => i.analysis.primaryStyle == style).length;
    if (matches == items.length) return 6;
    if (matches >= (items.length * 0.6).ceil()) return 4;
    if (matches >= 1) return 2;
    return 0;
  }

  int _colorHarmonyScore(List<ClothingItem> items) {
    final colors = _allColors(items);
    if (colors.isEmpty) return 1;

    final neutrals = {'black', 'white', 'grey', 'beige', 'brown'};
    final unique = colors.toSet().toList();
    final nonNeutral = unique.where((c) => !neutrals.contains(c)).toList();
    final neutralCount = unique.where(neutrals.contains).length;

    int score = 0;
    if (_isMonochromeFriendly(colors)) score += 6;
    if (_isMostlyNeutral(colors)) score += 5;
    if (neutralCount >= 1 && nonNeutral.length == 1) score += 4;
    if (nonNeutral.length >= 3) score -= 4;

    return score;
  }

  int _substyleCoherence(List<ClothingItem> items) {
    final all = items.expand((i) => i.effectiveSubStyles).map((s) => s.toLowerCase()).toList();
    if (all.isEmpty) return 0;

    final counts = <String, int>{};
    for (final s in all) {
      counts[s] = (counts[s] ?? 0) + 1;
    }
    final best = counts.values.reduce(max);
    if (best >= 3) return 2;
    if (best == 2) return 1;
    return 0;
  }

  int _likeBoost(List<ClothingItem> items, Map<String, int> weights) {
    int boost = 0;
    for (final it in items) {
      final w = weights[it.id] ?? 0;
      boost += min(6, w * 2);
    }
    return boost;
  }

  int _recentPenalty(List<ClothingItem> items, Set<String> recent) {
    int penalty = 0;
    for (final it in items) {
      if (recent.contains(it.id)) penalty += 2;
    }
    return penalty;
  }

  List<String> _allColors(List<ClothingItem> items) =>
      items.expand((i) => i.analysis.colors).map((c) => c.toLowerCase()).toList();

  bool _isMostlyNeutral(List<String> colors) {
    final neutrals = {'black', 'white', 'grey', 'beige', 'brown'};
    if (colors.isEmpty) return true;
    final neutralCount = colors.where(neutrals.contains).length;
    return neutralCount / colors.length >= 0.7;
  }

  bool _isMonochromeFriendly(List<String> colors) {
    if (colors.isEmpty) return true;
    final neutrals = {'black', 'white', 'grey', 'beige', 'brown'};
    final nonNeutral = colors.where((c) => !neutrals.contains(c)).toList();
    if (nonNeutral.isEmpty) return true;
    return nonNeutral.toSet().length <= 1;
  }

  String _defaultSignature(Outfit o) {
    final ids = o.items.map((i) => i.id).toList()..sort();
    return ids.join('|');
  }

  /// Diversifies the sorted outfit list so consecutive cards don't keep
  /// reusing the same "hero" top. Groups outfits by top item, then
  /// round-robins across tops (best-scored top first), preferring outfits
  /// with a bottom that hasn't been used yet in the current round.
  List<Outfit> _diversify(List<Outfit> sorted, int maxResults) {
    if (sorted.isEmpty) return [];

    final byTop = <String, List<Outfit>>{};
    for (final o in sorted) {
      byTop.putIfAbsent(o.top.id, () => []).add(o);
    }

    // Order tops by their best (highest-scoring, since `sorted` is
    // score-descending) outfit first.
    final topOrder = byTop.keys.toList()
      ..sort((a, b) => byTop[b]!.first.score.compareTo(byTop[a]!.first.score));

    final out = <Outfit>[];
    final usedBottom = <String>{};
    int round = 0;

    while (out.length < maxResults) {
      var addedAny = false;

      for (final topId in topOrder) {
        if (out.length >= maxResults) break;
        final group = byTop[topId]!;

        // Prefer an unused outfit from this top with a fresh bottom.
        Outfit? pick;
        for (final o in group) {
          if (out.contains(o)) continue;
          if (round == 0 && usedBottom.contains(o.bottom.id)) continue;
          pick = o;
          break;
        }
        // Fall back to any unused outfit from this top.
        pick ??= group.cast<Outfit?>().firstWhere(
              (o) => !out.contains(o),
              orElse: () => null,
            );

        if (pick != null) {
          out.add(pick);
          usedBottom.add(pick.bottom.id);
          addedAny = true;
        }
      }

      round++;
      if (!addedAny) break; // every outfit has been placed
    }

    return out.take(maxResults).toList();
  }
}

extension OutfitScoreCopy on Outfit {
  Outfit copyWithScore(int score) {
    return Outfit(
      top: top,
      bottom: bottom,
      shoes: shoes,
      outerwear: outerwear,
      score: score,
      reasons: reasons,
    );
  }
}
