import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme.dart';
import '../../services/ootd_feed_service.dart';
import 'create_post_screen.dart';
import 'post_detail_screen.dart';

class ExploreScreen extends StatefulWidget {
  const ExploreScreen({super.key});

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  final _feed = OotdFeedService();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _feed.load();
    setState(() => _loading = false);
  }

  Future<void> _openCreate() async {
    final created = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CreatePostScreen()),
    );
    if (created == true) {
      await _feed.load();
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.accent));
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            backgroundColor: AppColors.background,
            pinned: true,
            title: Text(
              'Feed',
              style: GoogleFonts.cormorantGaramond(
                fontSize: 30,
                fontWeight: FontWeight.w500,
                color: AppColors.textPrimary,
              ),
            ),
            titleSpacing: 20,
            actions: [
              IconButton(
                tooltip: 'New post',
                onPressed: _openCreate,
                icon: const Icon(Icons.add, color: AppColors.accent, size: 24),
              ),
              const SizedBox(width: 8),
            ],
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(0.5),
              child: Container(height: 0.5, color: AppColors.border),
            ),
          ),

          if (_feed.posts.isEmpty)
            SliverFillRemaining(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.grid_view_outlined, size: 40, color: AppColors.textTertiary),
                      const SizedBox(height: 16),
                      Text(
                        'Nothing here yet',
                        style: GoogleFonts.cormorantGaramond(
                          fontSize: 24,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Be the first to post your OOTD.',
                        style: GoogleFonts.dmSans(fontSize: 13, color: AppColors.textTertiary),
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        height: 48,
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _openCreate,
                          child: Text(
                            'POST OOTD',
                            style: GoogleFonts.dmSans(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.4,
                              color: AppColors.background,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, i) {
                    final post = _feed.posts[i];
                    return GestureDetector(
                      onTap: () async {
                        final changed = await Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => PostDetailScreen(postId: post.id)),
                        );
                        if (changed == true) {
                          await _feed.load();
                          if (mounted) setState(() {});
                        }
                      },
                      child: _PostCard(
                        post: post,
                        onLike: () async {
                          await _feed.toggleLike(post.id);
                          await _feed.load();
                          if (mounted) setState(() {});
                        },
                      ),
                    );
                  },
                  childCount: _feed.posts.length,
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openCreate,
        backgroundColor: AppColors.accent,
        foregroundColor: AppColors.background,
        elevation: 0,
        child: const Icon(Icons.add, size: 22),
      ),
    );
  }
}

class _PostCard extends StatelessWidget {
  final dynamic post;
  final VoidCallback onLike;
  const _PostCard({required this.post, required this.onLike});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Image — full bleed top
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            child: AspectRatio(
              aspectRatio: 1,
              child: Image.file(
                File(post.imagePath),
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  color: AppColors.surfaceElevated,
                  alignment: Alignment.center,
                  child: const Icon(Icons.image_not_supported_outlined, color: AppColors.textTertiary),
                ),
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Like row
                Row(
                  children: [
                    GestureDetector(
                      onTap: onLike,
                      child: Icon(
                        post.likedByMe ? Icons.favorite : Icons.favorite_border,
                        size: 20,
                        color: post.likedByMe ? AppColors.error : AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${post.likeCount}',
                      style: GoogleFonts.dmSans(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Icon(Icons.chat_bubble_outline, size: 18, color: AppColors.textTertiary),
                    const SizedBox(width: 6),
                    Text(
                      '${post.comments.length}',
                      style: GoogleFonts.dmSans(fontSize: 13, color: AppColors.textSecondary),
                    ),
                  ],
                ),
                if (post.caption.trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    post.caption,
                    style: GoogleFonts.dmSans(
                      fontSize: 13,
                      color: AppColors.textPrimary,
                      height: 1.5,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
