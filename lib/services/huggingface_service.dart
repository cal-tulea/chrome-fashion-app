import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;

import '../core/config.dart';
import '../models/clothing_analysis.dart';
import '../models/clothing_item.dart';

class HuggingFaceService {
  static const _captionModel = 'Salesforce/blip-image-captioning-large';
  static const _vqaModel    = 'Salesforce/blip-vqa-capfilt-large';
  static const _clipModel   = 'openai/clip-vit-large-patch14';
  // api-inference.huggingface.co is blocked on some networks.
  // router.huggingface.co is the newer load-balanced endpoint and resolves everywhere.
  static const _apiBase = 'https://router.huggingface.co/hf-inference/models';

  // Resize + JPEG-compress to ≤512px / ≤200 KB.
  // Phone photos can be 10–15 MB; HF free tier rejects payloads above ~1 MB.
  static Future<Uint8List> _compress(File imageFile) async {
    final raw = await imageFile.readAsBytes();
    final decoded = img.decodeImage(raw);
    if (decoded == null) return raw;
    const maxSide = 512;
    final resized = decoded.width >= decoded.height
        ? img.copyResize(decoded, width: maxSide)
        : img.copyResize(decoded, height: maxSide);
    return Uint8List.fromList(img.encodeJpg(resized, quality: 82));
  }

