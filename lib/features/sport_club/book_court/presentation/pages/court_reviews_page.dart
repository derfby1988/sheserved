import 'package:flutter/material.dart';
import 'package:sheserved/core/constants/app_colors.dart';
import 'package:sheserved/services/auth_service.dart';
import 'package:sheserved/shared/widgets/neumorphic/neumorphic.dart';

import '../../data/book_court_models.dart';
import '../../data/book_court_repository.dart';

/// Full review page for one venue: overall/category summary, rating
/// bands, popular topics, filters and a server-side paginated list.
/// Only published reviews are shown; every review originates from a
/// completed booking.
class CourtReviewsPage extends StatefulWidget {
  final VenueSummary venue;
  final BookCourtRepository repo;

  /// Overrides the signed-in user for tests; defaults to the current
  /// [AuthService] user in production.
  final String? viewerId;

  const CourtReviewsPage({
    super.key,
    required this.venue,
    required this.repo,
    this.viewerId,
  });

  @override
  State<CourtReviewsPage> createState() => _CourtReviewsPageState();
}

class _CourtReviewsPageState extends State<CourtReviewsPage> {
  static const _pageSize = 20;

  final _scroll = ScrollController();
  VenueReviewSummary? _summary;
  List<VenueCourt> _courts = const [];
  List<VenueReview> _reviews = const [];
  int _totalCount = 0;
  int _nextOffset = 0;
  bool _hasMore = false;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;

  int _summaryTab = 0; // 0 = คะแนน, 1 = หัวข้อ
  VenueReviewSort _sort = VenueReviewSort.helpful;
  VenueReviewBand? _band;
  String? _topicTagId;
  String? _courtId;

