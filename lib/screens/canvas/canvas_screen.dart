import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme.dart';
import '../../models/clothing_item.dart';
import '../../models/outfit.dart';
import '../../services/closet_service.dart';
import '../../services/outfit_generator.dart';
import '../../services/outfit_service.dart';
import '../../services/preference_service.dart';
import 'saved_outfit_detail_screen.dart';

class CanvasScreen extends StatefulWidget {
  const CanvasScreen({super.key});

  @override
  State<CanvasScreen> createState() => _CanvasScreenState();
}

class _CanvasScreenState extends State<CanvasScreen> {
  final _closet = ClosetService();
  final _outfitService = OutfitService();

  bool _loading = true;

  ClothingItem? _top;
  ClothingItem? _bottom;
  ClothingItem? _shoes;
  ClothingItem? _outerwear;

  List<Outfit> _savedResolved = [];

  bool get _manualComplete => _top != null && _bottom != null && _shoes != null;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _closet.load();
    await _outfitService.load();
    _refreshSaved();
    setState(() => _loading = false);
  }

  void _refreshSaved() {
    _savedResolved = _outfitService.saved
        .map((json) => _outfitService.resolveOutfit(json, _closet.items))
        .whereType<Outfit>()
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.background,
          title: Text(
            'Canvas',
            style: GoogleFonts.cormorantGaramond(
              fontSize: 26,
              fontWeight: FontWeight.w500,
              color: AppColors.textPrimary,
            ),
          ),
          centerTitle: false,
          actions: [
            IconButton(
              tooltip: 'Clear selections',
              onPressed: _clearSelection,
              icon: const Icon(Icons.refresh, color: AppColors.textTertiary, size: 20),
            ),
          ],
          bottom: TabBar(
            labelColor: AppColors.accent,
            unselectedLabelColor: AppColors.textTertiary,
            indicatorColor: AppColors.accent,
            indicatorWeight: 1.5,
            dividerColor: AppColors.border,
            labelStyle: GoogleFonts.dmSans(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.8,
            ),
            tabs: const [
              Tab(text: 'BUILD'),
              Tab(text: 'GENERATE'),
              Tab(text: 'SAVED'),
            ],
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator(color: AppColors.accent))
            : TabBarView(
                children: [
                  _buildTab(),
                  _generateTab(),
                  _savedTab(),
                ],
              ),
      ),
    );
  }

  // ─── BUILD tab ───────────────────────────────────────────────────────────────

  Widget _buildTab() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      children: [
        Text('Build an outfit',
            style: GoogleFonts.cormorantGaramond(fontSize: 26, fontWeight: FontWeight.w500, color: AppColors.textPrimary)),
        const SizedBox(height: 4),
        Text('Tap a slot to pick from your closet.',
            style: GoogleFonts.dmSans(fontSize: 13, color: AppColors.textSecondary)),
        const SizedBox(height: 20),
        Row(children: [
          Expanded(child: _slotCard('Top', _top, () => _pickItem(ClothingCategory.tops), onClear: () => setState(() => _top = null))),
          const SizedBox(width: 12),
          Expanded(child: _slotCard('Bottom', _bottom, () => _pickItem(ClothingCategory.bottoms), onClear: () => setState(() => _bottom = null))),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _slotCard('Shoes', _shoes, () => _pickItem(ClothingCategory.shoes), onClear: () => setState(() => _shoes = null))),
          const SizedBox(width: 12),
          Expanded(child: _slotCard('Outerwear', _outerwear, () => _pickItem(ClothingCategory.outerwear), optional: true, onClear: () => setState(() => _outerwear = null))),
        ]),
        const SizedBox(height: 24),
        SizedBox(
          height: 52,
          child: ElevatedButton(
            onPressed: _manualComplete ? _saveManualOutfit : null,
            child: Text('SAVE OUTFIT',
                style: GoogleFonts.dmSans(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1.4, color: AppColors.background)),
          ),
        ),
      ],
    );
  }

  Widget _slotCard(String label, ClothingItem? item, VoidCallback onPick, {bool optional = false, VoidCallback? onClear}) {
    return GestureDetector(
      onTap: onPick,
      child: Container(
        height: 160,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: item != null ? AppColors.accent.withValues(alpha: 0.4) : AppColors.border, width: 0.5),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: item == null
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add, size: 22, color: optional ? AppColors.textTertiary : AppColors.textSecondary),
                    const SizedBox(height: 6),
                    Text(label, textAlign: TextAlign.center,
                        style: GoogleFonts.dmSans(fontSize: 13, fontWeight: FontWeight.w600, color: optional ? AppColors.textTertiary : AppColors.textSecondary)),
                    if (optional) ...[const SizedBox(height: 2), Text('optional', style: GoogleFonts.dmSans(fontSize: 10, color: AppColors.textTertiary))],
                  ],
                )
              : Stack(fit: StackFit.expand, children: [
                  Image.file(File(item.imagePath), fit: BoxFit.contain),
                  Positioned(
                    bottom: 8, left: 0, right: 0,
                    child: Center(child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(color: AppColors.background.withValues(alpha: 0.75), borderRadius: BorderRadius.circular(6)),
                      child: Text(label, style: GoogleFonts.dmSans(color: AppColors.textPrimary, fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
                    )),
                  ),
                  if (onClear != null)
                    Positioned(
                      top: 6, right: 6,
                      child: GestureDetector(
                        onTap: onClear,
                        child: Container(
                          width: 24, height: 24,
                          decoration: BoxDecoration(color: AppColors.background.withValues(alpha: 0.80), shape: BoxShape.circle),
                          child: const Icon(Icons.close, size: 14, color: AppColors.textPrimary),
                        ),
                      ),
                    ),
                ]),
        ),
      ),
    );
  }

  // ─── GENERATE tab ────────────────────────────────────────────────────────────

  Widget _generateTab() {
    return _GenerateSetup(
      closet: _closet,
      onOpenSwipeScreen: (prefs, occasion, weather, workType) async {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => OutfitSwipeScreen(
              closet: _closet,
              outfitService: _outfitService,
              prefs: prefs,
              occasion: occasion,
              weather: weather,
              workType: workType,
              onSavedChanged: () => setState(_refreshSaved),
            ),
          ),
        );
      },
    );
  }

  // ─── SAVED tab ────────────────────────────────────────────────────────────────

  Widget _savedTab() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      children: [
        Text('Saved outfits',
            style: GoogleFonts.cormorantGaramond(fontSize: 26, fontWeight: FontWeight.w500, color: AppColors.textPrimary)),
        const SizedBox(height: 16),
        if (_savedResolved.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Center(child: Text('No saved outfits yet.', style: GoogleFonts.dmSans(color: AppColors.textSecondary, fontSize: 14))),
          )
        else
          ..._savedResolved.map((o) => _SavedOutfitRow(outfit: o, onDeleted: () async {
            await _outfitService.load();
            setState(_refreshSaved);
          })),
        if (_savedResolved.isNotEmpty) ...[
          const SizedBox(height: 12),
          TextButton(
            onPressed: () async {
              await _outfitService.clearAll();
              await _outfitService.load();
              setState(_refreshSaved);
            },
            child: Text('Clear all saved outfits', style: GoogleFonts.dmSans(color: AppColors.error, fontSize: 13)),
          ),
        ],
      ],
    );
  }

  Future<void> _pickItem(ClothingCategory category) async {
    final options = _closet.byCategory(category);
    if (options.isEmpty) return;
    final picked = await showModalBottomSheet<ClothingItem>(
      context: context,
      showDragHandle: true,
      backgroundColor: AppColors.surface,
      builder: (context) => SafeArea(
        child: GridView.builder(
          padding: const EdgeInsets.all(14),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 10, mainAxisSpacing: 10),
          itemCount: options.length,
          itemBuilder: (context, i) {
            final item = options[i];
            return GestureDetector(
              onTap: () => Navigator.pop(context, item),
              child: Container(
                decoration: BoxDecoration(color: AppColors.surfaceElevated, borderRadius: BorderRadius.circular(12)),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.file(File(item.imagePath), fit: BoxFit.contain),
                ),
              ),
            );
          },
        ),
      ),
    );
    if (picked == null) return;
    setState(() {
      if (category == ClothingCategory.tops) _top = picked;
      if (category == ClothingCategory.bottoms) _bottom = picked;
      if (category == ClothingCategory.shoes) _shoes = picked;
      if (category == ClothingCategory.outerwear) _outerwear = picked;
    });
  }

  void _clearSelection() => setState(() { _top = null; _bottom = null; _shoes = null; _outerwear = null; });

  Future<void> _saveManualOutfit() async {
    final outfit = Outfit(top: _top!, bottom: _bottom!, shoes: _shoes!, outerwear: _outerwear, score: 0, reasons: const []);
    await _outfitService.saveOutfit(outfit);
    await _outfitService.load();
    setState(_refreshSaved);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Outfit saved')));
  }
}

