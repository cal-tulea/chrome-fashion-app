import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme.dart';
import '../../services/closet_service.dart';
import '../../services/user_profile_service.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  UserProfile? _profile;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final profile = await UserProfileService.instance.getProfile();
    if (mounted) setState(() { _profile = profile; _loading = false; });
  }

  Future<void> _signOut() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text('You\'ll need to sign in again to access your wardrobe.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: GoogleFonts.dmSans(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Sign out', style: GoogleFonts.dmSans(color: AppColors.error, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
    if (confirm == true) await FirebaseAuth.instance.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final closetCount = ClosetService().items.length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
      children: [
        Text(
          'Profile',
          style: GoogleFonts.cormorantGaramond(
            fontSize: 30,
            fontWeight: FontWeight.w500,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 24),

        // ── User card ──────────────────────────────────────────────────────
        _Card(
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: AppColors.accentSubtle,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.accent.withValues(alpha: 0.3), width: 1),
                ),
                child: Center(
                  child: Text(
                    (user?.email?.isNotEmpty == true)
                        ? user!.email![0].toUpperCase()
                        : '?',
                    style: GoogleFonts.cormorantGaramond(
                      fontSize: 24,
                      fontWeight: FontWeight.w600,
                      color: AppColors.accent,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user?.email ?? 'Not signed in',
                      style: GoogleFonts.dmSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '$closetCount items in closet',
                      style: GoogleFonts.dmSans(fontSize: 12, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // ── Color season card ──────────────────────────────────────────────
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: AppColors.accentSubtle,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: const Icon(Icons.palette_outlined, color: AppColors.accent, size: 17),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Color Season',
                    style: GoogleFonts.dmSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.accentSubtle,
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Text(
                      'COMING SOON',
                      style: GoogleFonts.dmSans(
                        fontSize: 8,
                        fontWeight: FontWeight.w700,
                        color: AppColors.accent,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (_loading)
                const Center(child: CircularProgressIndicator(color: AppColors.accent, strokeWidth: 2))
              else if (_profile?.colorSeason != null) ...[
                Text(
                  _profile!.colorSeason!,
                  style: GoogleFonts.cormorantGaramond(
                    fontSize: 28,
                    fontWeight: FontWeight.w500,
                    color: AppColors.accent,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Your outfits are calibrated to this palette.',
                  style: GoogleFonts.dmSans(fontSize: 12, color: AppColors.textSecondary),
                ),
              ] else ...[
                Text(
                  'Not analyzed yet',
                  style: GoogleFonts.cormorantGaramond(
                    fontSize: 22,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Upload a selfie to discover your season — Deep Autumn, Soft Summer, and more.',
                  style: GoogleFonts.dmSans(
                    fontSize: 13,
                    color: AppColors.textTertiary,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 16),
                _SeasonSwatches(),
              ],
            ],
          ),
        ),

        const SizedBox(height: 16),

        // ── Swipe guide ────────────────────────────────────────────────────
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: AppColors.accentSubtle,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: const Icon(Icons.swipe_outlined, color: AppColors.accent, size: 17),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'How swiping works',
                    style: GoogleFonts.dmSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _SwipeGuideRow(icon: Icons.favorite, color: AppColors.success, label: 'Swipe right or tap ♥', detail: 'Tells the app you love this look — those pieces appear more often'),
              const SizedBox(height: 10),
              _SwipeGuideRow(icon: Icons.close, color: AppColors.error, label: 'Swipe left or tap ✕', detail: "Not your vibe — this outfit won't appear again"),
              const SizedBox(height: 10),
              _SwipeGuideRow(icon: Icons.bookmark_border, color: AppColors.accent, label: 'Tap bookmark', detail: 'Saves the outfit to your Canvas → Saved tab'),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // ── Sign out ───────────────────────────────────────────────────────
        _Card(
          child: InkWell(
            onTap: _signOut,
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Icon(Icons.logout, color: AppColors.error, size: 17),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Sign out',
                    style: GoogleFonts.dmSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.error,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: child,
    );
  }
}

class _SeasonSwatches extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    const seasons = [
      ('Deep Autumn', Color(0xFF8B4513)),
      ('Soft Summer', Color(0xFF708090)),
      ('True Winter', Color(0xFF191970)),
      ('Bright Spring', Color(0xFFDAA520)),
    ];
    return Row(
      children: seasons.map((s) {
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Column(
              children: [
                Container(
                  height: 32,
                  decoration: BoxDecoration(
                    color: s.$2,
                    borderRadius: BorderRadius.circular(7),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  s.$1,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.dmSans(fontSize: 8, color: AppColors.textTertiary, height: 1.2),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _SwipeGuideRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String detail;
  const _SwipeGuideRow({required this.icon, required this.color, required this.label, required this.detail});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 15, color: color),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: GoogleFonts.dmSans(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
              const SizedBox(height: 2),
              Text(detail, style: GoogleFonts.dmSans(fontSize: 12, color: AppColors.textSecondary, height: 1.4)),
            ],
          ),
        ),
      ],
    );
  }
}
