import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme.dart';
import '../../models/clothing_item.dart';
import '../../services/closet_service.dart';
import 'clothing_detail_screen.dart';

class ClosetScreen extends StatefulWidget {
  const ClosetScreen({super.key});

  @override
  State<ClosetScreen> createState() => _ClosetScreenState();
}

class _ClosetScreenState extends State<ClosetScreen> {
  ClothingCategory selected = ClothingCategory.all;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ClosetService(),
      builder: (context, _) => _buildContent(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    final items = ClosetService().byCategory(selected);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // HEADER
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 16, 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'My Closet',
                      style: GoogleFonts.cormorantGaramond(
                        fontSize: 30,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      '${ClosetService().items.length} items',
                      style: GoogleFonts.dmSans(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Reset closet',
                onPressed: _confirmReset,
                icon: const Icon(
                  Icons.delete_outline,
                  color: AppColors.textTertiary,
                  size: 20,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 14),

        // CATEGORY FILTER
        SizedBox(
          height: 36,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            children: ClothingCategory.values.map((cat) {
              final isSelected = selected == cat;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GestureDetector(
                  onTap: () => setState(() => selected = cat),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOut,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                    decoration: BoxDecoration(
                      color: isSelected ? AppColors.accent : AppColors.surface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isSelected ? AppColors.accent : AppColors.border,
                        width: 0.5,
                      ),
                    ),
                    child: Text(
                      cat.name.toUpperCase(),
                      style: GoogleFonts.dmSans(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.9,
                        color: isSelected ? AppColors.background : AppColors.textSecondary,
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),

        const SizedBox(height: 16),

        // GRID
        Expanded(
          child: items.isEmpty
              ? _EmptyState(category: selected)
              : GridView.builder(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 0.72,
                  ),
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final item = items[index];
                    return GestureDetector(
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ClothingDetailScreen(item: item),
                          ),
                        );
                        if (mounted) setState(() {});
                      },
                      onLongPress: () => _openItemActions(item),
                      child: _ClosetCard(item: item),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Future<void> _openItemActions(ClothingItem item) async {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      backgroundColor: AppColors.surface,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.edit_outlined, color: AppColors.textSecondary, size: 20),
                title: Text(
                  'Edit details',
                  style: GoogleFonts.dmSans(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                  ),
                ),
                onTap: () async {
                  Navigator.pop(context);
                  await Navigator.push(
                    this.context,
                    MaterialPageRoute(
                      builder: (_) => ClothingDetailScreen(item: item),
                    ),
                  );
                  if (mounted) setState(() {});
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline, color: AppColors.error, size: 20),
                title: Text(
                  'Delete',
                  style: GoogleFonts.dmSans(
                    color: AppColors.error,
                    fontSize: 14,
                  ),
                ),
                onTap: () async {
                  Navigator.pop(context);
                  await _deleteItem(item);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Future<void> _deleteItem(ClothingItem item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete item?'),
        content: const Text('This will remove it from your closet permanently.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              'Cancel',
              style: GoogleFonts.dmSans(color: AppColors.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              'Delete',
              style: GoogleFonts.dmSans(
                color: AppColors.error,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );

    if (ok != true) return;
    await ClosetService().deleteItem(item.id);
    if (mounted) setState(() {});
  }

  Future<void> _confirmReset() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset closet?'),
        content: const Text(
          'This will permanently delete all items and images from this device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              'Cancel',
              style: GoogleFonts.dmSans(color: AppColors.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              'Reset',
              style: GoogleFonts.dmSans(
                color: AppColors.error,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );

    if (ok == true) {
      await ClosetService().clearAll();
      if (mounted) setState(() => selected = ClothingCategory.all);
    }
  }
}

class _ClosetCard extends StatelessWidget {
  final ClothingItem item;
  const _ClosetCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final title = item.title.trim().isEmpty ? 'Untitled item' : item.title.trim();

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: AppColors.surface,
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.file(
                    File(item.imagePath),
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      color: AppColors.surfaceElevated,
                      alignment: Alignment.center,
                      child: const Icon(
                        Icons.image_not_supported_outlined,
                        color: AppColors.textTertiary,
                        size: 28,
                      ),
                    ),
                  ),
                  // Category pill
                  Positioned(
                    top: 10,
                    left: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.background.withValues(alpha: 0.80),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        item.category.name.toUpperCase(),
                        style: GoogleFonts.dmSans(
                          color: AppColors.textSecondary,
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                  ),
                  // Analysing overlay
                  if (item.title == 'Analysing…')
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          color: AppColors.background.withValues(alpha: 0.55),
                        ),
                        alignment: Alignment.center,
                        child: const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.accent,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // Title row
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
              child: Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.left,
                style: GoogleFonts.dmSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  height: 1.3,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final ClothingCategory category;
  const _EmptyState({required this.category});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.checkroom_outlined,
            size: 40,
            color: AppColors.textTertiary,
          ),
          const SizedBox(height: 14),
          Text(
            category == ClothingCategory.all
                ? 'Your closet is empty'
                : 'No ${category.name} yet',
            style: GoogleFonts.cormorantGaramond(
              fontSize: 20,
              fontWeight: FontWeight.w500,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Tap the camera tab to add your first item',
            style: GoogleFonts.dmSans(
              fontSize: 13,
              color: AppColors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }
}
