import 'dart:io';
import 'package:image/image.dart' as img;

class BackgroundCleanupService {
  /// Returns a NEW processed image file (PNG) next to the original.
  Future<File> cleanup({
    required File input,
    bool enableBorderTrim = true,
    bool enableBackgroundWhiten = true,
  }) async {
    final bytes = await input.readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return input;

    // 1) center crop (reduces background influence)
    final cropped = _centerCrop(decoded, cropFraction: 0.82);

    // 2) optional border trim
    final trimmed = enableBorderTrim ? _trimBorders(cropped) : cropped;

    // 3) optional background whitening (near-white -> pure white)
    final cleaned = enableBackgroundWhiten ? _whitenNearWhiteBackground(trimmed) : trimmed;

    // Save as PNG
    final outPath = input.path.replaceAll(RegExp(r'\.\w+$'), '_clean.png');
    final outFile = File(outPath);
    await outFile.writeAsBytes(img.encodePng(cleaned));
    return outFile;
  }

  img.Image _centerCrop(img.Image src, {double cropFraction = 0.82}) {
    final w = src.width;
    final h = src.height;
    final cw = (w * cropFraction).round();
    final ch = (h * cropFraction).round();
    final x0 = ((w - cw) / 2).round();
    final y0 = ((h - ch) / 2).round();
    return img.copyCrop(src, x: x0, y: y0, width: cw, height: ch);
  }

  img.Image _trimBorders(img.Image src) {
    final c = src.getPixel(0, 0);
    final baseR = c.r.toInt();
    final baseG = c.g.toInt();
    final baseB = c.b.toInt();

    bool isBorderPixel(img.Pixel p) {
      final r = p.r.toInt();
      final g = p.g.toInt();
      final b = p.b.toInt();
      final dr = (r - baseR).abs();
      final dg = (g - baseG).abs();
      final db = (b - baseB).abs();
      return (dr + dg + db) < 45;
    }

    int top = 0;
    for (; top < src.height; top++) {
      int borderCount = 0;
      for (int x = 0; x < src.width; x++) {
        if (isBorderPixel(src.getPixel(x, top))) borderCount++;
      }
      if (borderCount / src.width < 0.92) break;
    }

    int bottom = src.height - 1;
    for (; bottom >= 0; bottom--) {
      int borderCount = 0;
      for (int x = 0; x < src.width; x++) {
        if (isBorderPixel(src.getPixel(x, bottom))) borderCount++;
      }
      if (borderCount / src.width < 0.92) break;
    }

    int left = 0;
    for (; left < src.width; left++) {
      int borderCount = 0;
      for (int y = 0; y < src.height; y++) {
        if (isBorderPixel(src.getPixel(left, y))) borderCount++;
      }
      if (borderCount / src.height < 0.92) break;
    }

    int right = src.width - 1;
    for (; right >= 0; right--) {
      int borderCount = 0;
      for (int y = 0; y < src.height; y++) {
        if (isBorderPixel(src.getPixel(right, y))) borderCount++;
      }
      if (borderCount / src.height < 0.92) break;
    }

    final w = (right - left + 1).clamp(1, src.width);
    final h = (bottom - top + 1).clamp(1, src.height);

    // Avoid over-trimming
    if (w < src.width * 0.55 || h < src.height * 0.55) return src;

    return img.copyCrop(src, x: left, y: top, width: w, height: h);
  }

  img.Image _whitenNearWhiteBackground(img.Image src) {
    final out = img.Image.from(src);

    for (int y = 0; y < out.height; y++) {
      for (int x = 0; x < out.width; x++) {
        final p = out.getPixel(x, y);
        final r = p.r.toInt();
        final g = p.g.toInt();
        final b = p.b.toInt();

        // Near-white threshold
        if (r > 235 && g > 235 && b > 235) {
          p.r = 255;
          p.g = 255;
          p.b = 255;
        }
      }
    }

    return out;
  }
}
