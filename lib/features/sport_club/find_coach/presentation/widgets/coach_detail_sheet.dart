import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:sheserved/features/health/data/models/health_article_models.dart';
import 'package:sheserved/features/sport_club/presentation/widgets/sport_club_utils.dart';
import 'package:sheserved/services/auth_service.dart';
import 'package:sheserved/shared/widgets/glass/glass_confirm_dialog.dart';
import 'package:sheserved/shared/widgets/neumorphic/neumorphic.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../data/coach_models.dart';
import '../../data/find_coach_repository.dart';
import 'coach_labels.dart';
import 'dialogs/coach_enrollment_dialogs.dart';
import 'dialogs/coach_offering_history_dialog.dart';
import 'dialogs/coach_review_dialogs.dart';

/// Coach detail sheet — Neumorphic surface following the
/// `GroupDetailSheet` pattern: pinned header with identity + favorite +
/// close, a scrollable middle (profile, sports, locations, offerings with
/// inline-selectable sessions, 1:1 slots, reviews, articles, gated
/// contacts) and a sticky footer carrying the selection summary and the
/// primary enroll/request actions. Secondary actions hide behind
/// swipe-to-reveal Slidable panes.
class CoachDetailSheet {
  CoachDetailSheet._();

  static Future<void> show(
    BuildContext pageContext, {
    required CoachSummary coach,
    required FindCoachRepository repo,
    Future<void> Function()? onRequest,
    VoidCallback? onOpenMyEnrollments,
  }) async {
    await showModalBottomSheet(
      context: pageContext,
      isScrollControlled: true,
      isDismissible: true,
      enableDrag: true,
      backgroundColor: Colors.transparent,
      elevation: 0,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => _CoachDetailSheetBody(
        coach: coach,
        repo: repo,
        onRequest: onRequest,
        onOpenMyEnrollments: onOpenMyEnrollments,
      ),
    );
  }
}

class _CoachDetailSheetBody extends StatefulWidget {
  final CoachSummary coach;
  final FindCoachRepository repo;
  final Future<void> Function()? onRequest;
  final VoidCallback? onOpenMyEnrollments;

  const _CoachDetailSheetBody({
    required this.coach,
    required this.repo,
    this.onRequest,
    this.onOpenMyEnrollments,
  });

  @override
  State<_CoachDetailSheetBody> createState() => _CoachDetailSheetBodyState();
}

class _CoachDetailSheetBodyState extends State<_CoachDetailSheetBody> {
  static const _textPrimary = NeumorphicTheme.textPrimary;
  static const _textSecondary = NeumorphicTheme.textSecondary;
  static const _accent = NeumorphicTheme.primaryBlue;

  bool _loading = true;
  String? _error;

  List<CoachOffering> _offerings = const [];
  List<CoachSlot> _slots = const [];
  List<CoachAvailabilityWindow> _windows = const [];
  List<CoachTeachingLocation> _locations = const [];
  CoachReviewSummaryV2? _reviewSummary;
  List<CoachReview> _reviewPreview = const [];
  List<HealthArticle> _articles = const [];
  bool _isFavorite = false;

  /// Contact details resolve lazily — `get_coach_contacts` enforces the
  /// relationship gate server-side.
  CoachContact? _contact;
  bool _contactRequested = false;
  bool _contactLocked = false;

  bool _busy = false;

  /// Learner's in-sheet session selection: offeringId → sessionIds.
  final Map<String, Set<String>> _selected = {};
  final Set<String> _expandedOfferings = {};