// ─── Generate Setup ───────────────────────────────────────────────────────────

class _GenerateSetup extends StatefulWidget {
  final ClosetService closet;
  final Future<void> Function(PreferenceService, String, String, String) onOpenSwipeScreen;

  const _GenerateSetup({required this.closet, required this.onOpenSwipeScreen});

  @override
  State<_GenerateSetup> createState() => _GenerateSetupState();
}

class _GenerateSetupState extends State<_GenerateSetup> {
  final _prefs = PreferenceService();

  String _occasion = 'Any';
  String _weather  = 'Any';
  String _workType = 'Business Casual';

  static const _occasionOptions = ['Any', 'Everyday', 'Work', 'Evening', 'Weekend'];
  static const _weatherOptions  = ['Any', 'Cold', 'Mild', 'Warm'];
  static const _workTypeOptions = ['Corporate', 'Business Casual', 'Manual & Trade'];

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
      children: [
        Text('Generate outfits',
            style: GoogleFonts.cormorantGaramond(fontSize: 26, fontWeight: FontWeight.w500, color: AppColors.textPrimary)),
        const SizedBox(height: 4),
        Text('Set the mood, then swipe through looks.',
            style: GoogleFonts.dmSans(fontSize: 13, color: AppColors.textSecondary)),
        const SizedBox(height: 28),

        _label('OCCASION'),
        const SizedBox(height: 10),
        _chips(_occasionOptions, _occasion, (v) => setState(() => _occasion = v)),
        const SizedBox(height: 22),

        // Only relevant when generating for "Work" — lets the algorithm
        // tailor formality and material/footwear choices to the job type.
        if (_occasion == 'Work') ...[
          _label('WORK TYPE'),
          const SizedBox(height: 10),
          _chips(_workTypeOptions, _workType, (v) => setState(() => _workType = v)),
          const SizedBox(height: 22),
        ],

        _label('WEATHER'),
        const SizedBox(height: 10),
        _chips(_weatherOptions, _weather, (v) => setState(() => _weather = v)),
        const SizedBox(height: 36),

        SizedBox(
          height: 52,
          child: ElevatedButton(
            onPressed: () async {
              await widget.onOpenSwipeScreen(_prefs, _occasion, _weather, _workType);
              // Reset after returning (work type is kept — it's a stable
              // preference about the user's job, not a one-off mood).
              setState(() { _occasion = 'Any'; _weather = 'Any'; });
            },
            child: Text('GENERATE',
                style: GoogleFonts.dmSans(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1.4, color: AppColors.background)),
          ),
        ),
      ],
    );
  }

  Widget _label(String text) => Text(text,
      style: GoogleFonts.dmSans(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.2, color: AppColors.textTertiary));

  Widget _chips(List<String> options, String selected, void Function(String) onTap) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: options.map((opt) {
        final active = opt == selected;
        return GestureDetector(
          onTap: () => onTap(opt),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
            decoration: BoxDecoration(
              color: active ? AppColors.accentSubtle : Colors.transparent,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: active ? AppColors.accent : AppColors.border, width: active ? 1.0 : 0.5),
            ),
            child: Text(opt,
                style: GoogleFonts.dmSans(
                    fontSize: 13,
                    fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                    color: active ? AppColors.accent : AppColors.textSecondary)),
          ),
        );
      }).toList(),
    );
  }
}