  // BLIP free-form captioning — good for color / texture / description context.
  Future<String?> caption(File imageFile) async {
    if (!AppConfig.hasHuggingFaceToken) return null;
    try {
      final bytes = await _compress(imageFile);
      for (int attempt = 0; attempt < 2; attempt++) {
        final response = await http
            .post(
              Uri.parse('$_apiBase/$_captionModel'),
              headers: {
                'Authorization': 'Bearer ${AppConfig.huggingFaceToken}',
                'Content-Type': 'application/octet-stream',
              },
              body: bytes,
            )
            .timeout(const Duration(seconds: 25));
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          if (data is List && data.isNotEmpty) {
            return (data[0]['generated_text'] as String?)?.trim();
          }
          return null;
        }
        // Model loading — wait and retry once
        if (response.statusCode == 503 && attempt == 0) {
          await Future.delayed(const Duration(seconds: 3));
          continue;
        }
        return null;
      }
    } catch (_) {}
    return null;
  }

  // BLIP VQA — ask a specific question about the image.
  // Much more accurate than free-form captioning for garment type detection.
  Future<String?> vqa(File imageFile, String question) async {
    if (!AppConfig.hasHuggingFaceToken) return null;
    try {
      final bytes = await _compress(imageFile);
      final base64Image = base64Encode(bytes);
      for (int attempt = 0; attempt < 2; attempt++) {
        final response = await http
            .post(
              Uri.parse('$_apiBase/$_vqaModel'),
              headers: {
                'Authorization': 'Bearer ${AppConfig.huggingFaceToken}',
                'Content-Type': 'application/json',
              },
              body: jsonEncode({
                'inputs': {'question': question, 'image': base64Image},
              }),
            )
            .timeout(const Duration(seconds: 25));
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          if (data is List && data.isNotEmpty) {
            return (data[0]['answer'] as String?)?.trim();
          }
          if (data is Map) {
            return (data['answer'] as String?)?.trim();
          }
          return null;
        }
        if (response.statusCode == 503 && attempt == 0) {
          await Future.delayed(const Duration(seconds: 3));
          continue;
        }
        return null;
      }
    } catch (_) {}
    return null;
  }

  // ── CLIP zero-shot image classification ───────────────────────────────────
  Future<String?> classifyGarmentClip(File imageFile, ClothingCategory? hint) async {
    if (!AppConfig.hasHuggingFaceToken) {
      debugPrint('[HF] CLIP skipped — no token');
      return null;
    }
    try {
      final bytes = await _compress(imageFile);
      debugPrint('[HF] CLIP compressed: ${bytes.length} bytes, hint=$hint');
      final b64    = base64Encode(bytes);
      final labels = _clipLabels(hint);
      debugPrint('[HF] CLIP labels: $labels');

      for (int attempt = 0; attempt < 2; attempt++) {
        debugPrint('[HF] CLIP attempt $attempt → POST $_apiBase/$_clipModel');
        final res = await http
            .post(
              Uri.parse('$_apiBase/$_clipModel'),
              headers: {
                'Authorization': 'Bearer ${AppConfig.huggingFaceToken}',
                'Content-Type': 'application/json',
              },
              body: jsonEncode({
                'inputs': b64,
                'parameters': {'candidate_labels': labels},
              }),
            )
            .timeout(const Duration(seconds: 30));

        debugPrint('[HF] CLIP status=${res.statusCode} body=${res.body.length > 200 ? res.body.substring(0, 200) : res.body}');

        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          if (data is List && data.isNotEmpty) {
            final top = (data[0]['label'] as String?)?.toLowerCase().trim();
            debugPrint('[HF] CLIP result → "$top"');
            return top;
          }
          debugPrint('[HF] CLIP 200 but unexpected body: ${res.body}');
          return null;
        }
        if (res.statusCode == 503 && attempt == 0) {
          debugPrint('[HF] CLIP 503 model loading, retrying in 4s…');
          await Future.delayed(const Duration(seconds: 4));
          continue;
        }
        debugPrint('[HF] CLIP failed status=${res.statusCode}');
        return null;
      }
    } catch (e) {
      debugPrint('[HF] CLIP exception: $e');
    }
    return null;
  }

  // Category-specific label lists for CLIP.
  // Smaller focused lists → higher accuracy (fewer wrong choices to score against).
  static List<String> _clipLabels(ClothingCategory? hint) {
    switch (hint) {
      case ClothingCategory.tops:
        return [
          't-shirt', 'shirt', 'hoodie', 'sweatshirt', 'sweater',
          'blouse', 'cardigan', 'tank top', 'polo shirt', 'turtleneck', 'vest',
        ];
      case ClothingCategory.bottoms:
        return ['jeans', 'shorts', 'trousers', 'skirt', 'leggings', 'joggers', 'chinos'];
      case ClothingCategory.shoes:
        return ['sneakers', 'boots', 'high heels', 'sandals', 'loafers', 'trainers', 'flats'];
      case ClothingCategory.outerwear:
        return ['jacket', 'coat', 'blazer', 'puffer jacket', 'trench coat', 'bomber jacket'];
      case ClothingCategory.accessories:
        return ['belt', 'handbag', 'hat', 'scarf', 'watch'];
      default:
        return [
          'jeans', 'shorts', 'trousers', 'skirt', 't-shirt', 'shirt',
          'hoodie', 'sweater', 'boots', 'sneakers', 'jacket', 'coat', 'blazer',
        ];
    }
  }

  // Constrained color question — multiple-choice so BLIP can't pick background colors.
  static String _colorQuestion() {
    return 'What is the color of the clothing item itself (not the background, floor, or hands)? '
           'Choose the single best color from this list: '
           'black, white, grey, navy, blue, red, green, yellow, orange, pink, purple, '
           'beige, brown, cream, camel, khaki, olive, burgundy, teal, coral, light blue, dark blue. '
           'Reply with that one color only.';
  }

  // Constrained multiple-choice VQA question — fallback when CLIP is unavailable.
  static String _garmentQuestion(ClothingCategory? hint) {
    switch (hint) {
      case ClothingCategory.tops:
        return 'What type of clothing is this? '
               'Choose the single best word from this list: '
               't-shirt, shirt, hoodie, sweater, blouse, cardigan, tank top, polo, turtleneck, vest. '
               'Reply with that one word only.';
      case ClothingCategory.bottoms:
        return 'What type of clothing is this? '
               'Choose the single best word from this list: '
               'jeans, shorts, trousers, skirt, leggings, joggers, chinos. '
               'Reply with that one word only.';
      case ClothingCategory.shoes:
        return 'What type of footwear is this? '
               'Choose the single best word from this list: '
               'sneakers, boots, heels, sandals, loafers, trainers, flats. '
               'Reply with that one word only.';
      case ClothingCategory.outerwear:
        return 'What type of outer garment is this? '
               'Choose the single best word from this list: '
               'jacket, coat, blazer, puffer, cardigan, trench. '
               'Reply with that one word only.';
      case ClothingCategory.accessories:
        return 'What type of accessory is this? '
               'Choose the single best word from this list: '
               'bag, belt, hat, scarf, watch, jewelry. '
               'Reply with that one word only.';
      default:
        return 'What type of clothing is this? '
               'Choose the single best word from this list: '
               'jeans, shorts, trousers, skirt, t-shirt, shirt, hoodie, sweater, '
               'boots, sneakers, heels, jacket, coat, blazer. '
               'Reply with that one word only.';
    }
  }

  // Constrained fit question — also category-specific so answers are relevant.
  static String _fitQuestion(ClothingCategory? hint) {
    if (hint == ClothingCategory.bottoms) {
      return 'What is the fit or cut of these bottoms? '
             'Choose the single best answer from this list: '
             'wide-leg, straight, slim, skinny, high-waist, relaxed, regular. '
             'Reply with that answer only.';
    }
    if (hint == ClothingCategory.tops) {
      return 'What is the fit of this top? '
             'Choose the single best word from this list: '
             'oversized, fitted, cropped, regular. '
             'Reply with that one word only.';
    }
    return 'What is the fit of this clothing? '
           'Choose the single best answer from this list: '
           'wide-leg, straight, slim, oversized, fitted, cropped, regular. '
           'Reply with that answer only.';
  }

  // Full analysis pipeline with full debug tracing.
  Future<HFAnalysisResult?> analyzeClothing(File imageFile, {ClothingCategory? hint}) async {
    debugPrint('[HF] analyzeClothing START — hint=$hint hasToken=${AppConfig.hasHuggingFaceToken}');

    final clipFuture    = classifyGarmentClip(imageFile, hint);
    final colorFuture   = vqa(imageFile, _colorQuestion());
    final fitFuture     = vqa(imageFile, _fitQuestion(hint));
    final captionFuture = caption(imageFile);

    String? garmentType = await clipFuture;
    final colorVqa      = await colorFuture;
    final fitVqa        = await fitFuture;
    final captionText   = await captionFuture;

    debugPrint('[HF] results — clip="$garmentType" color="$colorVqa" fit="$fitVqa" caption="$captionText"');

    if (garmentType == null || garmentType.isEmpty) {
      debugPrint('[HF] CLIP failed → falling back to VQA garment question');
      garmentType = await vqa(imageFile, _garmentQuestion(hint));
      debugPrint('[HF] VQA fallback garment="$garmentType"');
    }

    if (garmentType == null && colorVqa == null &&
        (captionText == null || captionText.isEmpty)) {
      debugPrint('[HF] all signals null — returning null (ML Kit fallback will run)');
      return null;
    }

    final result = HFAnalysisResult.fromCaption(
      captionText ?? garmentType ?? '',
      hint: hint,
      garmentTypeOverride: garmentType,
      colorOverride: colorVqa,
      fitOverride: fitVqa,
    );
    debugPrint('[HF] final → title="${result.title}" category=${result.category}');
    return result;
  }
}

