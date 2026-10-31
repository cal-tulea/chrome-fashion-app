import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme.dart';
import '../../models/outfit.dart';
import '../../services/outfit_service.dart';

class SavedOutfitDetailScreen extends StatelessWidget {
  final Outfit outfit;
  final VoidCallback? onDeleted;

  const SavedOutfitDetailScreen({super.key, required this.outfit, this.onDeleted});

  @override
  Widget build(BuildContext context) {
    final items = outfit.items;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18, color: AppColors.textSecondary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Saved Look',
          style: GoogleFonts.cormorantGaramond(
            fontSize: 22,
            fontWeight: FontWeight.w500,
            color: AppColors.textPrimary,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline, color: AppColors.error, size: 20),
            tooltip: 'Remove outfit',
            onPressed: () => _confirmDelete(context),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: ListView.separated(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, i) {
          final item = items[i];
          final labels = ['Top', 'Bottom', 'Shoes', 'Outerwear'];
          final label = i < labels.length ? labels[i] : item.category.name;

          return Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.border, width: 0.5),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Full image — contain so full garment is visible
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: Container(
                      color: AppColors.surfaceElevated,
                      child: Image.file(
                        File(item.imagePath),
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => const Center(
                          child: Icon(Icons.image_not_supported_outlined, color: AppColors.textTertiary, size: 36),
                        ),
                      ),
                    ),
                  ),
                ),
                // Item info
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.accentSubtle,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          label.toUpperCase(),
                          style: GoogleFonts.dmSans(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: AppColors.accent,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          item.title.trim().isEmpty ? 'Untitled item' : item.title.trim(),
                          style: GoogleFonts.dmSans(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove outfit?'),
        content: const Text('This removes the saved look but keeps your clothes.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: GoogleFonts.dmSans(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Remove', style: GoogleFonts.dmSans(color: AppColors.error, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );

    if (ok == true && context.mounted) {
      await OutfitService().removeOutfitByItems(outfit);
      onDeleted?.call();
      if (context.mounted) Navigator.pop(context);
    }
  }
}
