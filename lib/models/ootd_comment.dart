class OotdComment {
  final String id;
  final String text;
  final DateTime createdAt;

  const OotdComment({
    required this.id,
    required this.text,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'createdAt': createdAt.toIso8601String(),
      };

  factory OotdComment.fromJson(Map<String, dynamic> json) {
    return OotdComment(
      id: json['id'] as String,
      text: (json['text'] as String?) ?? '',
      createdAt: DateTime.tryParse(json['createdAt'] ?? '') ?? DateTime.now(),
    );
  }
}
