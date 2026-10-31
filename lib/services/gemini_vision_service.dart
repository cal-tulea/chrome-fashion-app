import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;

import '../models/clothing_item.dart';
import 'ai_rate_limiter.dart';
import 'correction_service.dart';

/// Gemini Flash vision service — used as primary clothing classifier.
/// generativelanguage.googleapis.com is reachable on all tested networks.
///
/// Model cascade:
///   1. gemini-2.5-flash   — best quality, 10 RPM / 250 RPD free tier
///   2. gemini-2.0-flash-lite — falls back on 429, 30 RPM / 1500 RPD free tier
/// Get a free key at: https://aistudio.google.com/apikey
class GeminiVisionService {
  static const _endpointPrimary =
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent';
  static const _endpointFallback =
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash-lite:generateContent';

  // API key — set this in AppConfig or pass it in.
  // Free key from https://aistudio.google.com/apikey
  static String apiKey = '';

  static bool get hasKey => apiKey.isNotEmpty && !apiKey.startsWith('YOUR_');

  // Compress image before sending (same as HF service).
  static Future<Uint8List> _compress(File imageFile) async {
    final raw = await imageFile.readAsBytes();
    final decoded = img.decodeImage(raw);
    if (decoded == null) return raw;
    const maxSide = 512;
    final resized = decoded.width >= decoded.height
        ? img.copyResize(decoded, width: maxSide)
        : img.copyResize(decoded, height: maxSide);
    return Uint8List.fromList(img.encodeJpg(resized, quality: 85));
  }

  /// Analyses a clothing image and returns structured results.
  /// Returns null if key is missing or both model tiers fail.
  ///
  /// Cascade: gemini-2.5-flash → (429?) → gemini-2.0-flash-lite
  static Future<GeminiClothingResult?> analyseClothing(
    File imageFile, {
    ClothingCategory? hint,
  }) async {
    if (!hasKey) {
      debugPrint('[Gemini] Skipped — no API key');
      return null;
    }
    // Per-user daily rate limit (50 calls/day)
    final allowed = await AIRateLimiter.checkAndIncrement();
    if (!allowed) {
      debugPrint('[Gemini] Daily AI limit reached — skipping call');
      return null;
    }
    try {
      final bytes = await _compress(imageFile);
      final b64 = base64Encode(bytes);
      final prompt = _buildPrompt(hint);

      // ── 1. Try primary model (gemini-2.5-flash) ──────────────────────────
      debugPrint('[Gemini] Trying 2.5-flash, hint=$hint');
      var response = await _postToModel(_endpointPrimary, b64, prompt)
          .timeout(const Duration(seconds: 20));

      // ── 2. If rate-limited, immediately fall back to flash-lite ──────────
      if (response.statusCode == 429) {
        debugPrint('[Gemini] 2.5-flash quota hit (429) → falling back to 2.0-flash-lite');
        response = await _postToModel(_endpointFallback, b64, prompt)
            .timeout(const Duration(seconds: 20));
      }

      debugPrint('[Gemini] status=${response.statusCode}');
      if (response.statusCode != 200) {
        if (kDebugMode) {
          debugPrint('[Gemini] error body=${response.body.substring(0, response.body.length.clamp(0, 300))}');
        }
        return null;
      }

      final data = jsonDecode(response.body);
      final text = (data['candidates']?[0]?['content']?['parts']?[0]?['text'] as String?)?.trim();
      debugPrint('[Gemini] raw response="$text"');
      if (text == null || text.isEmpty) return null;

      return GeminiClothingResult.parse(text, hint: hint);
    } catch (e) {
      debugPrint('[Gemini] exception: $e');
      return null;
    }
  }