class HFAnalysisResult {
  final String caption;
  final String title;
  final String description;
  final ClothingCategory category;
  final List<String> colors;
  final String formality;
  final String structure;
  final String seasonality;
  final String primaryStyle;
  final List<String> subStyles;
  final List<String> stylistPairings;

  const HFAnalysisResult({
    required this.caption,
    required this.title,
    required this.description,
    required this.category,
    required this.colors,
    required this.formality,
    required this.structure,
    required this.seasonality,
    required this.primaryStyle,
    required this.subStyles,
    required this.stylistPairings,
  });

  factory HFAnalysisResult.fromCaption(
    String caption, {
    ClothingCategory? hint,
    String? garmentTypeOverride,
    String? colorOverride,
    String? fitOverride,
  }) {
    final lower = caption.toLowerCase();

    // ── Garment type — VQA wins over free-form caption extraction ─────────────
    String garmentType = (garmentTypeOverride != null && garmentTypeOverride.isNotEmpty)
        ? _normaliseGarmentType(garmentTypeOverride)
        : _extractGarmentType(lower);

    // ── Category cross-check — reject VQA answer if it contradicts the hint ───
    // E.g. VQA says "jeans" for a shirt, or "shorts" for a shoe — discard it.
    if (hint != null && hint != ClothingCategory.all &&
        garmentType.isNotEmpty && garmentType != 'clothing item' &&
        !_garmentMatchesCategory(garmentType, hint)) {
      // VQA was wrong — try extracting from caption text, then fall back to generic
      final fromCap = _extractGarmentType(lower);
      garmentType = _garmentMatchesCategory(fromCap, hint)
          ? fromCap
          : _defaultGarmentForCategory(hint);
    }

    // ── Color — VQA colour wins over caption scanning ─────────────────────────
    // Caption colour scanning is unreliable because it picks up background colours.
    List<String> colors;
    if (colorOverride != null && colorOverride.isNotEmpty) {
      final c = colorOverride.toLowerCase().trim();
      colors = [c];
    } else {
      const colorKeywords = [
        'black', 'white', 'grey', 'gray', 'navy', 'blue', 'red', 'green',
        'yellow', 'orange', 'pink', 'purple', 'beige', 'brown', 'cream',
        'ivory', 'camel', 'khaki', 'olive', 'burgundy', 'teal', 'coral',
        'indigo', 'tan', 'rust', 'terracotta', 'cobalt', 'sage',
      ];
      colors = colorKeywords.where((c) => lower.contains(c)).toList();
      if (colors.isEmpty) colors.add('neutral');
    }

    // ── Category ──────────────────────────────────────────────────────────────
    ClothingCategory category;
    if (hint != null && hint != ClothingCategory.all) {
      category = hint;
    } else {
      category = _inferCategory(garmentType.isNotEmpty ? garmentType : lower);
    }

    // ── Fit / cut descriptor (e.g. "wide-leg", "slim", "oversized") ──────────
    final fit = _normaliseFit(fitOverride);

    // ── Title — "{colour} {fit} {garmentType}" ────────────────────────────────
    // If the garment VQA already includes the fit (e.g. "wide-leg jeans"),
    // don't double-append it.
    final garmentAlreadyHasFit = fit.isNotEmpty && garmentType.contains(fit);
    final fitPart = (fit.isNotEmpty && !garmentAlreadyHasFit) ? '$fit ' : '';

    // Denim: prefer wash language in the title ("Light wash" > "light blue")
    final rawColor = (colors.isNotEmpty && colors.first != 'neutral') ? colors.first : '';
    final isDenim = garmentType.contains('jeans') || garmentType.contains('denim');
    final colorLabel = isDenim ? _washLabel(rawColor) : rawColor;
    final colorPart  = colorLabel.isNotEmpty ? '${_capitalise(colorLabel)} ' : '';

    final title = '$colorPart$fitPart${_capitalise(garmentType)}';

    // ── Formality ─────────────────────────────────────────────────────────────
    final formality = _inferFormality(lower);

    // ── Structure ─────────────────────────────────────────────────────────────
    final structure = _inferStructure(lower);

    // ── Seasonality ───────────────────────────────────────────────────────────
    final seasonality = _inferSeasonality(lower);

    // ── Primary style ─────────────────────────────────────────────────────────
    final primaryStyle = _inferPrimaryStyle(lower, formality);

    // ── Sub-styles ────────────────────────────────────────────────────────────
    final subStyles = _inferSubStyles(lower);

    // ── Stylist pairings ──────────────────────────────────────────────────────
    final pairings = _stylistPairings(category, formality, primaryStyle, colors);

    // ── Description ───────────────────────────────────────────────────────────
    final description = buildRichDescription(
      garmentType: garmentType,
      color: rawColor,
      fit: fit,
      category: category,
      formality: formality,
      structure: structure,
      seasonality: seasonality,
    );

    return HFAnalysisResult(
      caption: caption,
      title: title,
      description: description,
      category: category,
      colors: colors,
      formality: formality,
      structure: structure,
      seasonality: seasonality,
      primaryStyle: primaryStyle,
      subStyles: subStyles,
      stylistPairings: pairings,
    );
  }

