import 'package:flutter/material.dart';
import 'package:sheserved/core/constants/app_colors.dart';
import 'package:sheserved/features/sport_club/presentation/widgets/sport_club_utils.dart';
import 'package:sheserved/shared/widgets/glass/glass_dialog.dart';
import 'package:sheserved/shared/widgets/glass/glass_primitives.dart';

import '../../../data/coach_models.dart';

/// Draft returned by [CoachReviewDialog.show]. The overall score is the
/// equal-weighted arithmetic mean of the five categories — the reviewer
/// never enters an overall score directly.
typedef CoachReviewDraft =
    ({
      Map<String, int> categoryScores,
      String? comment,
      Set<String> tagIds,
      List<String> customTags,
    });

/// Coach review composer — custom-content GlassDialog (not a bottom sheet).
/// Five mandatory 1–10 category scores with anchored labels, comment
/// 0–500 chars, and standard/custom tags capped at 5.
class CoachReviewDialog extends StatefulWidget {
  final String coachName;
  final List<CoachReviewCategory> categories;
  final List<CoachReviewTag> tagCatalog;

  /// Restored draft for a retry after a failed submit.
  final CoachReviewDraft? initial;

  const CoachReviewDialog({
    super.key,
    required this.coachName,
    required this.categories,
    required this.tagCatalog,
    this.initial,
  });

  static Future<CoachReviewDraft?> show(
    BuildContext context, {
    required String coachName,
    required List<CoachReviewCategory> categories,
    required List<CoachReviewTag> tagCatalog,
    CoachReviewDraft? initial,
  }) {
    return GlassDialog.show<CoachReviewDraft>(
      context: context,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      panelAccentColor: AppColors.primary,
      contentPadding: EdgeInsets.zero,
      builder: (_) => CoachReviewDialog(
        coachName: coachName,
        categories: categories,
        tagCatalog: tagCatalog,
        initial: initial,
      ),
    );
  }

  @override
  State<CoachReviewDialog> createState() => _CoachReviewDialogState();
}

class _CoachReviewDialogState extends State<CoachReviewDialog> {
  static const int maxTags = 5;

  late final Map<String, int> _categoryScores = {
    ...?widget.initial?.categoryScores,
  };
  late final _comment = TextEditingController(
    text: widget.initial?.comment ?? '',
  );
  late final Set<String> _tagIds = {...?widget.initial?.tagIds};
  late final List<String> _customTags = [...?widget.initial?.customTags];
  final _customTagController = TextEditingController();

  bool get _categoriesComplete => widget.categories.every(
    (c) => _categoryScores.containsKey(c.id),
  );

  int get _tagCount => _tagIds.length + _customTags.length;

  double? get _overall {
    if (!_categoriesComplete || widget.categories.isEmpty) return null;
    final sum = widget.categories.fold<int>(
      0,
      (s, c) => s + (_categoryScores[c.id] ?? 0),
    );
    return sum / widget.categories.length;
  }

  @override
  void dispose() {
    _comment.dispose();
    _customTagController.dispose();
    super.dispose();
  }

  void _toggleTag(String tagId, bool selected) {
    setState(() {
      if (selected) {
        if (_tagCount < maxTags) _tagIds.add(tagId);
      } else {
        _tagIds.remove(tagId);
      }
    });
  }

  void _addCustomTag() {
    final label = _customTagController.text.trim();
    if (label.isEmpty || label.length > 60 || _tagCount >= maxTags) return;
    if (_customTags.contains(label)) return;
    _customTagController.clear();
    setState(() => _customTags.add(label));
  }

