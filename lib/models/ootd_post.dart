import 'ootd_comment.dart';

class OotdPost {
  final String id;
  final String imagePath; // local path for now
  final String caption;
  final DateTime createdAt;

  final int likeCount;
  final bool likedByMe;

  final List<OotdComment> comments;

  const OotdPost({
    required this.id,
    required this.imagePath,
    required this.caption,
    required this.createdAt,
    required this.likeCount,
    required this.likedByMe,
    required this.comments,
  });

  OotdPost copyWith({
    String? id,
    String? imagePath,
    String? caption,
    DateTime? createdAt,
    int? likeCount,
    bool? likedByMe,
    List<OotdComment>? comments,
  }) {
    return OotdPost(
      id: id ?? this.id,
      imagePath: imagePath ?? this.imagePath,
      caption: caption ?? this.caption,
      createdAt: createdAt ?? this.createdAt,
      likeCount: likeCount ?? this.likeCount,
      likedByMe: likedByMe ?? this.likedByMe,
      comments: comments ?? this.comments,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'imagePath': imagePath,
        'caption': caption,
        'createdAt': createdAt.toIso8601String(),
        'likeCount': likeCount,
        'likedByMe': likedByMe,
        'comments': comments.map((c) => c.toJson()).toList(),
      };

  factory OotdPost.fromJson(Map<String, dynamic> json) {
    final rawComments = (json['comments'] as List?) ?? const [];
    return OotdPost(
      id: json['id'] as String,
      imagePath: json['imagePath'] as String,
      caption: (json['caption'] as String?) ?? '',
      createdAt: DateTime.tryParse(json['createdAt'] ?? '') ?? DateTime.now(),
      likeCount: (json['likeCount'] as num?)?.toInt() ?? 0,
      likedByMe: (json['likedByMe'] as bool?) ?? false,
      comments: rawComments.map((e) => OotdComment.fromJson(Map<String, dynamic>.from(e))).toList(),
    );
  }
}