  String? get _userId =>
      widget.viewerId ?? AuthService.instance.currentUser?.id;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_maybeLoadMore);
    _load();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        widget.repo.getVenueReviewSummary(
          widget.venue.id,
          courtId: _courtId,
        ),
        widget.repo.listVenueReviewsV2(
          widget.venue.id,
          courtId: _courtId,
          tagId: _topicTagId,
          band: _band,
          sort: _sort,
          limit: _pageSize,
          viewerId: _userId,
        ),
        widget.repo.listPublicCourts(widget.venue.id),
      ]);
      if (!mounted) return;
      final page = results[1] as VenueReviewListPage;
      setState(() {
        _summary = results[0] as VenueReviewSummary;
        _reviews = page.reviews;
        _totalCount = page.totalCount;
        _nextOffset = page.nextOffset;
        _hasMore = page.hasMore;
        _courts = results[2] as List<VenueCourt>;
        _loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'โหลดรีวิวไม่สำเร็จ';
          _loading = false;
        });
      }
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final page = await widget.repo.listVenueReviewsV2(
        widget.venue.id,
        courtId: _courtId,
        tagId: _topicTagId,
        band: _band,
        sort: _sort,
        limit: _pageSize,
        offset: _nextOffset,
        viewerId: _userId,
      );
      if (!mounted) return;
      setState(() {
        _reviews = [..._reviews, ...page.reviews];
        _totalCount = page.totalCount;
        _nextOffset = page.nextOffset;
        _hasMore = page.hasMore;
        _loadingMore = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _maybeLoadMore() {
    if (_scroll.position.pixels >=
        _scroll.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  Future<void> _toggleHelpful(VenueReview review) async {
    final userId = _userId;
    if (userId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('เข้าสู่ระบบเพื่อโหวตรีวิว')),
      );
      return;
    }
    try {
      await widget.repo.setReviewHelpful(
        userId,
        review.id,
        helpful: !review.viewerVoted,
      );
      if (!mounted) return;
      setState(() {
        _reviews = [
          for (final r in _reviews)
            if (r.id == review.id)
              r.copyWith(
                viewerVoted: !r.viewerVoted,
                helpfulCount:
                    r.helpfulCount + (r.viewerVoted ? -1 : 1),
              )
            else
              r,
        ];
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('บันทึกการโหวตไม่สำเร็จ')),
        );
      }
    }
  }

  String _reviewDate(DateTime? date) {
    if (date == null) return '';
    final d = date.toLocal();
    return '${d.day}/${d.month}/${d.year + 543}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NeumorphicTheme.baseColor,
      appBar: AppBar(
        title: const Text(
          'รีวิว',
          style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: -0.3),
        ),
        backgroundColor: NeumorphicTheme.baseColor,
        elevation: 0,
        foregroundColor: NeumorphicTheme.textPrimary,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_error!),
                  TextButton(
                    onPressed: _load,
                    child: const Text('ลองอีกครั้ง'),
                  ),
                ],
              ),
            )
          : _buildBody(),
    );
  }

  Widget _buildBody() {
    final summary = _summary!;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          _buildHeader(summary),
          const SizedBox(height: 16),
          _buildSummaryTabs(summary),
          const SizedBox(height: 16),
          _buildFilters(),
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 8),
            child: Text(
              'ทั้งหมด $_totalCount รีวิว',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ),
          if (_reviews.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Center(
                child: Text(
                  _band != null || _topicTagId != null || _courtId != null
                      ? 'ไม่มีรีวิวตามตัวกรองนี้'
                      : 'ยังไม่มีรีวิว',
                  style: TextStyle(color: Colors.grey.shade600),
                ),
              ),
            )
          else ...[
            for (final review in _reviews) _buildReviewItem(review),
            if (_loadingMore)
              const Padding(
                padding: EdgeInsets.all(12),
                child: Center(child: CircularProgressIndicator()),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildHeader(VenueReviewSummary summary) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.venue.name,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 56,
              height: 56,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.primaryDark,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                summary.averageRating?.toStringAsFixed(1) ?? '-',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${summary.reviewCount} รีวิว',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'อ้างอิงจากรีวิวจากการจองที่เสร็จสมบูรณ์จริง',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSummaryTabs(VenueReviewSummary summary) {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 0, label: Text('คะแนน')),
              ButtonSegment(value: 1, label: Text('หัวข้อ')),
            ],
            selected: {_summaryTab},
            onSelectionChanged: (sel) =>
                setState(() => _summaryTab = sel.first),
          ),
        ),
        const SizedBox(height: 12),
        if (_summaryTab == 0)
          _buildBandBars(summary)
        else
          _buildTopicChips(summary),
      ],
    );
  }

  Widget _buildBandBars(VenueReviewSummary summary) {
    final maxCount = VenueReviewBand.values
        .map((b) => summary.bandCount(b))
        .fold(0, (a, b) => a > b ? a : b);
    return Column(
      children: [
        for (final band in VenueReviewBand.values)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () {
                setState(() => _band = _band == band ? null : band);
                _load();
              },
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          band.label,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: _band == band
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                        ),
                      ),
                      Text(
                        '${summary.bandCount(band)} รีวิว',
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: AppColors.primaryDark,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      minHeight: 8,
                      value: maxCount == 0
                          ? 0
                          : summary.bandCount(band) / maxCount,
                      backgroundColor: Colors.grey.shade300,
                      valueColor: const AlwaysStoppedAnimation(
                        AppColors.primaryDark,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildTopicChips(VenueReviewSummary summary) {
    if (summary.topics.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(
          'ยังไม่มีหัวข้อรีวิว',
          style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
        ),
      );
    }
    return Align(
      alignment: Alignment.centerLeft,
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        children: [
          for (final topic in summary.topics)
            FilterChip(
              label: Text('${topic.labelTh} (${topic.reviewCount})'),
              selected: _topicTagId == topic.tagId,
              onSelected: (sel) {
                setState(() => _topicTagId = sel ? topic.tagId : null);
                _load();
              },
            ),
        ],
      ),
    );
  }

  Widget _buildFilters() {
    return Row(
      children: [
        if (_courts.length > 1)
          Expanded(
            child: DropdownButtonFormField<String?>(
              initialValue: _courtId,
              isDense: true,
              decoration: const InputDecoration(
                labelText: 'สถานที่',
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
              ),
              items: [
                const DropdownMenuItem(
                  value: null,
                  child: Text('ทุกสถานที่'),
                ),
                for (final court in _courts)
                  DropdownMenuItem(
                    value: court.id,
                    child: Text(
                      court.name,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (v) {
                setState(() => _courtId = v);
                _load();
              },
            ),
          )
        else
          const Spacer(),
        const SizedBox(width: 8),
        DropdownButton<VenueReviewSort>(
          value: _sort,
          underline: const SizedBox.shrink(),
          items: [
            for (final sort in VenueReviewSort.values)
              DropdownMenuItem(value: sort, child: Text(sort.labelTh)),
          ],
          onChanged: (v) {
            if (v == null) return;
            setState(() => _sort = v);
            _load();
          },
        ),
      ],
    );
  }

  Widget _buildReviewItem(VenueReview review) {
    final isMine =
        _userId != null && review.userId == _userId;
    return NeumorphicContainer(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      borderRadius: 12,
      depth: 4,
      blur: 8,
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        review.userDisplayName ?? 'ผู้ใช้',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        [
                          if (review.courtName?.isNotEmpty == true)
                            review.courtName!,
                          if (review.sportName?.isNotEmpty == true)
                            review.sportName!,
                          _reviewDate(review.createdAt),
                        ].join(' • '),
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primaryDark,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    review.rating10.toStringAsFixed(1),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
            if (review.comment?.isNotEmpty == true) ...[
              const SizedBox(height: 8),
              Text(review.comment!, style: const TextStyle(fontSize: 13)),
            ],
            if (review.tagLabels.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final label in review.tagLabels)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        label,
                        style: const TextStyle(fontSize: 11),
                      ),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  Icons.verified_rounded,
                  size: 14,
                  color: AppColors.primaryDark,
                ),
                const SizedBox(width: 4),
                Text(
                  'จองจริง',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: Colors.grey.shade700,
                  ),
                ),
                const Spacer(),
                if (!isMine)
                  TextButton.icon(
                    onPressed: () => _toggleHelpful(review),
                    icon: Icon(
                      review.viewerVoted
                          ? Icons.thumb_up_rounded
                          : Icons.thumb_up_outlined,
                      size: 15,
                    ),
                    label: Text('มีประโยชน์ (${review.helpfulCount})'),
                    style: TextButton.styleFrom(
                      foregroundColor: review.viewerVoted
                          ? AppColors.primaryDark
                          : Colors.grey.shade700,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  )
                else
                  Text(
                    'มีประโยชน์ ${review.helpfulCount}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                  ),
              ],
            ),
          ],
        ),
    );
  }
}
