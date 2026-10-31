import 'dart:io';
import 'dart:math';
import 'package:image/image.dart' as img;

class ColorAnalysisSummary {
  final List<String> colors; // names
  final String temperature; // Warm/Cool/Neutral
  final String seasonGuess; // Winter/Summer/Autumn/Spring

  const ColorAnalysisSummary({
    required this.colors,
    required this.temperature,
    required this.seasonGuess,
  });
}

class ColorAnalysisService {
  Future<List<String>> detectColorNames(File imageFile, {int maxColors = 4}) async {
    final s = await analyze(imageFile, maxColors: maxColors);
    return s.colors;
  }

  Future<ColorAnalysisSummary> analyze(File imageFile, {int maxColors = 4}) async {
    final bytes = await imageFile.readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      return const ColorAnalysisSummary(
        colors: [],
        temperature: 'Neutral',
        seasonGuess: 'Summer',
      );
    }

    final cropped = _centerCrop(decoded, cropFraction: 0.78);
    final small = img.copyResize(cropped, width: 120);

    final counts = <int, int>{};
    final hues = <double>[];
    final sats = <double>[];
    final lights = <double>[];

    for (int y = 0; y < small.height; y++) {
      for (int x = 0; x < small.width; x++) {
        final p = small.getPixel(x, y);

        // ✅ Image v4: Pixel object, not int
        final r = p.r.toInt();
        final g = p.g.toInt();
        final b = p.b.toInt();

        final hsl = _rgbToHsl(r, g, b);

        // ignore deep shadows
        if (hsl.l < 0.12) continue;

        // ignore glare whites
        if (hsl.l > 0.97 && hsl.s < 0.15) continue;

        // ignore dark grey noise
        if (hsl.s < 0.10 && hsl.l < 0.35) continue;

        hues.add(hsl.h);
        sats.add(hsl.s);
        lights.add(hsl.l);

        // quantize
        final rq = (r ~/ 24) * 24;
        final gq = (g ~/ 24) * 24;
        final bq = (b ~/ 24) * 24;

        final key = (rq << 16) | (gq << 8) | bq;
        counts[key] = (counts[key] ?? 0) + 1;
      }
    }

    if (counts.isEmpty) {
      return _fallback(decoded, maxColors: maxColors);
    }

    final sorted = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final names = <String>[];
    for (final e in sorted.take(maxColors * 6)) {
      final key = e.key;
      final r = (key >> 16) & 0xFF;
      final g = (key >> 8) & 0xFF;
      final b = key & 0xFF;

      final name = _toBasicColorName(r, g, b);
      if (!names.contains(name)) names.add(name);
      if (names.length >= maxColors) break;
    }

    final temp = _temperatureFrom(hues, names);
    final season = _seasonFrom(names, temp, sats, lights);