  // Public static helper so clothing detail screen can call without a full HF result
  static List<String> stylistPairingsFor(dynamic item) {
    // item is ClothingItem but we avoid the import by using dynamic
    try {
      final formality = item.analysis?.formality as String? ?? 'Casual';
      final style = item.analysis?.primaryStyle as String? ?? 'Everyday';
      final colors = List<String>.from(item.analysis?.colors as List? ?? []);
      final category = item.category;
      return _stylistPairings(category, formality, style, colors);
    } catch (_) {
      return ['Neutral bottoms or a simple top to complement this piece'];
    }
  }

  // Converts this HF result into a ClothingAnalysis
  ClothingAnalysis toAnalysis() {
    return ClothingAnalysis(
      primaryStyle: primaryStyle,
      subStyles: subStyles,
      colorSeason: 'Any',
      colors: colors,
      temperature: colors.any((c) => ['red', 'orange', 'yellow', 'coral', 'burgundy', 'camel'].contains(c))
          ? 'Warm'
          : colors.any((c) => ['blue', 'navy', 'teal', 'purple', 'grey', 'gray'].contains(c))
              ? 'Cool'
              : 'Neutral',
      contrastLevel: colors.contains('black') || colors.contains('white') ? 'High' : 'Medium',
      patternLevel: lowerContainsPattern(caption.toLowerCase()) ? 'Subtle' : 'Solid',
      structure: structure,
      formality: formality,
      seasonality: seasonality,
      bodyTypeFit: 'Standard fit',
      description: description,
      history: 'Added via Chromé AI analysis.',
    );
  }

  static bool lowerContainsPattern(String lower) {
    return lower.contains('stripe') ||
        lower.contains('check') ||
        lower.contains('plaid') ||
        lower.contains('floral') ||
        lower.contains('print') ||
        lower.contains('pattern');
  }

  // ── Private helpers ────────────────────────────────────────────────────────

  static ClothingCategory _inferCategory(String lower) {
    const topKeywords = ['shirt', 't-shirt', 'tshirt', 'top', 'blouse', 'sweater', 'jumper',
        'hoodie', 'sweatshirt', 'jersey', 'tank', 'vest', 'crop', 'turtleneck', 'polo', 'tunic'];
    const bottomKeywords = ['jeans', 'pants', 'trousers', 'shorts', 'skirt', 'leggings',
        'chinos', 'joggers', 'cargo', 'culottes'];
    const shoeKeywords = ['shoe', 'shoes', 'sneaker', 'sneakers', 'boot', 'boots', 'heel',
        'heels', 'loafer', 'loafers', 'sandal', 'sandals', 'trainer', 'trainers', 'slipper'];
    const outerwearKeywords = ['jacket', 'coat', 'blazer', 'cardigan', 'trench', 'parka',
        'raincoat', 'windbreaker', 'puffer', 'bomber', 'cape', 'overcoat'];
    const dressKeywords = ['dress', 'gown', 'romper', 'jumpsuit', 'playsuit', 'kaftan'];

    if (shoeKeywords.any((k) => lower.contains(k))) return ClothingCategory.shoes;
    if (outerwearKeywords.any((k) => lower.contains(k))) return ClothingCategory.outerwear;
    if (dressKeywords.any((k) => lower.contains(k))) return ClothingCategory.tops;
    if (bottomKeywords.any((k) => lower.contains(k))) return ClothingCategory.bottoms;
    if (topKeywords.any((k) => lower.contains(k))) return ClothingCategory.tops;
    return ClothingCategory.tops;
  }

