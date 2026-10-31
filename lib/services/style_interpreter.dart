class StyleInterpreter {
  static String inferPrimaryStyle(List<String> labels) {
    if (labels.any((l) => l.contains('bohemian'))) return 'Boho Chic';
    if (labels.any((l) => l.contains('formal'))) return 'Classic';
    if (labels.any((l) => l.contains('street'))) return 'Streetwear';
    if (labels.any((l) => l.contains('sport'))) return 'Athleisure';
    return 'Casual';
  }

  static List<String> inferSubStyles(List<String> labels) {
    final styles = <String>[];

    if (labels.any((l) => l.contains('minimal'))) styles.add('Minimal');
    if (labels.any((l) => l.contains('vintage'))) styles.add('Vintage');
    if (labels.any((l) => l.contains('oversized'))) styles.add('Oversized');
    if (labels.any((l) => l.contains('elegant'))) styles.add('Elegant');

    return styles.isEmpty ? ['Everyday'] : styles;
  }

  static String inferColorSeason(List<String> labels) {
    if (labels.any((l) => l.contains('black') || l.contains('grey'))) {
      return 'Winter';
    }
    if (labels.any((l) => l.contains('beige') || l.contains('cream'))) {
      return 'Soft Autumn';
    }
    return 'Soft Summer';
  }

  static List<String> inferBodyTypes(List<String> labels) {
    if (labels.any((l) => l.contains('oversized'))) {
      return ['Rectangle', 'Gamine'];
    }
    return ['Hourglass', 'Pear'];
  }

  static String inferHistory(String primaryStyle) {
    switch (primaryStyle) {
      case 'Boho Chic':
        return 'Bohemian fashion draws from 19th century artistic movements and was popularized in the 1960s.';
      case 'Classic':
        return 'Classic tailoring originates from European formalwear traditions of the 18th century.';
      case 'Streetwear':
        return 'Streetwear emerged from skate and hip-hop culture in the late 20th century.';
      default:
        return 'This style evolved through modern everyday fashion trends.';
    }
  }
}
