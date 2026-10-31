import 'dart:io';
import 'package:google_mlkit_image_labeling/google_mlkit_image_labeling.dart';

class LabelScore {
  final String label;
  final double confidence;
  const LabelScore(this.label, this.confidence);
}

class MlKitTaggingService {
  Future<List<LabelScore>> detectLabelScores(File imageFile) async {
    final inputImage = InputImage.fromFile(imageFile);

    final labeler = ImageLabeler(
      options: ImageLabelerOptions(confidenceThreshold: 0.20),
    );

    try {
      final labels = await labeler.processImage(inputImage);

      final out = labels
          .map((l) => LabelScore(l.label.toLowerCase().trim(), l.confidence))
          .toList()
        ..sort((a, b) => b.confidence.compareTo(a.confidence));

      // De-dupe by label (keep best confidence)
      final seen = <String>{};
      final deduped = <LabelScore>[];
      for (final x in out) {
        if (seen.add(x.label)) deduped.add(x);
      }

      return deduped.take(15).toList();
    } finally {
      labeler.close();
    }
  }

  /// Keep this if other parts still call detectTags()
  Future<List<String>> detectTags(File imageFile) async {
    final scored = await detectLabelScores(imageFile);
    return scored.map((e) => e.label).toList();
  }
}