  static String _extractGarmentType(String lower) {
    // Check compound/specific types first (longer matches win)
    if (lower.contains('wide leg') || lower.contains('wide-leg')) return 'wide-leg jeans';
    if (lower.contains('straight leg') || lower.contains('straight-leg')) return 'straight-leg jeans';
    if (lower.contains('slim leg') || lower.contains('slim-leg')) return 'slim jeans';
    if (lower.contains('high waist') || lower.contains('high-waist')) {
      if (lower.contains('jean') || lower.contains('denim')) return 'high-waist jeans';
      if (lower.contains('skirt')) return 'high-waist skirt';
      if (lower.contains('trouser') || lower.contains('pant')) return 'high-waist trousers';
    }
    if (lower.contains('trench coat')) return 'trench coat';
    if (lower.contains('tank top')) return 'tank top';
    if (lower.contains('crop top')) return 'crop top';

    const types = [
      't-shirt', 'tshirt', 'shirt', 'blouse', 'sweater', 'jumper', 'hoodie', 'sweatshirt',
      'vest', 'polo', 'turtleneck', 'cardigan',
      'jeans', 'denim', 'trousers', 'pants', 'shorts', 'skirt', 'leggings', 'chinos', 'joggers', 'culottes',
      'dress', 'jumpsuit', 'romper', 'gown',
      'jacket', 'coat', 'blazer', 'parka', 'bomber', 'puffer', 'windbreaker',
      'sneakers', 'trainers', 'boots', 'heels', 'loafers', 'sandals', 'shoes',
    ];
    for (final t in types) {
      if (lower.contains(t)) {
        // 'denim' → display as 'jeans'
        if (t == 'denim') return 'jeans';
        // 'pants' → display as 'trousers'
        if (t == 'pants') return 'trousers';
        return t;
      }
    }
    return 'clothing item';
  }

  static String _inferFormality(String lower) {
    const formalKeywords = ['blazer', 'suit', 'formal', 'dress shirt', 'gown', 'heels', 'trousers'];
    const smartKeywords = ['chinos', 'polo', 'loafer', 'smart', 'button-up', 'button up', 'blouse'];
    if (formalKeywords.any((k) => lower.contains(k))) return 'Formal';
    if (smartKeywords.any((k) => lower.contains(k))) return 'Smart';
    return 'Casual';
  }

  static String _inferStructure(String lower) {
    const structuredKeywords = ['blazer', 'structured', 'tailored', 'stiff', 'rigid', 'denim', 'leather'];
    return structuredKeywords.any((k) => lower.contains(k)) ? 'Structured' : 'Soft';
  }

  static String _inferSeasonality(String lower) {
    const warmKeywords = ['linen', 'cotton', 'crop', 'shorts', 'sleeveless', 'tank', 'sandal'];
    const coldKeywords = ['wool', 'knit', 'fleece', 'puffer', 'parka', 'coat', 'thermal', 'cashmere'];
    if (coldKeywords.any((k) => lower.contains(k))) return 'Winter';
    if (warmKeywords.any((k) => lower.contains(k))) return 'Summer';
    if (lower.contains('layer') || lower.contains('jacket') || lower.contains('cardigan')) return 'Transitional';
    return 'AllSeason';
  }

  static String _inferPrimaryStyle(String lower, String formality) {
    if (lower.contains('sport') || lower.contains('gym') || lower.contains('athletic') ||
        lower.contains('jogger') || lower.contains('hoodie') || lower.contains('legging')) {
      return 'Athleisure';
    }
    if (lower.contains('leather') || lower.contains('graphic') || lower.contains('cargo') ||
        lower.contains('oversized') || lower.contains('streetwear')) {
      return 'Streetwear';
    }
    if (lower.contains('floral') || lower.contains('lace') || lower.contains('ruffle') ||
        lower.contains('feminine') || lower.contains('romantic')) {
      return 'Romantic';
    }
    if (formality == 'Formal' || lower.contains('classic') || lower.contains('tailored') ||
        lower.contains('blazer') || lower.contains('trousers')) {
      return 'Classic';
    }
    if (lower.contains('minimal') || lower.contains('simple') || lower.contains('clean') ||
        lower.contains('plain')) {
      return 'Minimal';
    }
    return 'Everyday';
  }

  static List<String> _inferSubStyles(String lower) {
    final subs = <String>[];
    if (lower.contains('knit') || lower.contains('wool') || lower.contains('cashmere')) subs.add('Knit');
    if (lower.contains('denim') || lower.contains('jeans')) subs.add('Denim');
    if (lower.contains('leather')) subs.add('Leather');
    if (lower.contains('tailored') || lower.contains('blazer') || lower.contains('suit')) subs.add('Tailored');
    if (lower.contains('relaxed') || lower.contains('oversized') || lower.contains('loose')) subs.add('Relaxed');
    if (lower.contains('sport') || lower.contains('athletic')) subs.add('Sporty');
    if (lower.contains('vintage') || lower.contains('retro')) subs.add('Vintage');
    return subs;
  }

