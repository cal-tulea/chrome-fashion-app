import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/theme.dart';
import '../preview_screen.dart';

class CameraScreen extends StatelessWidget {
  const CameraScreen({super.key});

  Future<void> _pick(BuildContext context, ImageSource source) async {
    if (source == ImageSource.camera) {
      final status = await Permission.camera.request();
      if (!status.isGranted) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Camera permission denied')),
          );
        }
        return;
      }
    }

    final XFile? photo = await ImagePicker().pickImage(
      source: source,
      imageQuality: 100,
    );
    if (photo == null) return;

    if (context.mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PreviewScreen(imageFile: File(photo.path)),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Add to closet',
            style: GoogleFonts.cormorantGaramond(
              fontSize: 30,
              fontWeight: FontWeight.w500,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Photo the item on its own for the best analysis.',
            style: GoogleFonts.dmSans(fontSize: 13, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 32),

          // Camera button
          _OptionTile(
            icon: Icons.camera_alt_outlined,
            title: 'Take a photo',
            subtitle: 'Use your camera right now',
            onTap: () => _pick(context, ImageSource.camera),
          ),
          const SizedBox(height: 12),

          // Gallery button
          _OptionTile(
            icon: Icons.photo_library_outlined,
            title: 'Choose from gallery',
            subtitle: 'Pick an existing photo',
            onTap: () => _pick(context, ImageSource.gallery),
          ),

          const Spacer(),

          // Tip
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.accentSubtle,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.accent.withValues(alpha: 0.2), width: 0.5),
            ),
            child: Row(
              children: [
                const Icon(Icons.lightbulb_outline, color: AppColors.accent, size: 16),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Best results: flat lay on a light surface, or hang the item against a plain wall.',
                    style: GoogleFonts.dmSans(fontSize: 12, color: AppColors.accentLight, height: 1.5),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _OptionTile({required this.icon, required this.title, required this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border, width: 0.5),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: AppColors.accentSubtle,
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(icon, color: AppColors.accent, size: 20),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: GoogleFonts.dmSans(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: GoogleFonts.dmSans(fontSize: 12, color: AppColors.textSecondary)),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios, size: 14, color: AppColors.textTertiary),
          ],
        ),
      ),
    );
  }
}