  /// Sends a single model request. Returns the raw HTTP response.
  /// thinkingConfig is only included for the primary (2.5-flash) thinking model.
  static Future<http.Response> _postToModel(
    String endpoint,
    String b64,
    String prompt,
  ) {
    final isThinkingModel = endpoint.contains('2.5-flash');
    final genConfig = <String, dynamic>{
      'temperature': 0.1,
      'maxOutputTokens': 100,
    };
    if (isThinkingModel) {
      genConfig['thinkingConfig'] = {'thinkingBudget': 0};
    }

    return http.post(
      Uri.parse('$endpoint?key=$apiKey'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'contents': [
          {
            'parts': [
              {
                'inline_data': {'mime_type': 'image/jpeg', 'data': b64},
              },
              {'text': prompt},
            ],
          }
        ],
        'generationConfig': genConfig,
      }),
    );
  }

  /// Builds the clothing classification prompt with optional category context and corrections.
  static String _buildPrompt(ClothingCategory? hint) {
    final categoryContext = _categoryContext(hint);
    final corrections = CorrectionService().promptContext;
    return '''You are analysing a clothing photo for a wardrobe app.
$categoryContext
Look ONLY at the clothing item, not the background or floor.

Reply with EXACTLY this format (one line, pipe-separated, no extra text):
GARMENT|COLOR|FIT|WASH|PATTERN|MATERIAL

Rules:
- GARMENT: one word from this list only: t-shirt, shirt, hoodie, sweater, cardigan, blouse, tank-top, polo, turtleneck, vest, jeans, shorts, trousers, skirt, leggings, joggers, chinos, jacket, coat, blazer, puffer, boots, sneakers, oxfords, heels, sandals, loafers, mules, flats, belt, bag, hat, scarf
- COLOR: one word (black, white, grey, navy, blue, red, green, yellow, orange, pink, purple, beige, brown, cream, camel, olive, burgundy, teal, coral)
- FIT: one word (slim, regular, straight, wide-leg, oversized, fitted, cropped, skinny, relaxed, flared, high-waist) or "regular" if unclear
- WASH: for denim only write the wash (light-wash, mid-wash, dark-wash, black, raw); for everything else write "none"
- PATTERN: one word (solid, striped, floral, plaid, checked, animal-print, geometric, tie-dye, camo, graphic, ribbed, lace, paisley); use "solid" if plain with no visible pattern
- MATERIAL: one word — if you are not certain, write "unknown". Never guess.
  For clothing: cotton, denim, wool, silk, linen, polyester, velvet, knit, jersey, satin, chiffon, lace, fleece, nylon
  For footwear: canvas, mesh, leather, suede, rubber, synthetic (NEVER use denim, cotton, wool etc. for shoes)
  For accessories: leather, canvas, nylon, fabric
$corrections
Example: shorts|black|regular|none|solid|cotton
Example: jeans|blue|wide-leg|light-wash|solid|denim
Example: skirt|white|regular|none|floral|chiffon
Example: t-shirt|white|regular|none|striped|cotton
Example: sneakers|white|regular|none|solid|canvas
Example: sneakers|black|regular|none|solid|mesh
Example: boots|brown|regular|none|solid|leather
Example: boots|black|regular|none|solid|leather
Example: oxfords|black|regular|none|solid|leather
Example: oxfords|brown|regular|none|solid|leather
Example: loafers|tan|regular|none|solid|leather
Example: loafers|black|regular|none|solid|leather
Example: heels|black|regular|none|solid|leather
Example: flats|nude|regular|none|solid|leather''';
  }

  static String _categoryContext(ClothingCategory? hint) {
    if (hint == null) return '';
    return switch (hint) {
      ClothingCategory.tops =>
        'This image contains a top (shirt, t-shirt, hoodie, sweater, blouse, etc.).',
      ClothingCategory.bottoms =>
        'This image contains a bottom (jeans, shorts, trousers, skirt, leggings, etc.).',
      ClothingCategory.shoes =>
        'This image contains footwear. Identify the EXACT type using these visual cues:\n'
        '- sneakers: athletic/casual, rubber sole, canvas or mesh upper, sporty look\n'
        '- boots: shaft rising above ankle (any style)\n'
        '- oxfords: formal leather shoe with laces, low heel, closed toe, smooth upper — worn to work/office\n'
        '- loafers: leather slip-on, no laces, low heel, formal or smart-casual\n'
        '- heels: elevated heel, typically womens dress shoes\n'
        '- sandals: open toe with straps\n'
        '- flats: very flat sole, no heel, often ballet-style\n'
        'IMPORTANT: if the shoe looks formal, professional, or made of smooth leather → it is oxfords or loafers, NOT sneakers. Only use sneakers for clearly athletic/casual shoes.',
      ClothingCategory.outerwear =>
        'This image contains outerwear (jacket, coat, blazer, puffer, etc.).',
      ClothingCategory.accessories =>
        'This image contains an accessory (bag, belt, hat, scarf, etc.).',
      _ => '',
    };
  }
}

class GeminiClothingResult {
  final String garment;
  final String color;
  final String fit;
  final String wash;
  final String pattern;
  final String material;
  final ClothingCategory category;

  const GeminiClothingResult({
    required this.garment,
    required this.color,
    required this.fit,
    required this.wash,
    required this.pattern,
    required this.material,
    required this.category,
  });

