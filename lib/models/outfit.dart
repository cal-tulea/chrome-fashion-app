import 'clothing_item.dart';

class Outfit {
  final ClothingItem top;
  final ClothingItem bottom;
  final ClothingItem? shoes;
  final ClothingItem? outerwear;

  final int score;
  final List<String> reasons;

  Outfit({
    required this.top,
    required this.bottom,
    this.shoes,
    this.outerwear,
    required this.score,
    required this.reasons,
  });

  List<ClothingItem> get items => [
        top,
        bottom,
        if (outerwear != null) outerwear!,
        if (shoes != null) shoes!,
      ];
}