// ─── Outfit Swipe Screen ──────────────────────────────────────────────────────

class OutfitSwipeScreen extends StatefulWidget {
  final ClosetService closet;
  final OutfitService outfitService;
  final PreferenceService prefs;
  final String occasion;
  final String weather;
  final String workType;
  final VoidCallback onSavedChanged;

  const OutfitSwipeScreen({
    super.key,
    required this.closet,
    required this.outfitService,
    required this.prefs,
    required this.occasion,
    required this.weather,
    required this.workType,
    required this.onSavedChanged,
  });

  @override
  State<OutfitSwipeScreen> createState() => _OutfitSwipeScreenState();
}

class _OutfitSwipeScreenState extends State<OutfitSwipeScreen> {
  final _generator = OutfitGenerator();

  bool _generating = false;
  final List<Outfit> _deck = [];
  int _deckVersion = 0;

  /// Set when the closet doesn't have enough occasion-appropriate pieces.
  /// Shown as a banner above the deck so the user knows the result is a
  /// best-effort match, not a false promise.
  bool _lowCoverage = false;
  String? _coverageHint;

  /// Signatures of outfits shown this session — regenerate skips these for variety
  final Set<String> _shownThisSession = {};

  Outfit? get _current => _deck.isEmpty ? null : _deck.first;