  static List<String> _stylistPairings(
    ClothingCategory category,
    String formality,
    String style,
    List<String> colors,
  ) {
    final isNeutral = colors.isEmpty ||
        colors.every((c) => ['black', 'white', 'grey', 'gray', 'beige', 'cream', 'ivory', 'camel'].contains(c));

    switch (category) {
      case ClothingCategory.tops:
        if (formality == 'Formal') {
          return ['Tailored trousers', 'Straight-leg dress pants', 'Leather loafers or Oxford shoes'];
        }
        if (formality == 'Smart') {
          return ['High-waist trousers', 'Dark slim jeans', 'Ankle boots or clean leather sneakers'];
        }
        if (isNeutral) {
          return ['Any colour bottoms — this pairs with everything', 'Straight or wide-leg jeans', 'Chunky sneakers or strappy sandals'];
        }
        return ['Neutral bottoms to let this piece speak', 'Black or white jeans', 'Simple clean sneakers'];

      case ClothingCategory.bottoms:
        if (formality == 'Formal') {
          return ['Tucked-in button-up shirt', 'Fitted blazer', 'Oxford shoes or heels'];
        }
        if (isNeutral) {
          return ['Any top — neutral bottoms are the base of every outfit', 'Graphic tee or structured blouse', 'Sneakers or boots to match the mood'];
        }
        return ['Simple white or black top', 'Fitted tucked-in tee', 'Monochrome shoes to elongate'];

      case ClothingCategory.shoes:
        if (formality == 'Formal') {
          return ['Tailored trousers with a slight break', 'Midi or maxi dress', 'Structured blazer'];
        }
        if (style == 'Athleisure') {
          return ['Joggers or track pants', 'Oversized hoodie or fitted tee', 'Athletic co-ord sets'];
        }
        return ['Straight-leg or wide-leg jeans', 'Midi skirt for a contrast', 'Relaxed trousers'];

      case ClothingCategory.outerwear:
        if (formality == 'Formal') {
          return ['Tailored suit underneath', 'Slim trousers and a turtleneck', 'Loafers or pointed-toe heels'];
        }
        return ['Simple fitted tee + straight jeans', 'Monochrome outfit underneath to let the layer be the statement', 'Ankle boots or chunky sneakers'];

      default:
        return ['Build around this piece as a neutral base'];
    }
  }

  // Normalises a VQA fit answer into a short canonical label.
  // Handles both single-word constrained answers ("slim", "straight") and
  // multi-word legacy answers ("slim fit", "wide leg").
  // Order matters — more specific checks must come before substring checks.
  static String _normaliseFit(String? fitVqa) {
    if (fitVqa == null || fitVqa.isEmpty) return '';
    final lower = fitVqa.toLowerCase().trim();

    // "regular / regular fit" → omit from title (uninformative)
    if (lower == 'regular' || lower.startsWith('regular ')) return '';

    // Compound fit names
    if (lower.contains('wide') && lower.contains('leg')) return 'wide-leg';
    if (lower == 'wide-leg' || lower == 'wide leg') return 'wide-leg';
    if (lower.contains('straight') && lower.contains('leg')) return 'straight-leg';
    if (lower == 'straight' || lower == 'straight-leg') return 'straight-leg';
    if (lower.contains('high') && lower.contains('waist')) return 'high-waist';
    if (lower == 'high-waist' || lower == 'high waist') return 'high-waist';
    if (lower.contains('bootcut') || lower.contains('boot cut')) return 'bootcut';
    if (lower.contains('flared') || lower.contains('flare')) return 'flared';

    // Simple single-word fits
    if (lower.contains('skinny')) return 'skinny';
    if (lower.contains('slim')) return 'slim';
    if (lower.contains('oversized')) return 'oversized';
    if (lower.contains('relaxed') || lower.contains('loose')) return 'relaxed';
    if (lower.contains('cropped') || lower.contains('crop')) return 'cropped';
    // "fitted" must come before generic "fit" check
    if (lower.contains('fitted')) return 'fitted';
    // Bare "fit" on its own is noise — skip it
    if (lower == 'fit') return '';

    // Short multi-word answer not caught above — use as-is if sensible
    final words = lower.split(RegExp(r'\s+'));
    if (words.length <= 2 &&
        !lower.contains('n/a') &&
        !lower.contains('unknown') &&
        !lower.contains('none') &&
        !lower.contains('no ')) {
      return lower;
    }
    return '';
  }

  // Converts a raw colour string to wash language when the garment is denim.
  // "light blue"  → "light wash"
  // "dark indigo" → "dark wash"
  // "black"       → "black"
  // Anything else passes through unchanged.
  static String _washLabel(String color) {
    final c = color.toLowerCase().trim();
    if (c.isEmpty || c == 'neutral') return '';
    if (c.contains('light') || c.contains('pale') || c.contains('sky')) return 'light wash';
    if (c.contains('medium') || c.contains('mid')) return 'mid wash';
    if (c.contains('dark') || c.contains('deep') || c.contains('indigo') ||
        c.contains('navy') || c.contains('midnight')) {
      return 'dark wash';
    }
    if (c.contains('raw') || c.contains('rigid') || c.contains('selvedge')) return 'raw denim';
    if (c == 'black' || c.contains('black')) return 'black';
    if (c.contains('white') || c.contains('cream') || c.contains('ecru')) return 'bleached';
    if (c.contains('grey') || c.contains('gray')) return 'grey wash';
    if (c.contains('blue')) return 'mid wash'; // generic "blue" → mid wash
    return c; // not a standard wash colour — return as-is
  }

