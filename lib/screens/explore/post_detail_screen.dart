import 'dart:io';
import 'package:flutter/material.dart';

import '../../services/ootd_feed_service.dart';

class PostDetailScreen extends StatefulWidget {
  final String postId;

  const PostDetailScreen({super.key, required this.postId});

  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  final _commentCtrl = TextEditingController();

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final post = OotdFeedService().getById(widget.postId);

    if (post == null) {
      return const Scaffold(body: Center(child: Text('Post not found')));
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF7F4F2),
      appBar: AppBar(
        title: const Text('OOTD'),
        actions: [
          IconButton(
            tooltip: 'Delete',
            onPressed: () async {
              await OotdFeedService().deletePost(post.id);
              if (!mounted) return;
              Navigator.pop(context, true);
            },
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Image.file(File(post.imagePath), fit: BoxFit.cover),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              IconButton(
                onPressed: () async {
                  await OotdFeedService().toggleLike(post.id);
                  setState(() {});
                },
                icon: Icon(post.likedByMe ? Icons.favorite : Icons.favorite_border),
              ),
              Text('${post.likeCount}'),
              const Spacer(),
              Text(
                _timeAgo(post.createdAt),
                style: const TextStyle(color: Colors.black54),
              ),
            ],
          ),
          if (post.caption.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(post.caption, style: const TextStyle(fontSize: 16, height: 1.35)),
          ],
          const SizedBox(height: 14),
          const Text('Comments', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ...post.comments.map((c) {
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.black12),
              ),
              child: Text(c.text),
            );
          }),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _commentCtrl,
                  decoration: InputDecoration(
                    hintText: 'Add a comment…',
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              IconButton(
                onPressed: () async {
                  await OotdFeedService().addComment(post.id, _commentCtrl.text);
                  _commentCtrl.clear();
                  setState(() {});
                },
                icon: const Icon(Icons.send),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _timeAgo(DateTime dt) {
    final d = DateTime.now().difference(dt);
    if (d.inMinutes < 1) return 'now';
    if (d.inMinutes < 60) return '${d.inMinutes}m';
    if (d.inHours < 24) return '${d.inHours}h';
    return '${d.inDays}d';
  }
}