  // Map 3 UI params → generator's internal params
  String? get _mappedOccasion => switch (widget.occasion) {
    'Everyday' => 'Casual',
    'Work'     => 'Work',
    'Evening'  => 'Date',
    'Weekend'  => 'Casual',
    _          => null,
  };

  // Work-type sub-toggle — only meaningful when occasion is "Work".
  String? get _mappedWorkType => widget.occasion == 'Work' ? widget.workType : null;

  String? get _mappedStyle => switch (widget.occasion) {
    // Manual & Trade work isn't "Classic" styling — leave style unconstrained
    // so practical/durable pieces aren't penalised for not looking polished.
    'Work'    => _mappedWorkType == 'Manual & Trade' ? null : 'Classic',
    'Evening' => 'Classic',
    _         => null,
  };

  String get _mappedWeather => switch (widget.weather) {
    'Cold' => 'Cold',
    'Mild' => 'Mild',
    'Warm' => 'Hot',
    _      => 'Any',
  };

  String? get _mappedPalette => null; // palette filter removed from UI

  @override
  void initState() {
    super.initState();
    _regenerate();
  }

  Future<void> _regenerate() async {
    if (_generating) return;
    setState(() => _generating = true);

    try {
      final disliked = await widget.prefs.getDislikedOutfits();
      final weights  = await widget.prefs.getItemLikeWeights();
      final recent   = (await widget.prefs.getRecentItemIds()).toSet();

      final result = _generator.generate(
        closet: widget.closet.items,
        desiredStyle: _mappedStyle,
        desiredSeason: null,
        colorMode: _mappedPalette,
        desiredOccasion: _mappedOccasion,
        workType: _mappedWorkType,
        weatherTemp: _mappedWeather,
        isRaining: false,
        isWindy: false,
        maxResults: 12,
        allowOuterwear: true,
        dislikedOutfitSignatures: disliked,
        shownSignatures: _shownThisSession,
        itemLikeWeights: weights,
        recentItemIds: recent,
        signatureFn: widget.prefs.signatureForOutfit,
      );

      final outfits = result.outfits;

      // If we've shown everything already, reset tracking so future
      // regenerates can vary again instead of repeating the same set forever.
      if (result.exhausted) {
        _shownThisSession.clear();
      }

      // Track what we showed so next regenerate is different
      for (final o in outfits) {
        _shownThisSession.add(widget.prefs.signatureForOutfit(o));
      }

      setState(() {
        _deckVersion++;
        _deck..clear()..addAll(outfits);
        _generating = false;
        _lowCoverage = result.lowCoverage;
        _coverageHint = result.coverageHint;
      });

      await widget.prefs.markOutfitsShown(outfits);

      if (result.exhausted && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              "You've seen all the best combos for this closet — add more items for fresh looks",
              style: GoogleFonts.dmSans(fontSize: 13, color: AppColors.textPrimary),
            ),
            backgroundColor: AppColors.surface,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 3),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } catch (_) {
      setState(() => _generating = false);
    }
  }

  void _skipCurrent(Outfit outfit, {bool like = false}) {
    setState(() {
      if (_deck.isNotEmpty) _deck.removeAt(0);
    });
    if (like) {
      widget.prefs.likeOutfit(outfit);
    } else {
      widget.prefs.dislikeOutfit(outfit);
    }
    if (_deck.isEmpty && !_generating) _regenerate();
  }

  Future<void> _saveOutfit(Outfit o) async {
    await widget.outfitService.saveOutfit(o);
    await widget.outfitService.load();
    widget.onSavedChanged();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Saved — swipe to continue',
              style: GoogleFonts.dmSans(fontSize: 13, color: AppColors.textPrimary)),
          backgroundColor: AppColors.surface,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final outfit = _current;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18, color: AppColors.textSecondary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Outfits',
            style: GoogleFonts.cormorantGaramond(fontSize: 22, fontWeight: FontWeight.w500, color: AppColors.textPrimary)),
        actions: [
          // Subtle regenerate button top-right
          IconButton(
            tooltip: 'New looks',
            onPressed: _generating ? null : _regenerate,
            icon: Icon(Icons.auto_awesome_outlined, size: 20,
                color: _generating ? AppColors.textTertiary : AppColors.textSecondary),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
          child: Column(
            children: [
              // Low-coverage notice — closet doesn't have occasion-appropriate
              // pieces, so this deck is the closest available match.
              if (_lowCoverage && _coverageHint != null && !_generating && outfit != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _coverageBanner(_coverageHint!),
                ),

              // Swipe direction hints
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(children: [
                      Icon(Icons.close_rounded, size: 13, color: AppColors.error.withValues(alpha: 0.7)),
                      const SizedBox(width: 4),
                      Text('Skip', style: GoogleFonts.dmSans(fontSize: 11, color: AppColors.error.withValues(alpha: 0.7), fontWeight: FontWeight.w500)),
                    ]),
                    Row(children: [
                      Text('Like', style: GoogleFonts.dmSans(fontSize: 11, color: AppColors.success.withValues(alpha: 0.7), fontWeight: FontWeight.w500)),
                      const SizedBox(width: 4),
                      Icon(Icons.favorite_border, size: 13, color: AppColors.success.withValues(alpha: 0.7)),
                    ]),
                  ],
                ),
              ),

              // Outfit card
              Expanded(
                child: _generating
                    ? const Center(child: CircularProgressIndicator(color: AppColors.accent))
                    : outfit == null
                        ? _emptyState()
                        : _swipeCard(outfit),
              ),

              const SizedBox(height: 14),

              // Single action: save (stays on current card)
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: outfit == null ? null : () => _saveOutfit(outfit),
                  icon: const Icon(Icons.bookmark_border, size: 18),
                  label: Text('SAVE OUTFIT',
                      style: GoogleFonts.dmSans(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1.2, color: AppColors.background)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _coverageBanner(String hint) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.textTertiary.withValues(alpha: 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 16, color: AppColors.textSecondary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              hint,
              style: GoogleFonts.dmSans(fontSize: 12, color: AppColors.textSecondary, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState() {
    final items = widget.closet.items;
    final hasTops    = items.any((i) => i.category == ClothingCategory.tops);
    final hasBottoms = items.any((i) => i.category == ClothingCategory.bottoms);
    final missing = [if (!hasTops) 'tops', if (!hasBottoms) 'bottoms'];

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.checkroom_outlined, size: 40, color: AppColors.textTertiary),
            const SizedBox(height: 14),
            Text(
              missing.isEmpty ? 'All looks explored' : 'Not enough items yet',
              style: GoogleFonts.cormorantGaramond(fontSize: 22, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 6),
            Text(
              missing.isEmpty
                  ? 'Tap ✦ in the top-right for fresh looks.'
                  : 'Add ${missing.join(' and ')} to your closet.',
              textAlign: TextAlign.center,
              style: GoogleFonts.dmSans(fontSize: 13, color: AppColors.textTertiary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _swipeCard(Outfit outfit) {
    final key = ValueKey('${_deckVersion}_${widget.prefs.signatureForOutfit(outfit)}');

    return Dismissible(
      key: key,
      direction: DismissDirection.horizontal,
      onDismissed: (dir) {
        _skipCurrent(outfit, like: dir == DismissDirection.startToEnd);
      },
      background: _swipeBg(left: false),       // swipe right bg
      secondaryBackground: _swipeBg(left: true), // swipe left bg
      child: _outfitCard(outfit),
    );
  }

  Widget _swipeBg({required bool left}) {
    // left=true  → dragging LEFT  → Skip (red)
    // left=false → dragging RIGHT → Like (green)
    final color = left ? AppColors.error : AppColors.success;
    final icon  = left ? Icons.close_rounded : Icons.favorite_border;
    final label = left ? 'SKIP' : 'LIKE';

    return Container(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.35), width: 0.5),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 28),
      alignment: left ? Alignment.centerRight : Alignment.centerLeft,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 30, color: color),
          const SizedBox(height: 6),
          Text(label,
              style: GoogleFonts.dmSans(
                  fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.0, color: color)),
        ],
      ),
    );
  }

  Widget _outfitCard(Outfit outfit) {
    final hasOuterwear = outfit.outerwear != null;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      padding: const EdgeInsets.all(10),
      child: hasOuterwear ? _grid2x2(outfit) : _grid3Items(outfit),
    );
  }

  Widget _grid2x2(Outfit outfit) {
    return Column(children: [
      Expanded(child: Row(children: [
        Expanded(child: _itemCell(outfit.top, 'Top')),
        const SizedBox(width: 8),
        Expanded(child: _itemCell(outfit.bottom, 'Bottom')),
      ])),
      const SizedBox(height: 8),
      Expanded(child: Row(children: [
        Expanded(child: _itemCell(outfit.outerwear!, 'Outer')),
        const SizedBox(width: 8),
        Expanded(child: outfit.shoes != null ? _itemCell(outfit.shoes!, 'Shoes') : _emptyCell('Shoes')),
      ])),
    ]);
  }

  Widget _grid3Items(Outfit outfit) {
    return Column(children: [
      Expanded(flex: 3, child: _itemCell(outfit.top, 'Top')),
      const SizedBox(height: 8),
      Expanded(flex: 2, child: Row(children: [
        Expanded(child: _itemCell(outfit.bottom, 'Bottom')),
        const SizedBox(width: 8),
        Expanded(child: outfit.shoes != null ? _itemCell(outfit.shoes!, 'Shoes') : _emptyCell('Shoes')),
      ])),
    ]);
  }

  Widget _itemCell(ClothingItem item, String label) {
    return Container(
      decoration: BoxDecoration(color: AppColors.surfaceElevated, borderRadius: BorderRadius.circular(12)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.file(File(item.imagePath), fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Center(child: Icon(Icons.image_not_supported_outlined, color: AppColors.textTertiary))),
            Positioned(
              bottom: 6, left: 0, right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: AppColors.background.withValues(alpha: 0.70), borderRadius: BorderRadius.circular(5)),
                  child: Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.dmSans(fontSize: 9, fontWeight: FontWeight.w500, color: AppColors.textSecondary, letterSpacing: 0.3),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyCell(String label) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.add_circle_outline, color: AppColors.textTertiary, size: 20),
          const SizedBox(height: 4),
          Text(label, style: GoogleFonts.dmSans(fontSize: 9, color: AppColors.textTertiary, fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }
}

// ─── Saved Outfit Row ─────────────────────────────────────────────────────────

class _SavedOutfitRow extends StatelessWidget {
  final Outfit outfit;
  final VoidCallback? onDeleted;
  const _SavedOutfitRow({required this.outfit, this.onDeleted});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.push(context,
          MaterialPageRoute(builder: (_) => SavedOutfitDetailScreen(outfit: outfit, onDeleted: onDeleted))),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border, width: 0.5),
        ),
        child: Row(
          children: [
            ...outfit.items.take(4).map((item) => Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Container(
                width: 72, height: 72,
                decoration: BoxDecoration(color: AppColors.surfaceElevated, borderRadius: BorderRadius.circular(10)),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.file(File(item.imagePath), fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const Icon(Icons.image_not_supported_outlined, color: AppColors.textTertiary, size: 18)),
                ),
              ),
            )),
            const Spacer(),
            const Icon(Icons.chevron_right, color: AppColors.textTertiary, size: 18),
          ],
        ),
      ),
    );
  }
}
