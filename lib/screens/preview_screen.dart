import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/nav_state.dart';
import '../core/theme.dart';
import '../models/clothing_item.dart';
import '../services/closet_service.dart';
import '../services/clothing_item_analyzer.dart';
import '../services/background_cleanup_service.dart';

class PreviewScreen extends StatefulWidget {
  final File imageFile;
  const PreviewScreen({super.key, required this.imageFile});

  @override
  State<PreviewScreen> createState() => _PreviewScreenState();
}

class _PreviewScreenState extends State<PreviewScreen> {
  final _analyzer = ClothingItemAnalyzer();
  final _cleanup = BackgroundCleanupService();

  bool _loadingPrediction = true;

  // OFF by default — original photo quality is better in almost all cases.
  // User can enable if they specifically want background whitening.
  bool _improvePhoto = false;
  bool _processingPhoto = false;

  File? _processed;
  ClothingCategory? _override;
  CategoryPrediction? _prediction;

  @override
  void initState() {
    super.initState();
    _runPrediction();
  }

  File get _imageToAnalyze => _processed ?? widget.imageFile;
  ClothingCategory get _effectiveCategory =>
      _override ?? _prediction?.category ?? ClothingCategory.tops;
  bool get _uncertain => _prediction?.uncertain ?? false;

  Future<void> _runCleanup() async {
    setState(() => _processingPhoto = true);
    try {
      final out = await _cleanup.cleanup(
        input: widget.imageFile,
        enableBorderTrim: true,
        enableBackgroundWhiten: true,
      );
      // Only accept result if the file exists and has content
      if (await out.exists() && await out.length() > 1024) {
        setState(() => _processed = out);
      } else {
        setState(() => _processed = null);
      }
    } catch (_) {
      setState(() => _processed = null);
    } finally {
      setState(() => _processingPhoto = false);
    }
  }

  Future<void> _runPrediction() async {
    setState(() => _loadingPrediction = true);
    final pred = await _analyzer.predictCategory(_imageToAnalyze);
    setState(() {
      _prediction = pred;
      _loadingPrediction = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final shown = _imageToAnalyze;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18, color: AppColors.textSecondary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Preview',
          style: GoogleFonts.cormorantGaramond(
            fontSize: 22,
            fontWeight: FontWeight.w500,
            color: AppColors.textPrimary,
          ),
        ),
      ),
      body: Column(
        children: [
          // ── Image ──────────────────────────────────────────────────────────
          Expanded(
            child: Stack(
              children: [
                Container(
                  color: AppColors.surface,
                  child: Center(
                    child: Image.file(shown, fit: BoxFit.contain),
                  ),
                ),
                if (_processingPhoto || _loadingPrediction)
                  Container(
                    color: AppColors.background.withValues(alpha: 0.50),
                    alignment: Alignment.center,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(color: AppColors.accent),
                        const SizedBox(height: 12),
                        Text(
                          _processingPhoto ? 'Processing photo…' : 'Analysing…',
                          style: GoogleFonts.dmSans(color: AppColors.textSecondary, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),

          // ── Controls ───────────────────────────────────────────────────────
          Container(
            color: AppColors.surface,
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Background cleanup toggle
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Improve photo',
                            style: GoogleFonts.dmSans(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          Text(
                            'Whitens background — works best on light surfaces',
                            style: GoogleFonts.dmSans(fontSize: 11, color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: _improvePhoto,
                      activeThumbColor: AppColors.accent,
                      onChanged: (v) async {
                        setState(() {
                          _improvePhoto = v;
                          _processed = null;
                          _override = null;
                        });
                        if (v) await _runCleanup();
                        await _runPrediction();
                      },
                    ),
                  ],
                ),

                const Divider(color: AppColors.border, height: 16),

                // Detected category
                Row(
                  children: [
                    Text(
                      'Detected as',
                      style: GoogleFonts.dmSans(fontSize: 13, color: AppColors.textSecondary),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.accentSubtle,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: AppColors.accent.withValues(alpha: 0.3), width: 0.5),
                      ),
                      child: Text(
                        _effectiveCategory.name.toUpperCase(),
                        style: GoogleFonts.dmSans(
                          color: AppColors.accent,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: _loadingPrediction ? null : _editCategory,
                      child: Text(
                        'Change',
                        style: GoogleFonts.dmSans(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),

                if (_uncertain)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      'Not fully confident — tap Change to confirm.',
                      style: GoogleFonts.dmSans(color: AppColors.error, fontSize: 11),
                    ),
                  ),

                const SizedBox(height: 10),

                // Action buttons
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 48,
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: AppColors.border, width: 0.5),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: Text(
                            'Retake',
                            style: GoogleFonts.dmSans(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: SizedBox(
                        height: 48,
                        child: ElevatedButton(
                          onPressed: (_processingPhoto || _loadingPrediction)
                              ? null
                              : () async {
                                  await ClosetService().addItem(
                                    _imageToAnalyze,
                                    categoryHint: _effectiveCategory,
                                  );
                                  if (mounted) {
                                    globalNavIndex.value = 3; // go to closet
                                    Navigator.pop(context);
                                  }
                                },
                          child: Text(
                            'SAVE TO CLOSET',
                            style: GoogleFonts.dmSans(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.2,
                              color: AppColors.background,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 20),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _editCategory() async {
    final picked = await showModalBottomSheet<ClothingCategory>(
      context: context,
      showDragHandle: true,
      backgroundColor: AppColors.surface,
      builder: (context) {
        final cats = ClothingCategory.values.where((c) => c != ClothingCategory.all).toList();
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                child: Text(
                  'Choose category',
                  style: GoogleFonts.cormorantGaramond(
                    fontSize: 22,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              ...cats.map((c) {
                final selected = c == _effectiveCategory;
                return ListTile(
                  title: Text(
                    c.name.toUpperCase(),
                    style: GoogleFonts.dmSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.6,
                      color: selected ? AppColors.accent : AppColors.textPrimary,
                    ),
                  ),
                  trailing: selected
                      ? const Icon(Icons.check, color: AppColors.accent, size: 18)
                      : null,
                  onTap: () => Navigator.pop(context, c),
                );
              }),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );

    if (picked == null) return;
    setState(() => _override = picked);
  }
}