  static String buildRichDescription({
    required String garmentType,
    required String color,
    required String fit,
    required ClothingCategory category,
    required String formality,
    required String structure,
    required String seasonality,
  }) {
    final g = garmentType.toLowerCase();
    final c = color == 'neutral' ? '' : '$color ';
    final season = seasonality == 'AllSeason' ? 'year-round' : seasonality.toLowerCase();
    final fml = formality.toLowerCase();
    final fitLower = fit.toLowerCase();

    // Denim / jeans — use fit param first, then fall back to garmentType embedded fit
    final isWideleg  = fitLower.contains('wide')     || g.contains('wide-leg') || g.contains('wide leg');
    final isStraight = fitLower.contains('straight') || g.contains('straight');
    final isSlim     = fitLower.contains('slim')     || fitLower.contains('skinny') || g.contains('slim');
    final isHighWaist = fitLower.contains('high-waist') || fitLower.contains('high waist') || g.contains('high-waist');
    if ((g.contains('jeans') || g.contains('denim')) && isWideleg) {
      final washPhrase = c.isNotEmpty ? 'in ${c}denim' : 'in denim';
      return 'A wide-leg silhouette $washPhrase. '
          'The relaxed, floor-grazing cut balances out fitted tops and creates an effortlessly '
          'elongated look — pair with a tucked-in tee or structured blazer.';
    }
    if ((g.contains('jeans') || g.contains('denim')) && isStraight) {
      final washPhrase = c.isNotEmpty ? 'in ${c}denim' : 'in denim';
      return 'A straight-leg cut $washPhrase — '
          'a clean, versatile silhouette that works from casual to smart-casual. '
          'Pairs with almost anything from oversized knitwear to a crisp shirt.';
    }
    if ((g.contains('jeans') || g.contains('denim')) && isSlim) {
      return 'Slim-cut ${c}jeans with a streamlined silhouette. '
          'Easy to dress up with a blazer or keep casual with a clean tee.';
    }
    if ((g.contains('jeans') || g.contains('denim')) && isHighWaist) {
      return 'High-waist ${c}jeans with a flattering, elongating cut. '
          'Tuck in a fitted top to emphasise the waist, or wear with a relaxed knit.';
    }
    if (g.contains('jeans') || g.contains('denim')) {
      final washPhrase = c.isNotEmpty ? c : '';
      return 'A ${washPhrase}denim piece — a wardrobe staple that reads $fml '
          'and suits $season wear. Style with a simple top and let the fit do the work.';
    }

    // Shorts
    if (g.contains('shorts')) {
      return '${_capitalise(c)}shorts with a relaxed cut. '
          'Light and easy to style — pair with a fitted tee or loose shirt for a casual, '
          'warm-weather look.';
    }

    // Trousers / skirt
    if (g.contains('trouser') || g.contains('pant')) {
      return '${_capitalise(c)}trousers with a $fml finish. '
          'A clean, tailored bottom that grounds any look — from a simple knit to a structured top.';
    }
    if (g.contains('skirt')) {
      return 'A ${c}skirt with a $fml silhouette. '
          'Style with a fitted top tucked in, or a relaxed knit for a more casual feel.';
    }

    // Tops
    if (g.contains('hoodie') || g.contains('sweatshirt')) {
      return 'An oversized ${c}hoodie — relaxed and comfortable. '
          'Layer over a long-sleeve tee or wear alone with straight-leg trousers for an effortless look.';
    }
    if (g.contains('sweater') || g.contains('knit') || g.contains('cardigan')) {
      return 'A ${c}knit piece that adds texture and warmth. '
          'Works layered over a shirt for depth, or alone with tailored bottoms for a polished casual look.';
    }
    if (g.contains('shirt') || g.contains('blouse')) {
      return 'A $c$g — versatile and $fml. '
          'Wear tucked in for a polished look or untucked and relaxed for casual styling.';
    }
    if (g.contains('t-shirt') || g.contains('tee')) {
      return 'A clean ${c}tee — the foundation of a great casual outfit. '
          'Layer under a jacket or wear alone with well-fitting jeans or trousers.';
    }

    // Outerwear
    if (g.contains('blazer')) {
      return 'A ${c}blazer with a structured, $fml finish. '
          'Worn over a tee for smart-casual or a dress shirt for formal — '
          'the single piece that elevates almost any outfit.';
    }
    if (g.contains('coat') || g.contains('trench')) {
      return 'A $c$g — a statement outer layer that finishes any look. '
          'Keep the outfit underneath simple so the silhouette does the work.';
    }
    if (g.contains('jacket')) {
      return 'A ${c}jacket — versatile layering piece for $season. '
          'Pairs with jeans for casual, or trousers for a sharper look.';
    }

    // Shoes
    if (g.contains('boots')) {
      return '${_capitalise(c)}boots — grounding and versatile. '
          'Ankle-length pairs with jeans and midi skirts; knee-high works best with dresses and straight trousers.';
    }
    if (g.contains('sneakers') || g.contains('trainers')) {
      return '${_capitalise(c)}sneakers — the casual anchor of any outfit. '
          'Best with relaxed or mid-weight bottoms; avoid very formal pieces.';
    }
    if (g.contains('heels')) {
      return '${_capitalise(c)}heels that instantly elevate the outfit. '
          'Pair with tailored trousers, a midi skirt, or a fitted dress.';
    }

    // Generic fallback
    return 'A $fml $c${g == 'clothing item' ? category.name : g} suited for $season wear. '
        'Style with pieces in a complementary palette and let the proportions balance.';
  }

