import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/ootd_post.dart';
import '../models/ootd_comment.dart';

class OotdFeedService {
  static final OotdFeedService _instance = OotdFeedService._internal();
  factory OotdFeedService() => _instance;
  OotdFeedService._internal();

  final List<OotdPost> _posts = [];
  List<OotdPost> get posts => _posts;

  Future<File> _postsFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/ootd_posts.json');
  }

  Future<void> load() async {
    final file = await _postsFile();
    if (!await file.exists()) return;

    final data = jsonDecode(await file.readAsString()) as List;
    _posts
      ..clear()
      ..addAll(data.map((e) => OotdPost.fromJson(Map<String, dynamic>.from(e))));

    _posts.sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  Future<void> save() async {
    final file = await _postsFile();
    final jsonData = _posts.map((p) => p.toJson()).toList();
    await file.writeAsString(jsonEncode(jsonData));
  }

  Future<OotdPost> createPost({
    required File imageFile,
    required String caption,
  }) async {
    final dir = await getApplicationDocumentsDirectory();
    final id = DateTime.now().millisecondsSinceEpoch.toString();

    // save image
    final ext = imageFile.path.toLowerCase().endsWith('.png') ? 'png' : 'jpg';
    final savedPath = '${dir.path}/ootd_$id.$ext';
    final savedImage = await imageFile.copy(savedPath);

    final post = OotdPost(
      id: id,
      imagePath: savedImage.path,
      caption: caption.trim(),
      createdAt: DateTime.now(),
      likeCount: 0,
      likedByMe: false,
      comments: const [],
    );

    _posts.insert(0, post);
    await save();
    return post;
  }

  Future<void> deletePost(String postId) async {
    final idx = _posts.indexWhere((p) => p.id == postId);
    if (idx == -1) return;

    final post = _posts.removeAt(idx);
    final f = File(post.imagePath);
    if (await f.exists()) await f.delete();

    await save();
  }

  Future<void> toggleLike(String postId) async {
    final idx = _posts.indexWhere((p) => p.id == postId);
    if (idx == -1) return;

    final p = _posts[idx];
    final nowLiked = !p.likedByMe;
    final newCount = (p.likeCount + (nowLiked ? 1 : -1)).clamp(0, 1 << 30);

    _posts[idx] = p.copyWith(likedByMe: nowLiked, likeCount: newCount);
    await save();
  }

  Future<void> addComment(String postId, String text) async {
    final idx = _posts.indexWhere((p) => p.id == postId);
    if (idx == -1) return;

    final t = text.trim();
    if (t.isEmpty) return;

    final p = _posts[idx];
    final comment = OotdComment(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      text: t,
      createdAt: DateTime.now(),
    );

    final updated = List<OotdComment>.from(p.comments)..add(comment);
    _posts[idx] = p.copyWith(comments: updated);
    await save();
  }

  OotdPost? getById(String id) {
    try {
      return _posts.firstWhere((p) => p.id == id);
    } catch (_) {
      return null;
    }
  }
}