  String? get _userId => AuthService.instance.currentUser?.id;
  bool get _isAdmin => AuthService.instance.currentUser?.isAdmin == true;
  bool get _isSelf => _userId != null && _userId == widget.coach.userId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final userId = _userId;
      final results = await Future.wait<Object?>([
        widget.repo.getOfferingBoard(widget.coach.id, viewerId: userId),
        widget.repo.listPublicSlots(widget.coach.id),
        widget.repo.listCoachAvailability(widget.coach.id),
        widget.repo.listPublicLocations(widget.coach.id),
        widget.repo.getReviewSummaryV2(widget.coach.id),
        widget.repo.listReviewsV2(
          widget.coach.id,
          sort: 'helpful',
          limit: 3,
          viewerId: userId,
        ),
        if (userId != null)
          widget.repo.listMyFavoriteCoachIds(userId)
        else
          Future<Set<String>>.value(const {}),
        _loadArticles(),
      ]);
      if (!mounted) return;
      final favorites = results[6] as Set<String>;
      setState(() {
        _offerings = results[0] as List<CoachOffering>;
        _slots = results[1] as List<CoachSlot>;
        _windows = results[2] as List<CoachAvailabilityWindow>;
        _locations = results[3] as List<CoachTeachingLocation>;
        _reviewSummary = results[4] as CoachReviewSummaryV2;
        _reviewPreview = (results[5] as (List<CoachReview>, int)).$1;
        _isFavorite = favorites.contains(widget.coach.id);
        _articles = results[7] as List<HealthArticle>;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = CoachLabels.mapError(e);
      });
    }
  }

  /// Coach-authored health articles — public rows filtered by author.
  Future<List<HealthArticle>> _loadArticles() async {
    try {
      final res = await Supabase.instance.client
          .from('health_articles')
          .select('*, users(username, profile_image_url)')
          .eq('author_id', widget.coach.userId)
          .order('created_at', ascending: false)
          .limit(5);
      return (res as List)
          .map((e) => HealthArticle.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  // =============== Actions ===============

  Future<void> _toggleFavorite() async {
    final userId = _userId;
    if (userId == null) {
      _toast('กรุณาเข้าสู่ระบบเพื่อบันทึกโค้ชที่ชอบ');
      return;
    }
    try {
      final nowFav = await widget.repo.toggleCoachFavorite(
        userId,
        widget.coach.id,
      );
      if (!mounted) return;
      setState(() => _isFavorite = nowFav);
      _toast(nowFav ? 'บันทึกโค้ชแล้ว' : 'เลิกบันทึกแล้ว');
    } catch (e) {
      _toast(CoachLabels.mapError(e));
    }
  }

  Future<void> _revealContact() async {
    final userId = _userId;
    if (userId == null) {
      _toast('กรุณาเข้าสู่ระบบก่อน');
      return;
    }
    setState(() => _contactRequested = true);
    try {
      final contact = await widget.repo.getCoachContacts(
        userId,
        widget.coach.id,
      );
      if (!mounted) return;
      setState(() {
        _contact = contact;
        _contactLocked = contact == null || contact.isEmpty;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _contactLocked = true);
    }
  }

  Future<void> _requestSlot(CoachSlot slot) async {
    final userId = _userId;
    if (userId == null) {
      _toast('กรุณาเข้าสู่ระบบก่อนขอนัด');
      return;
    }
    final message = await _slotMessageDialog();
    if (message == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.repo.createSlotBookingRequest(
        userId: userId,
        slotId: slot.id,
        message: message.isEmpty ? null : message,
        idempotencyKey: const Uuid().v4(),
      );
      _toast('ส่งคำขอนัดแล้ว — คำขอยังไม่กันเวลาจนกว่าโค้ชจะอนุมัติ');
      await _load();
    } catch (e) {
      _toast(CoachLabels.mapError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _slotMessageDialog() {
    final controller = TextEditingController();
    return GlassConfirmDialog.show(
      context,
      icon: Icons.send_rounded,
      title: 'ส่งคำขอนัด 1:1',
      accentColor: _accent,
      cancelLabel: 'ยกเลิก',
      confirmLabel: 'ส่งคำขอ',
      maxWidth: 360,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'คำขอหลายรายการต่อ slot เดียวกันได้ — ช่วงเวลาถูกจองจริง'
            'เมื่อโค้ชอนุมัติคำขอใดคำขอหนึ่ง',
            style: TextStyle(
              fontSize: 12,
              color: Colors.white.withValues(alpha: 0.7),
              height: 1.35,
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: controller,
            maxLength: 300,
            maxLines: 2,
            style: const TextStyle(color: Colors.white, fontSize: 13),
            decoration: InputDecoration(
              hintText: 'ข้อความถึงโค้ช (ไม่บังคับ)',
              hintStyle: TextStyle(
                fontSize: 12.5,
                color: Colors.white.withValues(alpha: 0.45),
              ),
              border: InputBorder.none,
              counterStyle: TextStyle(
                fontSize: 10,
                color: Colors.white.withValues(alpha: 0.5),
              ),
            ),
          ),
        ],
      ),
      onConfirm: () async => true,
    ).then((ok) => ok == true ? controller.text.trim() : null);
  }

  void _toggleSession(CoachOffering o, CoachOfferingSession s) {
    if (!s.isScheduled || !s.isFuture || s.isFull) return;
    if (s.myEnrollmentStatus != null &&
        s.myEnrollmentStatus != 'cancelled' &&
        s.myEnrollmentStatus != 'rejected') {
      return; // already enrolled/requested for this session
    }
    setState(() {
      final set = _selected.putIfAbsent(o.id, () => {});
      if (set.contains(s.id)) {
        set.remove(s.id);
        if (set.isEmpty) _selected.remove(o.id);
      } else {
        if (o.allowPartialEnrollment) {
          set.add(s.id);
        } else {
          set
            ..clear()
            ..add(s.id);
        }
      }
    });
  }

  Future<void> _enrollSelected() async {
    final userId = _userId;
    if (userId == null) {
      _toast('กรุณาเข้าสู่ระบบก่อนสมัคร');
      return;
    }
    // One offering per enrollment — the sheet keeps selections grouped.
    for (final entry in _selected.entries) {
      final offering = _offerings.firstWhere(
        (o) => o.id == entry.key,
        orElse: () => CoachOffering(
          id: '',
          type: CoachOfferingType.groupClass,
          title: '',
        ),
      );
      if (offering.id.isEmpty || entry.value.isEmpty) continue;
      final selectedSessions = offering.sessions
          .where((s) => entry.value.contains(s.id))
          .toList();
      if (!mounted) return;
      final confirmed = await CoachEnrollmentConfirmDialog.show(
        context,
        coach: widget.coach,
        offering: offering,
        selectedSessions: selectedSessions,
        wholeCourse:
            !offering.allowPartialEnrollment ||
            selectedSessions.length == offering.sessions.length,
      );
      if (confirmed == null || !mounted) continue;
      setState(() => _busy = true);
      try {
        await widget.repo.createEnrollment(
          userId: userId,
          offeringId: offering.id,
          sessionIds: confirmed.sessionIds,
          policyAccepted: true,
          idempotencyKey: const Uuid().v4(),
        );
        _toast(
          offering.autoConfirm
              ? 'สมัครแล้ว — ที่นั่งถูกยืนยัน'
              : 'ส่งคำขอสมัครแล้ว รอโค้ชอนุมัติ',
        );
        setState(() => _selected.remove(offering.id));
        await _load();
      } catch (e) {
        _toast(CoachLabels.mapError(e));
      } finally {
        if (mounted) setState(() => _busy = false);
      }
    }
  }

  Future<void> _openReviews() async {
    await CoachReviewsDialog.show(
      context,
      coach: widget.coach,
      loadSummary: () => widget.repo.getReviewSummaryV2(widget.coach.id),
      loadReviews:
          ({
            tagId,
            minRating10,
            maxRating10,
            sort = 'helpful',
            limit = 20,
            offset = 0,
          }) => widget.repo.listReviewsV2(
            widget.coach.id,
            tagId: tagId,
            minRating10: minRating10,
            maxRating10: maxRating10,
            sort: sort,
            limit: limit,
            offset: offset,
            viewerId: _userId,
          ),
      onToggleHelpful: _userId == null
          ? null
          : (review, helpful) => widget.repo.setReviewHelpful(
              _userId!,
              review.id,
              helpful: helpful,
            ),
      onModerate: _isAdmin
          ? (review) async {
              final action = await CoachReviewModerationDialog.show(
                context,
                review: review,
              );
              if (action == null || !mounted) return;
              try {
                await widget.repo.moderateReview(_userId!, review.id, action);
                _toast('อัปเดตสถานะรีวิวแล้ว');
              } catch (e) {
                _toast(CoachLabels.mapError(e));
              }
            }
          : null,
    );
    await _load();
  }

  // =============== Build ===============

  int get _selectedCount => _selected.values.fold(0, (a, s) => a + s.length);

  double get _selectedPrice {
    var sum = 0.0;
    for (final entry in _selected.entries) {
      for (final o in _offerings) {
        if (o.id != entry.key) continue;
        if (o.pricingUnit == CoachPricingUnit.package ||
            (!o.allowPartialEnrollment && entry.value.isNotEmpty)) {
          sum += o.price ?? 0;
          break;
        }
        for (final s in o.sessions) {
          if (entry.value.contains(s.id)) {
            sum += s.price ?? o.price ?? 0;
          }
        }
      }
    }
    return sum;
  }

  @override
  Widget build(BuildContext context) {
    final coach = widget.coach;
    final screenHeight = MediaQuery.of(context).size.height;
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          constraints: BoxConstraints(maxHeight: screenHeight * 0.9),
          decoration: const BoxDecoration(
            color: NeumorphicTheme.baseColor,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildHeader(coach),
              Expanded(
                child: _loading
                    ? const Center(
                        child: CircularProgressIndicator(
                          color: NeumorphicTheme.primaryBlue,
                        ),
                      )
                    : _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _error!,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFFDC2626),
                                ),
                              ),
                              const SizedBox(height: 12),
                              NeumorphicPillButton(
                                text: 'ลองใหม่',
                                icon: Icons.refresh_rounded,
                                height: 44,
                                onPressed: _load,
                              ),
                            ],
                          ),
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _load,
                        color: NeumorphicTheme.primaryBlue,
                        backgroundColor: NeumorphicTheme.baseColor,
                        child: ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                          children: _buildContent(coach),
                        ),
                      ),
              ),
              _buildFooter(coach),
            ],
          ),
        ),
      ),
    );
  }

  // =============== Pinned header / footer ===============

  Widget _buildHeader(CoachSummary coach) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 10, 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: NeumorphicTheme.shadowDark.withValues(alpha: 0.25),
          ),
        ),
      ),
      child: Column(
        children: [
          const Center(child: NeumorphicSheetDragHandle()),
          const SizedBox(height: 12),
          Row(
            children: [
              NeumorphicContainer(
                shape: BoxShape.circle,
                depth: 3,
                blur: 6,
                padding: const EdgeInsets.all(3),
                child: CircleAvatar(
                  radius: 26,
                  backgroundImage: coach.avatarUrl?.isNotEmpty == true
                      ? NetworkImage(coach.avatarUrl!)
                      : null,
                  child: coach.avatarUrl?.isNotEmpty == true
                      ? null
                      : const Icon(Icons.person, size: 26),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            coach.displayName,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: _textPrimary,
                              letterSpacing: -0.2,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (coach.isVerified) ...[
                          const SizedBox(width: 4),
                          const Icon(
                            Icons.verified_rounded,
                            size: 17,
                            color: Color(0xFF1E88E5),
                          ),
                        ],
                      ],
                    ),
                    Text(
                      [
                        CoachLabels.mode(coach.teachingMode),
                        if (coach.hourlyRate != null)
                          '${CoachLabels.formatBaht(coach.hourlyRate)}/ชม.',
                        if (coach.averageRating10 != null &&
                            coach.reviewCount > 0)
                          '★ ${coach.averageRating10!.toStringAsFixed(1)}/10 '
                              '(${coach.reviewCount} รีวิว)',
                      ].join(' · '),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _accent,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              NeumorphicIconButton(
                icon: _isFavorite
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
                color: _isFavorite ? const Color(0xFFE53935) : _textSecondary,
                tooltip: 'บันทึกโค้ช',
                onPressed: _toggleFavorite,
              ),
              const SizedBox(width: 8),
              NeumorphicSheetCloseButton(
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFooter(CoachSummary coach) {
    final selected = _selectedCount;
    final canRequest = widget.onRequest != null && !_isSelf;
    final canEnroll = selected > 0;
    if (!canRequest && !canEnroll && widget.onOpenMyEnrollments == null) {
      return const SizedBox.shrink();
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: NeumorphicTheme.shadowDark.withValues(alpha: 0.25),
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (canEnroll) ...[
              NeumorphicInsetBox(
                height: null,
                borderRadius: 14,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.checklist_rounded,
                      size: 16,
                      color: _accent,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'เลือกแล้ว $selected รอบ · '
                        '${CoachLabels.formatBaht(_selectedPrice)}',
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: _textPrimary,
                        ),
                      ),
                    ),
                    NeumorphicPillButton(
                      text: 'ล้าง',
                      height: 30,
                      fontSize: 11.5,
                      depth: 3,
                      blur: 6,
                      onPressed: () => setState(_selected.clear),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
            ],
            Row(
              children: [
                if (canEnroll)
                  Expanded(
                    flex: 2,
                    child: NeumorphicVerifyButton(
                      onPressed: _busy ? null : _enrollSelected,
                      isEnabled: !_busy,
                      isLoading: _busy,
                      text: 'สมัคร $selected รอบ',
                      height: 52,
                      fitTextToWidth: true,
                      icon: const Icon(
                        Icons.how_to_reg_rounded,
                        color: Colors.white,
                      ),
                    ),
                  ),
                if (canEnroll && canRequest) const SizedBox(width: 10),
                if (canRequest)
                  Expanded(
                    child: NeumorphicPillButton(
                      text: 'ขอนัดกับโค้ช',
                      icon: Icons.send_rounded,
                      iconSize: 16,
                      fontSize: 13.5,
                      height: 52,
                      onPressed: _busy || widget.onRequest == null
                          ? null
                          : widget.onRequest,
                    ),
                  ),
              ],
            ),
            if (widget.onOpenMyEnrollments != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: NeumorphicPillButton(
                  text: 'ดูการสมัครและคำขอของฉัน',
                  icon: Icons.arrow_forward_rounded,
                  iconSize: 16,
                  fontSize: 12,
                  height: 38,
                  depth: 3,
                  blur: 6,
                  onPressed: widget.onOpenMyEnrollments,
                ),
              ),
          ],
        ),
      ),
    );
  }

  // =============== Content ===============

  List<Widget> _buildContent(CoachSummary coach) {
    return [
      if (coach.bio?.isNotEmpty == true)
        _card(
          child: Text(
            coach.bio!,
            style: const TextStyle(
              fontSize: 13,
              color: _textPrimary,
              height: 1.45,
            ),
          ),
        ),
      if (coach.experience?.isNotEmpty == true)
        _card(
          icon: Icons.military_tech_outlined,
          title: 'ประสบการณ์',
          child: Text(
            coach.experience!,
            style: const TextStyle(fontSize: 12.5, color: _textPrimary),
          ),
        ),
      _card(
        icon: Icons.sports_rounded,
        title: 'กีฬาและความเชี่ยวชาญ',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (coach.skillLevels.isNotEmpty)
              Text(
                'ระดับผู้เรียน: ${coach.skillLevels.map(CoachLabels.level).join(', ')}',
                style: const TextStyle(fontSize: 12, color: _textSecondary),
              ),
            if (coach.specialties.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final s in coach.specialties)
                      NeumorphicTagChip(label: s),
                  ],
                ),
              ),
            if (coach.specialties.isEmpty && coach.skillLevels.isEmpty)
              const Text(
                'ยังไม่ระบุ',
                style: TextStyle(fontSize: 12, color: _textSecondary),
              ),
          ],
        ),
      ),
      if (coach.serviceAreas.isNotEmpty || _locations.isNotEmpty)
        _card(
          icon: Icons.place_outlined,
          title: 'พื้นที่สอน',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final a in coach.serviceAreas)
                _bullet(
                  [
                        if (a.district != null) a.district!,
                        if (a.province != null) a.province!,
                      ].join(', ') +
                      (a.radiusKm != null
                          ? ' (รัศมี ${a.radiusKm!.toStringAsFixed(0)} กม.)'
                          : ''),
                ),
              for (final l in _locations)
                _bullet(
                  '${l.name}${l.address != null ? ' — ${l.address}' : ''}',
                ),
            ],
          ),
        ),
      if (_windows.isNotEmpty)
        _card(
          icon: Icons.event_available_outlined,
          title: 'เวลาว่างประจำสัปดาห์ (${coach.timezone})',
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final w in _windows)
                NeumorphicTagChip(
                  label:
                      '${CoachLabels.dayOfWeek(w.dayOfWeek)} '
                      '${w.startTime}–${w.endTime}',
                ),
            ],
          ),
        ),
      _offeringsSection(),
      _slotsSection(),
      _reviewsSection(coach),
      if (_articles.isNotEmpty) _articlesSection(),
      _contactSection(),
    ];
  }

  Widget _offeringsSection() {
    final active = _offerings.where((o) => !o.isDone && !o.isOneOnOne).toList();
    final done = _offerings.where((o) => o.isDone && !o.isOneOnOne).toList();
    if (active.isEmpty && done.isEmpty) return const SizedBox.shrink();
    return _card(
      icon: Icons.class_outlined,
      title: 'คลาสและหลักสูตร',
      trailing: done.isNotEmpty
          ? NeumorphicPillButton(
              text: 'ประวัติ',
              icon: Icons.history_rounded,
              iconSize: 14,
              fontSize: 11.5,
              height: 32,
              depth: 3,
              blur: 6,
              onPressed: () => CoachOfferingHistoryDialog.show(
                context,
                offering: done.first,
              ),
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (active.isEmpty)
            const Text(
              'ยังไม่มีรอบที่เปิดรับ',
              style: TextStyle(fontSize: 12, color: _textSecondary),
            )
          else
            for (final o in active) _offeringBlock(o),
        ],
      ),
    );
  }

  Widget _offeringBlock(CoachOffering o) {
    final expanded = _expandedOfferings.contains(o.id);
    final activeSessions = o.activeSessions;
    final statusColor = CoachLabels.offeringStatusColor(o.status);
    final myEnrolled = o.myEnrollmentId != null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Slidable(
        key: ValueKey('offering_${o.id}'),
        endActionPane: ActionPane(
          motion: const ScrollMotion(),
          extentRatio: o.pastSessions.isNotEmpty ? 0.3 : 0.2,
          children: [
            if (o.pastSessions.isNotEmpty)
              _slidableAction(
                label: 'ประวัติ',
                icon: Icons.history_rounded,
                color: _textSecondary,
                onTap: () =>
                    CoachOfferingHistoryDialog.show(context, offering: o),
              ),
          ],
        ),
        child: NeumorphicContainer(
          borderRadius: 14,
          depth: 3,
          blur: 6,
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => setState(
                    () => expanded
                        ? _expandedOfferings.remove(o.id)
                        : _expandedOfferings.add(o.id),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    o.title,
                                    style: const TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w700,
                                      color: _textPrimary,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                NeumorphicInsetBox(
                                  height: null,
                                  borderRadius: 8,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  child: Text(
                                    CoachLabels.offeringStatus(o.status),
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: statusColor,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 3),
                            Text(
                              [
                                CoachLabels.offeringType(o.type),
                                if (o.price != null)
                                  '${CoachLabels.formatBaht(o.price)} '
                                      '${CoachLabels.pricingUnit(o.pricingUnit)}',
                                '${activeSessions.length} รอบว่าง',
                                if (o.minEnrollment > 0)
                                  'ขั้นต่ำ ${o.minEnrollment} คน',
                              ].join(' · '),
                              style: const TextStyle(
                                fontSize: 11,
                                color: _textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        expanded
                            ? Icons.expand_less_rounded
                            : Icons.expand_more_rounded,
                        color: _textSecondary,
                      ),
                    ],
                  ),
                ),
              ),
              if (expanded) ...[
                const SizedBox(height: 8),
                if (o.description?.isNotEmpty == true)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      o.description!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: _textSecondary,
                        height: 1.35,
                      ),
                    ),
                  ),
                if (o.locationLabel != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      'สถานที่: ${o.locationLabel} (${o.timezone}) · '
                      '${o.autoConfirm ? 'ยืนยันอัตโนมัติ' : 'รอโค้ชอนุมัติ'}',
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: _textSecondary,
                      ),
                    ),
                  ),
                if (myEnrolled)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      'คุณมีการสมัครรายการนี้แล้ว — ดูใน "การสมัครของฉัน"',
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF2E7D32),
                      ),
                    ),
                  ),
                if (activeSessions.isEmpty)
                  const Text(
                    'ไม่มีรอบที่เปิดรับแล้ว',
                    style: TextStyle(fontSize: 11.5, color: _textSecondary),
                  )
                else
                  for (final s in activeSessions) _sessionRow(o, s),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _sessionRow(CoachOffering o, CoachOfferingSession s) {
    final selected = _selected[o.id]?.contains(s.id) == true;
    final alreadyIn =
        s.myEnrollmentStatus != null &&
        s.myEnrollmentStatus != 'cancelled' &&
        s.myEnrollmentStatus != 'rejected';
    final selectable =
        o.isOpen && !s.isFull && s.isFuture && !alreadyIn && !_isSelf;
    const padding = EdgeInsets.symmetric(horizontal: 10, vertical: 8);
    final content = Row(
      children: [
        Icon(
          selected
              ? Icons.check_circle_rounded
              : alreadyIn
              ? Icons.check_circle_outline_rounded
              : s.isFull
              ? Icons.block_rounded
              : Icons.circle_outlined,
          size: 17,
          color: selected
              ? _accent
              : alreadyIn
              ? const Color(0xFF2E7D32)
              : _textSecondary,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'รอบ ${s.seq} · ${formatThaiSessionRange(s.startsAt.toLocal(), s.endsAt.toLocal())}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: selected ? _accent : _textPrimary,
                ),
              ),
              Text(
                [
                  if (alreadyIn)
                    switch (s.myEnrollmentStatus) {
                      'confirmed' => 'ยืนยันแล้ว',
                      'pending' => 'รออนุมัติ',
                      _ => s.myEnrollmentStatus!,
                    }
                  else if (s.isFull)
                    'เต็มแล้ว'
                  else if (s.capacity != null)
                    'เหลือ ${s.capacity! - s.confirmedCount}/${s.capacity} ที่',
                  if (s.price != null) CoachLabels.formatBaht(s.price),
                ].join(' · '),
                style: TextStyle(
                  fontSize: 10.5,
                  color: alreadyIn ? const Color(0xFF2E7D32) : _textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
    // สถานะเลือกเป็นรางจม (Inset) และสถานะปกติเป็นปุ่มนูน โดยใช้ padding
    // ชุดเดียวกันทั้งสองสถานะ เพื่อไม่ให้ความสูงของแถวขยับเมื่อเลือก
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: selectable ? () => _toggleSession(o, s) : null,
          borderRadius: BorderRadius.circular(12),
          child: selected
              ? NeumorphicInsetBox(
                  height: null,
                  borderRadius: 12,
                  padding: padding,
                  child: content,
                )
              : NeumorphicContainer(
                  borderRadius: 12,
                  depth: 3,
                  blur: 6,
                  padding: padding,
                  child: content,
                ),
        ),
      ),
    );
  }

  Widget _slotsSection() {
    final bookable = _slots.where((s) => s.isBookable).toList();
    if (bookable.isEmpty) return const SizedBox.shrink();
    return _card(
      icon: Icons.schedule_rounded,
      title: 'ช่วงเวลา 1:1 ที่เปิดจอง',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final s in bookable.take(10))
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Slidable(
                key: ValueKey('slot_${s.id}'),
                endActionPane: ActionPane(
                  motion: const ScrollMotion(),
                  extentRatio: 0.25,
                  children: [
                    _slidableAction(
                      label: 'ขอนัด',
                      icon: Icons.send_rounded,
                      color: _accent,
                      onTap: () => _requestSlot(s),
                    ),
                  ],
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: _isSelf ? null : () => _requestSlot(s),
                    borderRadius: BorderRadius.circular(12),
                    child: NeumorphicContainer(
                      borderRadius: 12,
                      depth: 3,
                      blur: 6,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.event_available_rounded,
                            size: 16,
                            color: _accent,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              formatThaiSessionRange(
                                s.startsAt.toLocal(),
                                s.endsAt.toLocal(),
                              ),
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: _textPrimary,
                              ),
                            ),
                          ),
                          Text(
                            'ปัดซ้ายเพื่อขอนัด',
                            style: TextStyle(
                              fontSize: 10,
                              color: _textSecondary.withValues(alpha: 0.75),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _reviewsSection(CoachSummary coach) {
    final summary = _reviewSummary;
    return _card(
      icon: Icons.reviews_outlined,
      title: 'รีวิว',
      badge: summary != null && summary.reviewCount > 0
          ? '${summary.reviewCount}'
          : null,
      trailing: NeumorphicPillButton(
        text: 'ดูทั้งหมด',
        fontSize: 11.5,
        height: 32,
        depth: 3,
        blur: 6,
        onPressed: _openReviews,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (summary != null && summary.reviewCount > 0) ...[
            Row(
              children: [
                Text(
                  summary.averageRating?.toStringAsFixed(1) ?? '-',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: _textPrimary,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '/10 · ${summary.reviewCount} รีวิว',
                  style: const TextStyle(fontSize: 12, color: _textSecondary),
                ),
              ],
            ),
            if (summary.categories.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Column(
                  children: [
                    for (final c in summary.categories.take(5))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 3),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                c.labelTh,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: _textSecondary,
                                ),
                              ),
                            ),
                            Text(
                              c.average?.toStringAsFixed(1) ?? '-',
                              style: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: _textPrimary,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
          ],
          if (_reviewPreview.isEmpty)
            const Text(
              'ยังไม่มีรีวิว — รีวิวได้หลังเรียนจบเท่านั้น',
              style: TextStyle(fontSize: 12, color: _textSecondary),
            )
          else
            for (final r in _reviewPreview) _reviewPreviewTile(r),
        ],
      ),
    );
  }

  Widget _reviewPreviewTile(CoachReview r) {
    final rating = r.rating10 ?? r.rating.toDouble();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 14,
            backgroundImage: r.userAvatarUrl?.isNotEmpty == true
                ? NetworkImage(r.userAvatarUrl!)
                : null,
            child: r.userAvatarUrl?.isNotEmpty == true
                ? null
                : const Icon(Icons.person, size: 14),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        r.userDisplayName ?? 'ผู้ใช้',
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: _textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      rating.toStringAsFixed(1),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: _accent,
                      ),
                    ),
                  ],
                ),
                if (r.comment?.isNotEmpty == true)
                  Text(
                    r.comment!,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: _textSecondary,
                      height: 1.35,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _articlesSection() {
    return _card(
      icon: Icons.article_outlined,
      title: 'บทความจากโค้ช',
      badge: '${_articles.length}',
      child: Column(
        children: [
          for (final a in _articles)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => Navigator.of(
                    context,
                  ).pushNamed('/health/article', arguments: a),
                  child: NeumorphicContainer(
                    borderRadius: 12,
                    depth: 3,
                    blur: 6,
                    padding: const EdgeInsets.all(10),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.article_outlined,
                          size: 16,
                          color: _accent,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            a.title,
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: _textPrimary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const Icon(
                          Icons.chevron_right_rounded,
                          size: 18,
                          color: _textSecondary,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _contactSection() {
    if (_isSelf) return const SizedBox.shrink();
    return _card(
      icon: Icons.contact_phone_outlined,
      title: 'ช่องทางติดต่อ',
      child: _contactRequested
          ? (_contact != null && !_contactLocked
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_contact!.phone?.isNotEmpty == true)
                        _bullet('โทร ${_contact!.phone}'),
                      if (_contact!.lineId?.isNotEmpty == true)
                        _bullet('LINE ${_contact!.lineId}'),
                      if (_contact!.facebookUrl?.isNotEmpty == true)
                        _bullet('Facebook ${_contact!.facebookUrl}'),
                    ],
                  )
                : const Text(
                    'ช่องทางติดต่อแสดงเฉพาะผู้เรียนที่มีนัด/การสมัคร'
                    'ที่ยืนยันแล้ว',
                    style: TextStyle(fontSize: 12, color: _textSecondary),
                  ))
          : NeumorphicPillButton(
              text: 'แตะเพื่อดูช่องทางติดต่อ',
              icon: Icons.lock_outline_rounded,
              iconSize: 16,
              fontSize: 12.5,
              height: 44,
              onPressed: _revealContact,
            ),
    );
  }

  // =============== Shared bits ===============

  Widget _card({
    IconData? icon,
    String? title,
    String? badge,
    Widget? trailing,
    required Widget child,
  }) {
    return NeumorphicContainer(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      borderRadius: 20,
      depth: 4,
      blur: 8,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null) ...[
            Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 17, color: _accent),
                  const SizedBox(width: 7),
                ],
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: _textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (badge != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Text(
                      badge,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: _textSecondary,
                      ),
                    ),
                  ),
                ?trailing,
              ],
            ),
            const SizedBox(height: 8),
          ],
          child,
        ],
      ),
    );
  }

  Widget _bullet(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 3),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '• ',
          style: TextStyle(fontSize: 12.5, color: _textSecondary),
        ),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 12.5, color: _textPrimary),
          ),
        ),
      ],
    ),
  );

  Widget _slidableAction({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return CustomSlidableAction(
      onPressed: (_) => onTap(),
      backgroundColor: color,
      foregroundColor: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 19),
            const SizedBox(height: 3),
            Text(
              label,
              maxLines: 1,
              softWrap: false,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