  // Returns true if the garment type string is consistent with the category.
  // Used to reject VQA answers that are completely off-category (e.g., "shorts" for a top).
  static bool _garmentMatchesCategory(String garmentType, ClothingCategory category) {
    final g = garmentType.toLowerCase();
    const topWords    = ['shirt', 't-shirt', 'tee', 'top', 'blouse', 'sweater', 'hoodie',
                         'sweatshirt', 'cardigan', 'polo', 'turtleneck', 'vest', 'tank',
                         'crop', 'jumper', 'knit', 'pullover'];
    const bottomWords = ['jeans', 'shorts', 'trouser', 'pant', 'skirt', 'legging', 'chino',
                         'jogger', 'culotte', 'denim'];
    const shoeWords   = ['shoe', 'sneaker', 'boot', 'heel', 'loafer', 'sandal', 'trainer',
                         'slipper', 'mule'];
    const outerWords  = ['jacket', 'coat', 'blazer', 'trench', 'parka', 'puffer', 'bomber',
                         'cape', 'windbreaker', 'overcoat', 'anorak', 'cardigan'];
    const accWords    = ['bag', 'belt', 'hat', 'scarf', 'watch', 'necklace', 'ring',
                         'bracelet', 'purse', 'cap', 'beret'];

    return switch (category) {
      ClothingCategory.tops        => topWords.any((w) => g.contains(w)),
      ClothingCategory.bottoms     => bottomWords.any((w) => g.contains(w)),
      ClothingCategory.shoes       => shoeWords.any((w) => g.contains(w)),
      ClothingCategory.outerwear   => outerWords.any((w) => g.contains(w)),
      ClothingCategory.accessories => accWords.any((w) => g.contains(w)),
      _                            => true,
    };
  }

  // Returns a safe generic garment label for a category when VQA fails.
  static String _defaultGarmentForCategory(ClothingCategory category) {
    return switch (category) {
      ClothingCategory.tops        => 'top',
      ClothingCategory.bottoms     => 'bottoms',
      ClothingCategory.shoes       => 'shoes',
      ClothingCategory.outerwear   => 'jacket',
      ClothingCategory.accessories => 'accessory',
      _                            => 'clothing item',
    };
  }

  // Cleans up a VQA garment-type answer into a canonical short label.
  // VQA may return full sentences or minor misspellings — normalise them.
  static String _normaliseGarmentType(String vqaAnswer) {
    final lower = vqaAnswer.toLowerCase().trim();

    // Compound types first (most specific)
    if ((lower.contains('wide') && lower.contains('leg')) || lower.contains('wide-leg')) {
      return 'wide-leg jeans';
    }
    if ((lower.contains('straight') && lower.contains('leg')) || lower.contains('straight-leg')) {
      return 'straight-leg jeans';
    }
    if ((lower.contains('slim') && lower.contains('leg')) || lower.contains('slim-leg')) {
      return 'slim jeans';
    }
    if (lower.contains('high waist') || lower.contains('high-waist')) {
      if (lower.contains('jean') || lower.contains('denim')) return 'high-waist jeans';
      if (lower.contains('skirt')) return 'high-waist skirt';
      if (lower.contains('trouser') || lower.contains('pant')) return 'high-waist trousers';
    }
    if (lower.contains('trench')) return 'trench coat';
    if (lower.contains('crop top') || lower.contains('crop t')) return 'crop top';
    if (lower.contains('tank top') || lower.contains('tank t')) return 'tank top';
    if (lower.contains('t-shirt') || lower.contains('tshirt') || lower.contains('t shirt')) return 't-shirt';

    // Simple canonical labels
    const canonical = [
      'jeans', 'shorts', 'trousers', 'skirt', 'leggings', 'culottes', 'chinos', 'joggers',
      'shirt', 'blouse', 'hoodie', 'sweatshirt', 'sweater', 'cardigan', 'jumper', 'polo', 'vest', 'turtleneck',
      'dress', 'jumpsuit', 'romper', 'gown',
      'jacket', 'coat', 'blazer', 'puffer', 'parka', 'bomber', 'windbreaker',
      'sneakers', 'trainers', 'boots', 'heels', 'loafers', 'sandals', 'shoes',
    ];
    for (final c in canonical) {
      if (lower.contains(c)) return c;
    }
    // denim → jeans, pants → trousers
    if (lower.contains('denim')) return 'jeans';
    if (lower.contains('pant')) return 'trousers';

    // Return the answer as-is if it's already short (likely a good answer)
    if (lower.split(' ').length <= 3) return lower;
    return 'clothing item';
  }

  static String _capitalise(String s) {
    if (s.isEmpty) return s;
    return s[0].toUpperCase() + s.substring(1);
  }
}