    return ColorAnalysisSummary(colors: names, temperature: temp, seasonGuess: season);
  }

  ColorAnalysisSummary _fallback(img.Image decoded, {required int maxColors}) {
    final small = img.copyResize(decoded, width: 120);

    final counts = <int, int>{};
    final hues = <double>[];
    final sats = <double>[];
    final lights = <double>[];

    for (int y = 0; y < small.height; y++) {
      for (int x = 0; x < small.width; x++) {
        final p = small.getPixel(x, y);
        final r = p.r.toInt();
        final g = p.g.toInt();
        final b = p.b.toInt();

        final hsl = _rgbToHsl(r, g, b);
        if (hsl.l < 0.08) continue;

        hues.add(hsl.h);
        sats.add(hsl.s);
        lights.add(hsl.l);

        final rq = (r ~/ 32) * 32;
        final gq = (g ~/ 32) * 32;
        final bq = (b ~/ 32) * 32;

        final key = (rq << 16) | (gq << 8) | bq;
        counts[key] = (counts[key] ?? 0) + 1;
      }
    }

    final sorted = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final names = <String>[];
    for (final e in sorted.take(maxColors * 6)) {
      final key = e.key;
      final r = (key >> 16) & 0xFF;
      final g = (key >> 8) & 0xFF;
      final b = key & 0xFF;

      final name = _toBasicColorName(r, g, b);
      if (!names.contains(name)) names.add(name);
      if (names.length >= maxColors) break;
    }

    final temp = _temperatureFrom(hues, names);
    final season = _seasonFrom(names, temp, sats, lights);

    return ColorAnalysisSummary(colors: names, temperature: temp, seasonGuess: season);
  }

  img.Image _centerCrop(img.Image src, {double cropFraction = 0.78}) {
    final w = src.width;
    final h = src.height;
    final cw = (w * cropFraction).round();
    final ch = (h * cropFraction).round();
    final x0 = ((w - cw) / 2).round();
    final y0 = ((h - ch) / 2).round();
    return img.copyCrop(src, x: x0, y: y0, width: cw, height: ch);
  }

  String _toBasicColorName(int r, int g, int b) {
    final hsl = _rgbToHsl(r, g, b);

    if (hsl.l < 0.12) return 'black';
    if (hsl.l > 0.92 && hsl.s < 0.20) return 'white';
    if (hsl.s < 0.15) return 'grey';

    final h = hsl.h;
    final l = hsl.l;

    if (h >= 15 && h <= 50 && l < 0.55) return 'brown';
    if (h >= 15 && h <= 60 && l >= 0.55) return 'beige';

    if (h < 15 || h >= 345) return 'red';
    if (h < 40) return 'orange';
    if (h < 70) return 'yellow';
    if (h < 160) return 'green';
    if (h < 250) return 'blue';
    if (h < 290) return 'purple';
    if (h < 345) return 'pink';

    return 'unknown';
  }

  String _temperatureFrom(List<double> hues, List<String> names) {
    final neutrals = {'black', 'white', 'grey', 'beige', 'brown'};
    final nonNeutral = names.where((n) => !neutrals.contains(n)).toList();
    if (nonNeutral.isEmpty) return 'Neutral';

    int warm = 0, cool = 0;
    for (final h in hues) {
      if (h < 70 || h >= 330) {
        warm++;
      } else if (h >= 70 && h <= 290) cool++;
    }
    if (warm > cool + 1) return 'Warm';
    if (cool > warm + 1) return 'Cool';
    return 'Neutral';
  }

  String _seasonFrom(List<String> names, String temperature, List<double> sats, List<double> lights) {
    final hasBlack = names.contains('black');
    final hasWhite = names.contains('white');
    final hasBrown = names.contains('brown') || names.contains('beige');
    final highContrast = hasBlack && hasWhite;

    final avgSat = sats.isEmpty ? 0.0 : sats.reduce((a, b) => a + b) / sats.length;
    final avgLight = lights.isEmpty ? 0.0 : lights.reduce((a, b) => a + b) / lights.length;

    if (highContrast || hasBlack) return 'Winter';
    if (temperature == 'Cool') return avgLight >= 0.55 ? 'Summer' : 'Winter';
    if (temperature == 'Warm') {
      if (hasBrown || avgSat < 0.35) return 'Autumn';
      return 'Spring';
    }
    if (hasBrown) return 'Autumn';
    return avgLight >= 0.55 ? 'Summer' : 'Winter';
  }
}

class _Hsl {
  final double h;
  final double s;
  final double l;
  const _Hsl(this.h, this.s, this.l);
}

_Hsl _rgbToHsl(int r, int g, int b) {
  final rf = r / 255.0, gf = g / 255.0, bf = b / 255.0;
  final maxv = max(rf, max(gf, bf));
  final minv = min(rf, min(gf, bf));
  final l = (maxv + minv) / 2.0;

  final d = maxv - minv;
  final s = d == 0 ? 0.0 : d / (1 - (2 * l - 1).abs());

  double h = 0.0;
  if (d != 0) {
    if (maxv == rf) {
      h = 60 * (((gf - bf) / d) % 6);
    } else if (maxv == gf) h = 60 * (((bf - rf) / d) + 2);
    else h = 60 * (((rf - gf) / d) + 4);
  }
  if (h < 0) h += 360;

  return _Hsl(h, s, l);
}