  /// Parses "shorts|black|regular|none" into a result.
  static GeminiClothingResult? parse(String text, {ClothingCategory? hint}) {
    // Strip any markdown / extra lines Gemini sometimes adds
    final clean = text
        .replaceAll('`', '')
        .split('\n')
        .map((l) => l.trim())
        .firstWhere((l) => l.contains('|'), orElse: () => '');

    final parts = clean.split('|');
    if (parts.length < 2) {
      debugPrint('[Gemini] parse failed — expected pipe-separated: "$text"');
      return null;
    }

    final garment  = parts[0].toLowerCase().trim();
    final color    = parts.length > 1 ? parts[1].toLowerCase().trim() : 'neutral';
    final fit      = parts.length > 2 ? parts[2].toLowerCase().trim() : 'regular';
    final wash     = parts.length > 3 ? parts[3].toLowerCase().trim() : 'none';
    final pattern  = parts.length > 4 ? parts[4].toLowerCase().trim() : 'solid';
    final material = parts.length > 5 ? parts[5].toLowerCase().trim() : 'unknown';

    if (garment.isEmpty) return null;

    // Always trust Gemini's garment identification — don't let the ML Kit
    // pre-prediction override what Gemini actually detected in the image.
    final category = _inferCategory(garment);

    debugPrint('[Gemini] parsed → garment="$garment" color="$color" fit="$fit" wash="$wash" pattern="$pattern" material="$material" category=$category');
    return GeminiClothingResult(
      garment: garment,
      color: color,
      fit: fit,
      wash: wash,
      pattern: pattern,
      material: material,
      category: category,
    );
  }

  /// Builds a clean title: "Floral Wide-leg Skirt", "Light Wash Wide-leg Jeans", etc.
  String get title {
    String colorPart;
    final isDenim = garment.contains('jean') || garment.contains('denim');
    if (isDenim && wash != 'none' && wash.isNotEmpty) {
      colorPart = _cap(_denimWashLabel(wash));
    } else {
      colorPart = color != 'neutral' && color.isNotEmpty ? _cap(color) : '';
    }

    // Pattern prefix overrides plain color when patterned
    final hasPattern = pattern.isNotEmpty && pattern != 'solid';
    final patternPart = hasPattern ? _cap(pattern.replaceAll('-', ' ')) : '';

    final fitPart = _displayFit();
    final garmentCap = _cap(garment.replaceAll('-', ' '));

    final titleParts = hasPattern
        ? [patternPart, colorPart, fitPart, garmentCap]
        : [colorPart, fitPart, garmentCap];

    return titleParts.where((p) => p.isNotEmpty).join(' ');
  }

  String _displayFit() {
    if (fit == 'regular' || fit.isEmpty) return '';
    if (fit == 'wide-leg') return 'Wide-leg';
    if (fit == 'straight') return 'Straight';
    if (fit == 'slim') return 'Slim';
    if (fit == 'skinny') return 'Skinny';
    if (fit == 'oversized') return 'Oversized';
    if (fit == 'fitted') return 'Fitted';
    if (fit == 'cropped') return 'Cropped';
    if (fit == 'high-waist') return 'High-waist';
    if (fit == 'relaxed') return 'Relaxed';
    return _cap(fit);
  }

  static String _denimWashLabel(String wash) {
    if (wash.contains('light')) return 'light wash';
    if (wash.contains('mid') || wash.contains('medium')) return 'mid wash';
    if (wash.contains('dark')) return 'dark wash';
    if (wash == 'black') return 'black';
    if (wash == 'raw') return 'raw denim';
    return wash.replaceAll('-', ' ');
  }

  static String _cap(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  static ClothingCategory _inferCategory(String garment) {
    const tops    = ['t-shirt','shirt','hoodie','sweater','cardigan','blouse','tank-top','polo','turtleneck','vest'];
    const bottoms = ['jeans','shorts','trousers','skirt','leggings','joggers','chinos'];
    const shoes   = ['boots','sneakers','oxfords','heels','sandals','loafers','mules','flats'];
    const outer   = ['jacket','coat','blazer','puffer'];
    const acc     = ['belt','bag','hat','scarf'];
    if (tops.contains(garment))    return ClothingCategory.tops;
    if (bottoms.contains(garment)) return ClothingCategory.bottoms;
    if (shoes.contains(garment))   return ClothingCategory.shoes;
    if (outer.contains(garment))   return ClothingCategory.outerwear;
    if (acc.contains(garment))     return ClothingCategory.accessories;
    return ClothingCategory.tops;
  }
}
