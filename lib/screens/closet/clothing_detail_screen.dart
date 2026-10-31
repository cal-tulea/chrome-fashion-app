import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme.dart';
import '../../models/clothing_item.dart';
import '../../services/closet_service.dart';
import '../../services/correction_service.dart';
import '../../services/huggingface_service.dart';

class ClothingDetailScreen extends StatefulWidget {
  final ClothingItem item;
  const ClothingDetailScreen({super.key, required this.item});

  @override
  State<ClothingDetailScreen> createState() => _ClothingDetailScreenState();
}

class _ClothingDetailScreenState extends State<ClothingDetailScreen> {
  late ClothingItem _item;
  late ClothingCategory _category;
  late TextEditingController _titleCtrl;
  late TextEditingController _notesCtrl;
  late TextEditingController _descCtrl;
  bool _busy = false;
  bool _dirtyTitle = false;
  bool _dirtyDesc = false;

  @override
  void initState() {
    super.initState();
    _item = widget.item;
    _category = _item.category;
    _titleCtrl = TextEditingController(text: _item.title.trim().isEmpty ? 'Untitled' : _item.title.trim());
    _notesCtrl = TextEditingController(text: _item.notes);
    _descCtrl  = TextEditingController(text: _resolvedDescription());
    _titleCtrl.addListener(() => _dirtyTitle = true);
    _descCtrl.addListener(() => _dirtyDesc = true);
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _notesCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final latest = ClosetService().getById(_item.id);
    if (latest != null && mounted) {
      setState(() { _item = latest; _category = latest.category; });
      // Re-seed description controller only if user hasn't manually edited it
      if (!_dirtyDesc) {
        _descCtrl.text = _resolvedDescription();
      }
    }
  }

  Future<void> _save({bool toast = false}) async {
    setState(() => _busy = true);
    final t = _titleCtrl.text.trim();
    if (t.isNotEmpty) {
      // Record correction so Gemini learns from it on future analyses
      if (_dirtyTitle && t != _item.title.trim()) {
        await CorrectionService().record(
          originalTitle: _item.title.trim(),
          correctedTitle: t,
        );
      }
      await ClosetService().updateItemTitle(_item.id, t);
    }
    await ClosetService().updateItemNotes(_item.id, _notesCtrl.text);
    if (_dirtyDesc) {
      final updated = _item.analysis.copyWith(description: _descCtrl.text.trim());
      await ClosetService().updateItemAnalysis(_item.id, updated);
    }
    _dirtyTitle = false;
    _dirtyDesc = false;
    await _refresh();
    setState(() => _busy = false);
    if (toast && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved')));
    }
  }

  Future<void> _rerun() async {
    if (_dirtyTitle) await _save();
    setState(() => _busy = true);
    await ClosetService().rerunAnalysis(_item.id);
    await _refresh();
    setState(() => _busy = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Analysis refreshed')));
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Delete item?', style: GoogleFonts.cormorantGaramond(color: AppColors.textPrimary, fontSize: 20)),
        content: Text('This removes it from your closet and any saved outfits.',
            style: GoogleFonts.dmSans(color: AppColors.textSecondary, fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
              child: Text('Cancel', style: GoogleFonts.dmSans(color: AppColors.textSecondary))),
          TextButton(onPressed: () => Navigator.pop(context, true),
              child: Text('Delete', style: GoogleFonts.dmSans(color: AppColors.error, fontWeight: FontWeight.w700))),
        ],
      ),
    );
    if (ok != true) return;
    await ClosetService().deleteItem(_item.id);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _editCategory() async {
    final cats = ClothingCategory.values.where((c) => c != ClothingCategory.all).toList();
    final picked = await showModalBottomSheet<ClothingCategory>(
      context: context,
      showDragHandle: true,
      backgroundColor: AppColors.surface,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Text('Choose category',
                  style: GoogleFonts.cormorantGaramond(
                      fontSize: 22, fontWeight: FontWeight.w500, color: AppColors.textPrimary)),
            ),
            ...cats.map((c) => ListTile(
              title: Text(c.name.toUpperCase(),
                  style: GoogleFonts.dmSans(
                      fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.6,
                      color: c == _category ? AppColors.accent : AppColors.textPrimary)),
              trailing: c == _category ? const Icon(Icons.check, color: AppColors.accent, size: 18) : null,
              onTap: () => Navigator.pop(context, c),
            )),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (picked == null || picked == _category) return;
    setState(() => _busy = true);
    await ClosetService().updateItemCategory(_item.id, picked);
    await _refresh();
    setState(() => _busy = false);
  }