  @override
  Widget build(BuildContext context) {
    final overall = _overall;
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: 440,
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.rate_review_rounded,
                  color: AppColors.primary,
                  size: 26,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'รีวิวโค้ช ${widget.coachName}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        'ให้คะแนนครบ 5 หมวด (1–10) — คะแนนรวมคำนวณอัตโนมัติ',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: Colors.white.withValues(alpha: 0.65),
                        ),
                      ),
                    ],
                  ),
                ),
                GlassIconButton(
                  icon: Icons.close_rounded,
                  semanticsLabel: 'ปิด',
                  onTap: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final category in widget.categories) ...[
                      LitGlassSurface.frosted(
                        borderRadius: 14,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                category.labelTh,
                                style: const TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF1E293B),
                                ),
                              ),
                              const SizedBox(height: 8),
                              SizedBox(
                                height: 34,
                                child: ListView.separated(
                                  scrollDirection: Axis.horizontal,
                                  itemCount: 10,
                                  separatorBuilder: (_, _) =>
                                      const SizedBox(width: 5),
                                  itemBuilder: (_, i) {
                                    final score = i + 1;
                                    final selected =
                                        _categoryScores[category.id] ==
                                        score;
                                    return GestureDetector(
                                      onTap: () => setState(
                                        () => _categoryScores[category.id] =
                                            score,
                                      ),
                                      child: AnimatedContainer(
                                        duration: const Duration(
                                          milliseconds: 120,
                                        ),
                                        width: 30,
                                        height: 30,
                                        alignment: Alignment.center,
                                        decoration: BoxDecoration(
                                          color: selected
                                              ? AppColors.primary
                                              : Colors.white,
                                          borderRadius:
                                              BorderRadius.circular(9),
                                          border: Border.all(
                                            color: selected
                                                ? AppColors.primaryDark
                                                : Colors.grey.shade300,
                                          ),
                                          boxShadow: selected
                                              ? [
                                                  BoxShadow(
                                                    color: AppColors.primary
                                                        .withValues(
                                                          alpha: 0.35,
                                                        ),
                                                    blurRadius: 6,
                                                    offset: const Offset(
                                                      0,
                                                      2,
                                                    ),
                                                  ),
                                                ]
                                              : null,
                                        ),
                                        child: Text(
                                          '$score',
                                          style: TextStyle(
                                            fontSize: 12.5,
                                            fontWeight: FontWeight.w700,
                                            color: selected
                                                ? Colors.white
                                                : Colors.grey.shade700,
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                              if (_categoryScores[category.id] != null &&
                                  category
                                      .anchorFor(
                                        _categoryScores[category.id]!,
                                      )
                                      .isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Text(
                                  category.anchorFor(
                                    _categoryScores[category.id]!,
                                  ),
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey.shade600,
                                    height: 1.35,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                    if (overall != null) ...[
                      LitGlassSurface.frosted(
                        borderRadius: 14,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.star_rounded,
                                color: AppColors.alertGold,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              const Expanded(
                                child: Text(
                                  'คะแนนรวม (ค่าเฉลี่ย 5 หมวด)',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF475569),
                                  ),
                                ),
                              ),
                              Text(
                                overall.toStringAsFixed(1),
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF1E293B),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                    LitGlassSurface.frosted(
                      borderRadius: 14,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'ความคิดเห็น (ไม่บังคับ)',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF475569),
                              ),
                            ),
                            TextField(
                              controller: _comment,
                              maxLength: 500,
                              maxLines: 3,
                              decoration: const InputDecoration(
                                hintText: 'เล่าประสบการณ์การเรียน…',
                                hintStyle: TextStyle(
                                  fontSize: 12.5,
                                  color: Color(0xFF94A3B8),
                                ),
                                border: InputBorder.none,
                                counterStyle: TextStyle(
                                  fontSize: 10,
                                  color: Color(0xFF94A3B8),
                                ),
                              ),
                              style: const TextStyle(
                                fontSize: 13,
                                color: Color(0xFF1E293B),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'แท็กรีวิว ($_tagCount/$maxTags)',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: Colors.white.withValues(alpha: 0.8),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final tag in widget.tagCatalog)
                          GestureDetector(
                            onTap: () => _toggleTag(
                              tag.id,
                              !_tagIds.contains(tag.id),
                            ),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: _tagIds.contains(tag.id)
                                    ? AppColors.primary.withValues(alpha: 0.3)
                                    : Colors.white.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: _tagIds.contains(tag.id)
                                      ? AppColors.primary
                                      : Colors.white.withValues(alpha: 0.2),
                                ),
                              ),
                              child: Text(
                                tag.labelTh,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  color: _tagIds.contains(tag.id)
                                      ? Colors.white
                                      : Colors.white.withValues(alpha: 0.7),
                                ),
                              ),
                            ),
                          ),
                        for (final label in _customTags)
                          GestureDetector(
                            onTap: () => setState(
                              () => _customTags.remove(label),
                            ),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.accent.withValues(
                                  alpha: 0.25,
                                ),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: AppColors.accent),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    label,
                                    style: const TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  const Icon(
                                    Icons.close_rounded,
                                    size: 12,
                                    color: Colors.white70,
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: LitGlassSurface(
                            borderRadius: 12,
                            blurSigma: 8,
                            fillOpacity: 0.10,
                            rimWidth: 1.2,
                            shadowOpacity: 0.10,
                            child: TextField(
                              controller: _customTagController,
                              maxLength: 60,
                              decoration: InputDecoration(
                                hintText: 'เพิ่มแท็กของคุณเอง',
                                hintStyle: TextStyle(
                                  fontSize: 12,
                                  color: Colors.white.withValues(
                                    alpha: 0.45,
                                  ),
                                ),
                                border: InputBorder.none,
                                counterText: '',
                                contentPadding:
                                    const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 10,
                                    ),
                              ),
                              style: const TextStyle(
                                fontSize: 12.5,
                                color: Colors.white,
                              ),
                              onSubmitted: (_) => _addCustomTag(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        GlassIconButton(
                          icon: Icons.add_rounded,
                          semanticsLabel: 'เพิ่มแท็ก',
                          onTap: _tagCount < maxTags ? _addCustomTag : null,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: GlassActionButton(
                    label: 'ยกเลิก',
                    onTap: () => Navigator.of(context).pop(),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: GlassActionButton(
                    label: 'ส่งรีวิว',
                    isFilled: true,
                    fillColor: AppColors.primary,
                    onTap: _categoriesComplete
                        ? () => Navigator.of(context).pop((
                            categoryScores: Map.of(_categoryScores),
                            comment: _comment.text.trim().isEmpty
                                ? null
                                : _comment.text.trim(),
                            tagIds: _tagIds,
                            customTags: _customTags,
                          ))
                        : null,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Coach full-reviews dialog — summary bands, category averages, topic
/// chips, rating filter and sort with server-side pagination.
class CoachReviewsDialog extends StatefulWidget {
  final CoachSummary coach;
  final Future<CoachReviewSummaryV2> Function() loadSummary;
  final Future<(List<CoachReview>, int)> Function({
    String? tagId,
    double? minRating10,
    double? maxRating10,
    String sort,
    int limit,
    int offset,
  })
  loadReviews;
  final Future<void> Function(CoachReview review, bool helpful)?
  onToggleHelpful;
  final Future<void> Function(CoachReview review)? onModerate;

  const CoachReviewsDialog({
    super.key,
    required this.coach,
    required this.loadSummary,
    required this.loadReviews,
    this.onToggleHelpful,
    this.onModerate,
  });

  static Future<void> show(
    BuildContext context, {
    required CoachSummary coach,
    required Future<CoachReviewSummaryV2> Function() loadSummary,
    required Future<(List<CoachReview>, int)> Function({
      String? tagId,
      double? minRating10,
      double? maxRating10,
      String sort,
      int limit,
      int offset,
    })
    loadReviews,
    Future<void> Function(CoachReview review, bool helpful)? onToggleHelpful,
    Future<void> Function(CoachReview review)? onModerate,
  }) {
    return GlassDialog.show<void>(
      context: context,
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 20),
      panelAccentColor: AppColors.primary,
      contentPadding: EdgeInsets.zero,
      builder: (_) => CoachReviewsDialog(
        coach: coach,
        loadSummary: loadSummary,
        loadReviews: loadReviews,
        onToggleHelpful: onToggleHelpful,
        onModerate: onModerate,
      ),
    );
  }

  @override
  State<CoachReviewsDialog> createState() => _CoachReviewsDialogState();
}

class _CoachReviewsDialogState extends State<CoachReviewsDialog> {
  static const _pageSize = 10;

  /// Rating buckets matching the five-band scale.
  static const _bands = <String, (double, double)>{
    'excellent': (9.0, 10.0),
    'good': (7.0, 8.9),
    'fair': (5.0, 6.9),
    'poor': (3.0, 4.9),
    'bad': (1.0, 2.9),
  };
  static const _bandLabels = <String, String>{
    'excellent': 'ดีเลิศ',
    'good': 'ดี',
    'fair': 'พอใช้ได้',
    'poor': 'แย่',
    'bad': 'แย่มาก',
  };
  static const _sortLabels = <String, String>{
    'helpful': 'มีประโยชน์ที่สุด',
    'newest': 'ใหม่สุด',
    'highest': 'คะแนนสูงสุด',
    'lowest': 'คะแนนต่ำสุด',
  };

  CoachReviewSummaryV2? _summary;
  List<CoachReview> _reviews = [];
  int _total = 0;
  bool _loadingSummary = true;
  bool _loading = true;
  bool _loadingMore = false;
  String _sort = 'helpful';
  String? _band;
  String? _tagId;
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _loadAll();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients || _loading || _loadingMore) return;
    if (_reviews.length >= _total) return;
    if (_scroll.position.pixels >=
        _scroll.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  Future<void> _loadAll() async {
    try {
      final summary = await widget.loadSummary();
      if (!mounted) return;
      setState(() {
        _summary = summary;
        _loadingSummary = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingSummary = false);
    }
    await _reload();
  }

  Future<void> _reload() async {
    setState(() => _loading = true);
    try {
      final band = _band == null ? null : _bands[_band];
      final (reviews, total) = await widget.loadReviews(
        tagId: _tagId,
        minRating10: band?.$1,
        maxRating10: band?.$2,
        sort: _sort,
        limit: _pageSize,
        offset: 0,
      );
      if (!mounted) return;
      setState(() {
        _reviews = reviews;
        _total = total;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    setState(() => _loadingMore = true);
    try {
      final band = _band == null ? null : _bands[_band];
      final (reviews, total) = await widget.loadReviews(
        tagId: _tagId,
        minRating10: band?.$1,
        maxRating10: band?.$2,
        sort: _sort,
        limit: _pageSize,
        offset: _reviews.length,
      );
      if (!mounted) return;
      setState(() {
        _reviews = [..._reviews, ...reviews];
        _total = total;
        _loadingMore = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: 480,
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.reviews_rounded,
                  color: AppColors.primary,
                  size: 24,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'รีวิว ${widget.coach.displayName}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                GlassIconButton(
                  icon: Icons.close_rounded,
                  semanticsLabel: 'ปิด',
                  onTap: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Flexible(
              child: ListView(
                controller: _scroll,
                shrinkWrap: true,
                children: [
                  if (_loadingSummary)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (_summary != null)
                    _summaryCard(_summary!),
                  const SizedBox(height: 10),
                  _filterBar(),
                  const SizedBox(height: 10),
                  if (_loading)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (_reviews.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Center(
                        child: Text(
                          'ไม่มีรีวิวตามตัวกรองนี้',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.white.withValues(alpha: 0.65),
                          ),
                        ),
                      ),
                    )
                  else
                    for (final r in _reviews) _reviewTile(r),
                  if (_loadingMore)
                    const Padding(
                      padding: EdgeInsets.all(12),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryCard(CoachReviewSummaryV2 s) {
    final maxCount = s.bandCounts.values.fold<int>(
      0,
      (a, b) => a > b ? a : b,
    );
    return LitGlassSurface.frosted(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  s.averageRating?.toStringAsFixed(1) ?? '-',
                  style: const TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF1E293B),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'เต็ม 10\n${s.reviewCount} รีวิว · อ้างอิงการเรียนที่เสร็จสิ้น',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: Colors.grey.shade600,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            for (final band in _bands.entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: GestureDetector(
                  onTap: () {
                    setState(
                      () => _band = _band == band.key ? null : band.key,
                    );
                    _reload();
                  },
                  child: Row(
                    children: [
                      SizedBox(
                        width: 60,
                        child: Text(
                          '${_bandLabels[band.key]}',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: _band == band.key
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: _band == band.key
                                ? AppColors.primaryDark
                                : const Color(0xFF475569),
                          ),
                        ),
                      ),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: maxCount == 0
                                ? 0
                                : (s.bandCounts[band.key] ?? 0) / maxCount,
                            minHeight: 8,
                            backgroundColor: Colors.grey.shade200,
                            valueColor: AlwaysStoppedAnimation(
                              _band == band.key
                                  ? AppColors.primaryDark
                                  : AppColors.primary,
                            ),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 30,
                        child: Text(
                          '${s.bandCounts[band.key] ?? 0}',
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (s.categories.isNotEmpty) ...[
              const SizedBox(height: 8),
              const Divider(height: 1),
              const SizedBox(height: 8),
              for (final c in s.categories)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          c.labelTh,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF475569),
                          ),
                        ),
                      ),
                      Text(
                        c.average?.toStringAsFixed(1) ?? '-',
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                      Text(
                        '  (${c.sampleCount})',
                        style: TextStyle(
                          fontSize: 10.5,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
            if (s.topics.isNotEmpty) ...[
              const SizedBox(height: 8),
              const Divider(height: 1),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final t in s.topics.take(8))
                    GestureDetector(
                      onTap: () {
                        setState(
                          () => _tagId = _tagId == t.tagId ? null : t.tagId,
                        );
                        _reload();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: _tagId == t.tagId
                              ? AppColors.primary.withValues(alpha: 0.25)
                              : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(9),
                          border: Border.all(
                            color: _tagId == t.tagId
                                ? AppColors.primaryDark
                                : Colors.grey.shade300,
                          ),
                        ),
                        child: Text(
                          '${t.labelTh} (${t.reviewCount})',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: _tagId == t.tagId
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: _tagId == t.tagId
                                ? AppColors.primaryDark
                                : const Color(0xFF475569),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _filterBar() {
    return Row(
      children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _sortChip('helpful'),
                _sortChip('newest'),
                _sortChip('highest'),
                _sortChip('lowest'),
              ],
            ),
          ),
        ),
        if (_band != null || _tagId != null)
          GestureDetector(
            onTap: () {
              setState(() {
                _band = null;
                _tagId = null;
              });
              _reload();
            },
            child: Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Text(
                'ล้างตัวกรอง',
                style: TextStyle(
                  fontSize: 11.5,
                  color: Colors.white.withValues(alpha: 0.75),
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _sortChip(String key) {
    final selected = _sort == key;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: GestureDetector(
        onTap: () {
          setState(() => _sort = key);
          _reload();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.primary.withValues(alpha: 0.3)
                : Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected
                  ? AppColors.primary
                  : Colors.white.withValues(alpha: 0.2),
            ),
          ),
          child: Text(
            _sortLabels[key] ?? key,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: selected
                  ? Colors.white
                  : Colors.white.withValues(alpha: 0.7),
            ),
          ),
        ),
      ),
    );
  }

  Widget _reviewTile(CoachReview r) {
    final rating = r.rating10 ?? r.rating.toDouble();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: LitGlassSurface.frosted(
        borderRadius: 14,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 15,
                    backgroundImage:
                        (r.userAvatarUrl?.isNotEmpty == true)
                        ? NetworkImage(r.userAvatarUrl!)
                        : null,
                    child: r.userAvatarUrl?.isNotEmpty == true
                        ? null
                        : const Icon(Icons.person, size: 15),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          r.userDisplayName ?? 'ผู้ใช้',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF1E293B),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          [
                            'ยืนยันการเรียนแล้ว',
                            if (r.isLegacy) 'คะแนนเดิม 1–5',
                            if (r.createdAt != null)
                              formatThaiBuddhistDateTime(
                                r.createdAt!.toLocal(),
                              ),
                          ].join(' · '),
                          style: TextStyle(
                            fontSize: 10.5,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Text(
                      rating.toStringAsFixed(1),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primaryDark,
                      ),
                    ),
                  ),
                ],
              ),
              if (r.comment?.isNotEmpty == true) ...[
                const SizedBox(height: 8),
                Text(
                  r.comment!,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: Color(0xFF334155),
                    height: 1.4,
                  ),
                ),
              ],
              if (r.tagLabels.isNotEmpty) ...[
                const SizedBox(height: 6),
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: [
                    for (final t in r.tagLabels)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2.5,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(7),
                        ),
                        child: Text(
                          t,
                          style: TextStyle(
                            fontSize: 10.5,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 8),
              Row(
                children: [
                  GestureDetector(
                    onTap: widget.onToggleHelpful == null
                        ? null
                        : () async {
                            await widget.onToggleHelpful!(
                              r,
                              !r.viewerVoted,
                            );
                            if (mounted) await _reload();
                          },
                    child: Row(
                      children: [
                        Icon(
                          r.viewerVoted
                              ? Icons.thumb_up_alt_rounded
                              : Icons.thumb_up_alt_outlined,
                          size: 15,
                          color: r.viewerVoted
                              ? AppColors.primaryDark
                              : Colors.grey.shade500,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'มีประโยชน์ (${r.helpfulCount})',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: r.viewerVoted
                                ? AppColors.primaryDark
                                : Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  if (widget.onModerate != null)
                    GestureDetector(
                      onTap: () => widget.onModerate!(r),
                      child: Text(
                        'จัดการรีวิว',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade500,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Admin moderation detail — hide/reject/publish a coach review.
class CoachReviewModerationDialog {
  static Future<String?> show(
    BuildContext context, {
    required CoachReview review,
  }) {
    return GlassDialog.show<String>(
      context: context,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      panelAccentColor: AppColors.accent,
      contentPadding: EdgeInsets.zero,
      builder: (ctx) => ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 340),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'จัดการรีวิว',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 10),
              LitGlassSurface.frosted(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${review.userDisplayName ?? 'ผู้ใช้'} · '
                        '${(review.rating10 ?? review.rating.toDouble()).toStringAsFixed(1)}/10',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                      if (review.comment?.isNotEmpty == true)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            review.comment!,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade700,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: GlassActionButton(
                      label: 'ซ่อน',
                      isFilled: true,
                      fillColor: const Color(0xFFEF6C00),
                      onTap: () => Navigator.of(ctx).pop('hide'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: GlassActionButton(
                      label: 'ปฏิเสธ',
                      isFilled: true,
                      fillColor: const Color(0xFFC62828),
                      onTap: () => Navigator.of(ctx).pop('reject'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: GlassActionButton(
                      label: 'เผยแพร่',
                      isFilled: true,
                      fillColor: AppColors.primary,
                      onTap: () => Navigator.of(ctx).pop('publish'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Center(
                child: GestureDetector(
                  onTap: () => Navigator.of(ctx).pop(),
                  child: Text(
                    'ปิด',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.6),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
