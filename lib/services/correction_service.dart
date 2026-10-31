import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Stores user corrections (e.g. "AI said shorts → user corrected to skirt")
/// and provides them as few-shot context to future Gemini calls.
class CorrectionService {
  static final CorrectionService _instance = CorrectionService._internal();
  factory CorrectionService() => _instance;
  CorrectionService._internal();

  static const _maxCorrections = 10;
  final List<_Correction> _corrections = [];

  /// Call this when the user saves a changed title in the detail screen.
  /// Only records if the title meaningfully changed.
  Future<void> record({
    required String originalTitle,
    required String correctedTitle,
  }) async {
    final orig = originalTitle.trim();
    final corr = correctedTitle.trim();
    if (orig == corr || orig.isEmpty || corr.isEmpty) return;

    // Avoid duplicate corrections for the same pair
    final alreadyKnown = _corrections.any(
      (c) => c.original.toLowerCase() == orig.toLowerCase(),
    );
    if (alreadyKnown) {
      // Update instead of duplicate
      _corrections.removeWhere(
        (c) => c.original.toLowerCase() == orig.toLowerCase(),
      );
    }

    _corrections.add(_Correction(original: orig, corrected: corr));

    if (_corrections.length > _maxCorrections) {
      _corrections.removeAt(0);
    }

    await _save();
    debugPrint('[Corrections] recorded: "$orig" → "$corr"');
  }

  /// Returns a string ready to inject into the Gemini prompt.
  String get promptContext {
    if (_corrections.isEmpty) return '';
    final lines = _corrections
        .take(6)
        .map((c) => '  - Was "${c.original}" → user corrected to "${c.corrected}"')
        .join('\n');
    return '\nPast user corrections — avoid repeating these mistakes:\n$lines';
  }

  Future<void> load() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/corrections.json');
      if (!await file.exists()) return;
      final data = jsonDecode(await file.readAsString()) as List;
      _corrections
        ..clear()
        ..addAll(data.map((e) => _Correction.fromJson(e as Map<String, dynamic>)));
      debugPrint('[Corrections] loaded ${_corrections.length} corrections');
    } catch (e) {
      debugPrint('[Corrections] load error: $e');
    }
  }

  Future<void> _save() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/corrections.json');
      await file.writeAsString(
        jsonEncode(_corrections.map((c) => c.toJson()).toList()),
      );
    } catch (e) {
      debugPrint('[Corrections] save error: $e');
    }
  }
}

class _Correction {
  final String original;
  final String corrected;

  _Correction({required this.original, required this.corrected});

  Map<String, dynamic> toJson() => {
    'original': original,
    'corrected': corrected,
  };

  factory _Correction.fromJson(Map<String, dynamic> json) => _Correction(
    original: json['original'] as String? ?? '',
    corrected: json['corrected'] as String? ?? '',
  );
}