  // Returns the best available description.
  // If stored description contradicts the current title (e.g., says "shorts"
  // but title says "Jeans"), regenerate from the title on the fly so the
  // user never sees stale AI output.
  String _resolvedDescription() {
    final a = _item.analysis;
    final stored = a.description.trim();
    if (stored.isEmpty) {
      return 'Tap the refresh icon to generate an AI description for this piece.';
    }

    final titleLower = _titleCtrl.text.toLowerCase();
    final descLower  = stored.toLowerCase();

    // Pairs where [0]=what title says, [1]=conflicting word description uses
    const conflictPairs = [
      ['jeans', 'shorts'],
      ['jeans', 'skirt'],
      ['trousers', 'shorts'],
      ['shorts', 'jeans'],
      ['skirt', 'jeans'],
      ['boots', 'sneakers'],
      ['sneakers', 'boots'],
      ['heels', 'sneakers'],
    ];
    bool contradicts = false;
    for (final pair in conflictPairs) {
      if (titleLower.contains(pair[0]) && descLower.contains(pair[1]) && !descLower.contains(pair[0])) {
        contradicts = true;
        break;
      }
    }
    if (!contradicts) return stored;

    // Rebuild description from current title + existing analysis signals
    final garmentType = _garmentFromTitle(titleLower);
    final fit = _fitFromTitle(titleLower);
    return HFAnalysisResult.buildRichDescription(
      garmentType: garmentType,
      color: a.colors.isNotEmpty ? a.colors.first : '',
      fit: fit,
      category: _item.category,
      formality: a.formality.isEmpty ? 'Casual' : a.formality,
      structure: a.structure.isEmpty ? 'Soft' : a.structure,
      seasonality: a.seasonality.isEmpty ? 'AllSeason' : a.seasonality,
    );
  }

  static String _garmentFromTitle(String titleLower) {
    if (titleLower.contains('wide-leg') || (titleLower.contains('wide') && titleLower.contains('leg'))) return 'wide-leg jeans';
    if (titleLower.contains('straight-leg') || (titleLower.contains('straight') && titleLower.contains('leg'))) return 'straight-leg jeans';
    if (titleLower.contains('slim') && (titleLower.contains('jean') || titleLower.contains('denim'))) return 'slim jeans';
    const garments = ['jeans', 'shorts', 'trousers', 'skirt', 'hoodie', 'sweater', 'cardigan', 'shirt', 't-shirt', 'boots', 'sneakers', 'heels', 'coat', 'jacket', 'blazer'];
    for (final g in garments) { if (titleLower.contains(g)) return g; }
    if (titleLower.contains('denim')) return 'jeans';
    return titleLower.trim().split(RegExp(r'\s+')).last;
  }

  static String _fitFromTitle(String titleLower) {
    if (titleLower.contains('wide-leg') || (titleLower.contains('wide') && titleLower.contains('leg'))) return 'wide-leg';
    if (titleLower.contains('straight-leg') || titleLower.contains('straight')) return 'straight-leg';
    if (titleLower.contains('slim')) return 'slim';
    if (titleLower.contains('skinny')) return 'skinny';
    if (titleLower.contains('oversized')) return 'oversized';
    if (titleLower.contains('cropped') || titleLower.contains('crop')) return 'cropped';
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final a = _item.analysis;
    final description = _resolvedDescription();

    final pairings = HFAnalysisResult.stylistPairingsFor(_item);

    // Auto-generate display pills from analysis
    final pills = <String>[
      _category.name.toUpperCase(),
      if (a.subStyles.isNotEmpty) a.subStyles.first.toUpperCase()
      else if (a.formality.isNotEmpty && a.formality != 'Casual') a.formality.toUpperCase(),
      if (a.seasonality.isNotEmpty && a.seasonality != 'AllSeason') a.seasonality.toUpperCase(),
    ];

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop && _dirtyTitle) await _save();
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.background,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, size: 18, color: AppColors.textSecondary),
            onPressed: () async {
              if (_dirtyTitle) await _save();
              if (mounted) Navigator.pop(context);
            },
          ),
          title: Text('Details',
              style: GoogleFonts.cormorantGaramond(
                  fontSize: 22, fontWeight: FontWeight.w500, color: AppColors.textPrimary)),
          actions: [
            if (_busy)
              const Padding(
                padding: EdgeInsets.all(14),
                child: SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 1.5, color: AppColors.accent)),
              )
            else ...[
              IconButton(
                tooltip: 'Re-run AI analysis',
                onPressed: _rerun,
                icon: const Icon(Icons.refresh, color: AppColors.textTertiary, size: 20),
              ),
              IconButton(
                tooltip: 'Save',
                onPressed: () => _save(toast: true),
                icon: const Icon(Icons.check, color: AppColors.accent, size: 20),
              ),
            ],
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 48),
          children: [

            // ── Image ──────────────────────────────────────────────────────
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: AspectRatio(
                aspectRatio: 1,
                child: Container(
                  color: AppColors.surface,
                  child: Image.file(
                    File(_item.imagePath),
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Center(
                      child: Icon(Icons.image_not_supported_outlined,
                          color: AppColors.textTertiary, size: 40),
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 18),

            // ── Title ──────────────────────────────────────────────────────
            TextField(
              controller: _titleCtrl,
              textCapitalization: TextCapitalization.words,
              style: GoogleFonts.cormorantGaramond(
                  fontSize: 26, fontWeight: FontWeight.w500, color: AppColors.textPrimary),
              decoration: InputDecoration(
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: const UnderlineInputBorder(
                    borderSide: BorderSide(color: AppColors.accent, width: 0.5)),
                hintText: 'Item title',
                hintStyle: GoogleFonts.cormorantGaramond(
                    fontSize: 26, color: AppColors.textTertiary),
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),

            const SizedBox(height: 10),

            // ── Pills ──────────────────────────────────────────────────────
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                // Category pill — tappable to change
                GestureDetector(
                  onTap: _busy ? null : _editCategory,
                  child: _pill(_category.name.toUpperCase(), accent: true),
                ),
                ...pills.skip(1).map((p) => _pill(p)),
              ],
            ),

            const SizedBox(height: 28),

            // ── About this piece ───────────────────────────────────────────
            Row(
              children: [
                _sectionHeader('About this piece'),
                const Spacer(),
                Text(
                  'AI-generated · may be inaccurate',
                  style: GoogleFonts.dmSans(
                      fontSize: 10, color: AppColors.textTertiary,
                      fontStyle: FontStyle.italic),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _descCtrl,
              maxLines: null,
              textCapitalization: TextCapitalization.sentences,
              style: GoogleFonts.dmSans(
                  fontSize: 14, color: AppColors.textSecondary, height: 1.65),
              decoration: InputDecoration(
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(
                        color: AppColors.accent.withValues(alpha: 0.4),
                        width: 0.5)),
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),

            const SizedBox(height: 28),

            // ── A stylist would pair this with ─────────────────────────────
            Row(
              children: [
                const Icon(Icons.style_outlined, size: 15, color: AppColors.accent),
                const SizedBox(width: 8),
                _sectionHeader('A stylist would pair this with'),
              ],
            ),
            const SizedBox(height: 12),
            ...pairings.map((s) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 4, height: 4,
                    margin: const EdgeInsets.only(top: 7, right: 12),
                    decoration: const BoxDecoration(
                        color: AppColors.accent, shape: BoxShape.circle),
                  ),
                  Expanded(
                    child: Text(s,
                        style: GoogleFonts.dmSans(
                            fontSize: 13, color: AppColors.textSecondary, height: 1.5)),
                  ),
                ],
              ),
            )),

            const SizedBox(height: 28),

            // ── Notes ──────────────────────────────────────────────────────
            _sectionHeader('Notes'),
            const SizedBox(height: 8),
            TextField(
              controller: _notesCtrl,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              style: GoogleFonts.dmSans(fontSize: 13, color: AppColors.textPrimary),
              decoration: InputDecoration(
                hintText: 'Where it\'s from, when you wear it, anything worth remembering…',
                hintStyle: GoogleFonts.dmSans(fontSize: 13, color: AppColors.textTertiary),
                filled: true,
                fillColor: AppColors.surface,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.border, width: 0.5)),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.border, width: 0.5)),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.accent, width: 0.5)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
            ),

            const SizedBox(height: 20),

            // ── Advanced (collapsed by default) ────────────────────────────
            Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border, width: 0.5),
              ),
              child: ExpansionTile(
                tilePadding: const EdgeInsets.symmetric(horizontal: 16),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                title: Text('Advanced',
                    style: GoogleFonts.dmSans(
                        fontSize: 13, fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary)),
                subtitle: Text('AI tuning, style tags, re-run analysis',
                    style: GoogleFonts.dmSans(fontSize: 11, color: AppColors.textTertiary)),
                iconColor: AppColors.textTertiary,
                collapsedIconColor: AppColors.textTertiary,
                children: [
                  // Colors
                  if (a.colors.isNotEmpty) ...[
                    _advancedLabel('Detected colors'),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6, runSpacing: 6,
                      children: a.colors.map((c) => _pill(c)).toList(),
                    ),
                    const SizedBox(height: 14),
                  ],

                  // Signal dropdowns
                  _advancedDropdown('Style', a.primaryStyle.isEmpty ? 'Everyday' : a.primaryStyle,
                      ['Everyday', 'Classic', 'Minimal', 'Streetwear', 'Athleisure', 'Romantic'],
                      (v) => _setOverride('primaryStyle', v)),
                  const SizedBox(height: 10),
                  _advancedDropdown('Color season', a.colorSeason.isEmpty ? 'Any' : a.colorSeason,
                      ['Any', 'Winter', 'Summer', 'Autumn', 'Spring'],
                      (v) => _setOverride('colorSeason', v)),
                  const SizedBox(height: 10),
                  _advancedDropdown('Formality', a.formality.isEmpty ? 'Casual' : a.formality,
                      ['Casual', 'Smart', 'Formal'],
                      (v) => _setOverride('formality', v)),
                  const SizedBox(height: 10),
                  _advancedDropdown('Seasonality', a.seasonality.isEmpty ? 'AllSeason' : a.seasonality,
                      ['AllSeason', 'Summer', 'Winter', 'Transitional'],
                      (v) => _setOverride('seasonality', v)),

                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _busy ? null : _rerun,
                      icon: const Icon(Icons.refresh, size: 16),
                      label: Text('Re-run AI analysis',
                          style: GoogleFonts.dmSans(fontSize: 12, fontWeight: FontWeight.w600)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.accent,
                        side: const BorderSide(color: AppColors.accent, width: 0.5),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 28),

            // ── Delete ─────────────────────────────────────────────────────
            SizedBox(
              width: double.infinity,
              height: 46,
              child: OutlinedButton(
                onPressed: _busy ? null : _delete,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.error,
                  side: BorderSide(color: AppColors.error.withValues(alpha: 0.4), width: 0.5),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Text('Delete item',
                    style: GoogleFonts.dmSans(
                        fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.error)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  Widget _pill(String text, {bool accent = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: accent ? AppColors.accentSubtle : AppColors.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
            color: accent
                ? AppColors.accent.withValues(alpha: 0.35)
                : AppColors.border,
            width: 0.5),
      ),
      child: Text(text,
          style: GoogleFonts.dmSans(
              color: accent ? AppColors.accent : AppColors.textSecondary,
              fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.7)),
    );
  }

  Widget _sectionHeader(String text) {
    return Text(text,
        style: GoogleFonts.dmSans(
            fontSize: 11, fontWeight: FontWeight.w700,
            color: AppColors.textTertiary, letterSpacing: 0.8));
  }

  Widget _advancedLabel(String text) {
    return Text(text,
        style: GoogleFonts.dmSans(
            fontSize: 11, color: AppColors.textTertiary,
            fontWeight: FontWeight.w600, letterSpacing: 0.5));
  }

  Widget _advancedDropdown(String label, String value, List<String> options,
      void Function(String) onChanged) {
    final safe = options.contains(value) ? value : options.first;
    return Row(
      children: [
        SizedBox(
          width: 100,
          child: Text(label,
              style: GoogleFonts.dmSans(
                  color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
        ),
        const Spacer(),
        DropdownButton<String>(
          value: safe,
          dropdownColor: AppColors.surfaceElevated,
          style: GoogleFonts.dmSans(fontSize: 12, color: AppColors.accent),
          underline: const SizedBox.shrink(),
          icon: const Icon(Icons.keyboard_arrow_down, color: AppColors.textTertiary, size: 15),
          items: options.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
          onChanged: _busy ? null : (v) { if (v != null) onChanged(v); },
        ),
      ],
    );
  }

  Future<void> _setOverride(String key, dynamic value) async {
    setState(() => _busy = true);
    final updated = Map<String, dynamic>.from(_item.overrides)..addAll({key: value});
    await ClosetService().updateItemOverrides(_item.id, updated);
    await _refresh();
    setState(() => _busy = false);
  }
}
