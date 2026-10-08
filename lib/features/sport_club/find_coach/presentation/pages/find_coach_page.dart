import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'package:sheserved/features/community/find_buddies/data/fitness_buddies_repository.dart';
import 'package:sheserved/features/sport_club/application/feed_filter_collapse_controller.dart';
import 'package:sheserved/features/sport_club/presentation/widgets/feed/filter_collapse_box.dart';
import 'package:sheserved/features/sport_club/presentation/widgets/feed/sport_club_filter_button.dart';
import 'package:sheserved/features/sport_club/presentation/widgets/sport_club_utils.dart';
import 'package:sheserved/features/sport_club/shared/application/sports_hub_bar_controller.dart';
import 'package:sheserved/features/sport_club/shared/application/sports_hub_controller.dart';
import 'package:sheserved/features/sport_club/shared/application/sports_hub_sport_catalog.dart';
import 'package:sheserved/features/sport_club/shared/domain/sports_discovery_filter.dart';
import 'package:sheserved/features/sport_club/shared/presentation/widgets/shared_sport_filter_bar.dart';
import 'package:sheserved/services/auth_service.dart';

import '../../application/coach_request_service.dart';
import '../../application/find_coach_query.dart';
import '../../data/coach_models.dart';
import '../../data/find_coach_repository.dart';
import '../../domain/find_coach_filter.dart';
import '../widgets/coach_card.dart';
import '../widgets/coach_detail_sheet.dart';
import '../widgets/coach_filter_sheet.dart';
import '../widgets/coach_labels.dart';
import '../widgets/coach_quick_filter_row.dart';
import '../widgets/coach_request_sheet.dart';
import 'coach_management_page.dart';
import 'my_coach_enrollments_page.dart';
import 'my_coach_requests_page.dart';

/// Find Coach page of the Sports Hub.
///
/// Public directory of approved coaches. Shared sport/location state comes
/// from [SportsHubController]; coach-specific filters (skill level, rate,
/// teaching mode, verified) live in `hub.coaches` and never leak into other
/// domains. Discovery is read-only — requests start explicitly from the
/// coach detail sheet.
class FindCoachPage extends StatefulWidget {
  final SportsHubController? hubController;

  /// Shell-owned shared sport catalog + bar state (plan 21.7.13). Present
  /// when embedded in [SportsHubPage]; the shared chips row is rendered once
  /// by the shell overlay and this page registers its quick-action buttons
  /// as the bar's trailing controls.
  final SportsHubSportCatalog? sportCatalog;
  final SportsHubBarController? sportBar;

  const FindCoachPage({
    super.key,
    this.hubController,
    this.sportCatalog,
    this.sportBar,
  });

  @override
  State<FindCoachPage> createState() => _FindCoachPageState();
}

class _FindCoachPageState extends State<FindCoachPage> {
  late final FitnessBuddiesRepository _buddiesRepo;
  late final FindCoachRepository _repo;
  late final FindCoachQuery _query;
  late final CoachRequestService _requests;

  final _scrollController = ScrollController();
  final _filterCollapse = FeedFilterCollapseController();

  static const double _filterButtonTopCollapsed = 9;
  static const double _filterButtonTopEmbeddedExpanded = 67;
  static const double _filterButtonTopExpanded = 59;

  List<Map<String, dynamic>> _sports = [];
  List<CoachSummary> _coaches = [];
  bool _loading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  int _offset = 0;
  int _requestId = 0;
  double? _userLat;
  double? _userLng;
  Set<String> _favoriteCoachIds = const {};
  Set<String> _myCoachIds = const {};

  SportsHubController? get _hub => widget.hubController;
  FindCoachFilter get _filter => _hub?.coaches ?? const FindCoachFilter();
  String? get _userId => AuthService.instance.currentUser?.id;

  @override
  void initState() {
    super.initState();
    final client = Supabase.instance.client;
    _buddiesRepo = FitnessBuddiesRepository(client);
    _repo = FindCoachRepository(client);
    _query = FindCoachQuery(
      listCoaches: _repo.listPublicCoaches,
      hydrateCoaches: _repo.hydrateCoachCards,
    );
    _requests = CoachRequestService(
      createRequest: _repo.createBookingRequest,
      decideRequest: _repo.decideBookingRequest,
      cancelRequest: _repo.cancelBookingRequest,
    );
    _scrollController.addListener(_onScroll);
    _hub?.addListener(_onHubChanged);
    // initState runs while the shell's PageView is still building; defer the
    // registration so the bar controller's notifyListeners cannot mark the
    // shell's AnimatedBuilder dirty mid-build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        widget.sportBar?.setTrailing(2, (_) => _buildBarTrailing());
      }
    });
    _init();
  }

  @override
  void didUpdateWidget(covariant FindCoachPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.hubController != widget.hubController) {
      oldWidget.hubController?.removeListener(_onHubChanged);
      widget.hubController?.addListener(_onHubChanged);
      _onHubChanged();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _hub?.removeListener(_onHubChanged);
    widget.sportBar?.setTrailing(2, null);
    super.dispose();
  }

  void _onHubChanged() {
    if (!mounted) return;
    _reload();
  }

  /// Sport list for sheets/pickers — the shared ranked catalog when
  /// embedded, otherwise this page's own load (standalone usage).
  List<Map<String, dynamic>> get _sportRows {
    final catalog = widget.sportCatalog;
    if (catalog != null && catalog.sports.isNotEmpty) return catalog.sports;
    return _sports;
  }

  Future<void> _init() async {
    // Embedded pages share the shell's single ranked catalog (21.7.13);
    // standalone usage keeps its own load.
    final includeSports = widget.sportCatalog == null;
    try {
      final results = await Future.wait<Object?>([
        if (includeSports)
          _buddiesRepo.getApprovedSports(userId: _userId)
        else
          Future<List<Map<String, dynamic>>>.value(const []),
        if (_userId != null)
          _repo.listMyFavoriteCoachIds(_userId!)
        else
          Future<Set<String>>.value(const {}),
        if (_userId != null)
          _repo.listMyCoachRelationshipIds(_userId!)
        else
          Future<Set<String>>.value(const {}),
      ]);
      if (!mounted) return;
      setState(() {
        _sports = results[0] as List<Map<String, dynamic>>;
        _favoriteCoachIds = results[1] as Set<String>;
        _myCoachIds = results[2] as Set<String>;
      });
    } catch (_) {
      // Sports row may stay empty; the directory still renders.
    }
    await _reload();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pixels = _scrollController.position.pixels;
    widget.sportBar?.reportScroll(2, pixels);
    if (_filterCollapse.update(pixels)) setState(() {});
    if (_loading || _isLoadingMore || !_hasMore) return;
    if (pixels >= _scrollController.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  Future<void> _reload() async {
    final requestId = ++_requestId;
    setState(() => _loading = true);
    // Relationship filters must see fresh sets (favorites may have been
    // toggled from the detail sheet).
    if ((_filter.favoritesOnly || _filter.myCoachesOnly) &&
        _userId != null) {
      try {
        final results = await Future.wait([
          _repo.listMyFavoriteCoachIds(_userId!),
          _repo.listMyCoachRelationshipIds(_userId!),
        ]);
        if (!mounted || requestId != _requestId) return;
        _favoriteCoachIds = results[0];
        _myCoachIds = results[1];
      } catch (_) {}
    }
    try {
      final page = await _query.fetch(
        shared: _hub?.shared ?? const SportsDiscoveryFilter(),
        filter: _filter,
        offset: 0,
        userLat: _userLat,
        userLng: _userLng,
        favoriteCoachIds: _favoriteCoachIds,
        myCoachIds: _myCoachIds,
        isStale: () => requestId != _requestId,
      );
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _coaches = page.coaches;
        _offset = page.nextOffset;
        _hasMore = page.hasMore;
        _loading = false;
      });
    } on StateError catch (e) {
      if (e.message != 'STALE_FILTER_REQUEST' && mounted) {
        setState(() => _loading = false);
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    final requestId = ++_requestId;
    setState(() => _isLoadingMore = true);
    try {
      final page = await _query.fetch(
        shared: _hub?.shared ?? const SportsDiscoveryFilter(),
        filter: _filter,
        offset: _offset,
        userLat: _userLat,
        userLng: _userLng,
        favoriteCoachIds: _favoriteCoachIds,
        myCoachIds: _myCoachIds,
        isStale: () => requestId != _requestId,
      );
      if (!mounted) return;
      if (requestId != _requestId) {
        setState(() => _isLoadingMore = false);
        return;
      }
      setState(() {
        _coaches = [..._coaches, ...page.coaches];
        _offset = page.nextOffset;
        _hasMore = page.hasMore;
        _isLoadingMore = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isLoadingMore = false);
    }
  }

  // =============== Shared filter handlers ===============

  void _onSportSelected(String? id, bool selected) {
    final hub = _hub;
    if (hub == null) return;
    hub.updateShared(
      hub.shared.copyWith(sportId: selected ? id : null, clearSportId: true),
    );
  }

  Future<bool> _requestLocation() async {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return false;
    }
    try {
      final position = await Geolocator.getCurrentPosition();
      _userLat = position.latitude;
      _userLng = position.longitude;
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _toggleQuickFilter(String key) async {
    final hub = _hub;
    if (hub == null) return;
    if (key == 'radius') {
      if (hub.shared.locationEnabled) {
        hub.updateShared(hub.shared.copyWith(locationEnabled: false));
        return;
      }
      final ok = await _requestLocation();
      if (!ok) {
        _toast('ไม่สามารถเข้าถึงตำแหน่งได้ กรุณาอนุญาตสิทธิ์ตำแหน่ง');
        return;
      }
      hub.updateShared(hub.shared.copyWith(locationEnabled: true));
      return;
    }
    final filter = _filter;
    switch (key) {
      case 'verified':
        hub.updateCoaches(
          filter.copyWith(verifiedOnly: !filter.verifiedOnly),
        );
      case 'available':
        hub.updateCoaches(
          filter.copyWith(availableOnly: !filter.availableOnly),
        );
      case 'favorites':
        hub.updateCoaches(
          filter.copyWith(favoritesOnly: !filter.favoritesOnly),
        );
      case 'my_coaches':
        hub.updateCoaches(
          filter.copyWith(myCoachesOnly: !filter.myCoachesOnly),
        );
    }
  }

  Future<void> _showAdvancedFilter() async {
    final hub = _hub;
    if (hub == null) return;
    final specialtyOptions = _coaches
        .expand((c) => c.specialties)
        .toSet()
        .toList();
    final result = await CoachFilterSheet.show(
      context,
      current: _filter,
      currentQuery: hub.shared.query,
      currentProvince: hub.shared.province,
      currentDistrict: hub.shared.district,
      specialtyOptions: specialtyOptions,
      signedIn: _userId != null,
    );
    if (result == null || !mounted) return;
    hub.updateShared(
      hub.shared.copyWith(
        query: result.query,
        province: result.province,
        clearProvince: result.province == null,
        district: result.district,
        clearDistrict: result.district == null,
      ),
    );
    hub.updateCoaches(result.filter);
  }

  Future<bool> _requireLogin() async {
    if (_userId != null) return true;
    await Navigator.pushNamed(
      context,
      '/login',
      arguments: {'returnAfterLogin': true},
    );
    return _userId != null;
  }

  // =============== Detail + request flow ===============

  Future<void> _openCoach(CoachSummary coach) async {
    // Real user detail-opens feed the shared usage ranking (21.7.13).
    widget.sportCatalog?.recordDetailOpen(
      domain: 'coaches',
      entityId: coach.id,
      sportIds: coach.sportIds,
    );
    await CoachDetailSheet.show(
      context,
      coach: coach,
      repo: _repo,
      onRequest: () => _startRequest(coach),
      onOpenMyEnrollments: () {
        Navigator.of(context).maybePop();
        _openMyEnrollments();
      },
    );
  }

  Future<void> _openMyRequests() async {
    if (!await _requireLogin()) return;
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => MyCoachRequestsPage(repo: _repo)),
    );
  }

  Future<void> _openMyEnrollments() async {
    if (!await _requireLogin()) return;
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MyCoachEnrollmentsPage(repo: _repo),
      ),
    );
  }

  Future<void> _startRequest(CoachSummary coach) async {
    if (_userId == null) {
      await _requireLogin();
      if (_userId == null) return;
    }
    if (!mounted) return;
    Navigator.of(context).maybePop(); // close detail sheet

    final draft = await CoachRequestSheet.show(
      context,
      coach: coach,
      sports: _sportRows,
      preferredSportId: _hub?.shared.sportId,
    );
    if (draft == null || !mounted) return;

    try {
      await _requests.request(
        userId: _userId,
        coach: coach,
        sportId: draft.sportId,
        teachingMode: draft.teachingMode,
        startsAt: draft.startsAt,
        endsAt: draft.endsAt,
        message: draft.message,
        idempotencyKey: const Uuid().v4(),
      );
      _toast('ส่งคำขอนัดแล้ว รอโค้ชตอบรับ');
    } catch (e) {
      _toast(_mapRequestError(e));
    }
  }

  /// Coach self-service: the management page covers profile creation,
  /// editing, offerings, slots and the request/enrollment queues.
  Future<void> _openCoachTools() async {
    if (!await _requireLogin()) return;
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CoachManagementPage(repo: _repo, sports: _sportRows),
      ),
    );
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  String get _filterSummary {
    final parts = <String>[];
    final shared = _hub?.shared;
    final f = _filter;
    if (shared?.province?.isNotEmpty == true) parts.add(shared!.province!);
    if (shared?.district?.isNotEmpty == true) parts.add(shared!.district!);
    if (f.skillLevel != null) parts.add('ระดับ');
    if (f.maxHourlyRate != null) parts.add('ราคา');
    if (f.teachingMode != null) parts.add('รูปแบบ');
    if (f.minRating10 != null) {
      parts.add('≥${f.minRating10!.toStringAsFixed(0)}');
    }
    if (f.offeringType != null) {
      parts.add(CoachLabels.offeringType(coachOfferingTypeFrom(f.offeringType)));
    }
    if (f.favoritesOnly) parts.add('บันทึกไว้');
    if (f.myCoachesOnly) parts.add('โค้ชของฉัน');
    return parts.join(' · ');
  }

  /// Trailing quick actions registered on the shell's shared sport bar
  /// while this page is embedded; standalone builds keep them inline.
  Widget _buildBarTrailing() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'การสมัครของฉัน',
          icon: const Icon(Icons.how_to_reg_rounded),
          onPressed: _openMyEnrollments,
        ),
        IconButton(
          tooltip: 'คำขอนัดของฉัน',
          icon: const Icon(Icons.event_note_rounded),
          onPressed: _openMyRequests,
        ),
        IconButton(
          tooltip: 'จัดการโค้ชของฉัน',
          icon: const Icon(Icons.school_rounded),
          onPressed: _openCoachTools,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final shared = _hub?.shared;
    final filter = _filter;
    return Stack(
      children: [
        _buildBody(shared, filter),
        // Floating filter button: appears where the quick-filter row used to
        // be while it is collapsed, so the advanced filter stays reachable —
        // mirrors the Find Buddies feed and Book Court overlays.
        AnimatedPositioned(
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
          left: 16,
          top: _filterCollapse.isCollapsed
              ? _filterButtonTopCollapsed
              : (widget.sportBar != null
                    ? _filterButtonTopEmbeddedExpanded
                    : _filterButtonTopExpanded),
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 200),
            opacity: _filterCollapse.isCollapsed ? 1 : 0,
            child: IgnorePointer(
              ignoring: !_filterCollapse.isCollapsed,
              child: ExcludeSemantics(
                excluding: !_filterCollapse.isCollapsed,
                child: SportClubFilterButton(
                  activeFilterCount:
                      filter.activeCount + (shared?.activeCount ?? 0),
                  filterSummary: _filterSummary,
                  onTap: () {
                    setState(_filterCollapse.expand);
                    widget.sportBar?.expand();
                    unawaited(_showAdvancedFilter());
                  },
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBody(SportsDiscoveryFilter? shared, FindCoachFilter filter) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Column(
            children: [
              if (widget.sportBar != null)
                // The shared chips row is the shell's overlay; this spacer
                // keeps the quick filters at their usual position without
                // changing the viewport when the bar collapses.
                const SizedBox(height: SportsHubBarController.barHeight - 8)
              else
                SharedSportFilterBar(
                  sports: _sports,
                  selectedSportId: shared?.sportId,
                  onSportSelected: _onSportSelected,
                  trailing: _buildBarTrailing(),
                ),
              const SizedBox(height: 8),
              // Quick filters slide away (and give their height back to the
              // list) once the coach list is scrolled up — same behaviour as
              // the Find Buddies feed and Book Court.
              FilterCollapseBox(
                collapsed: _filterCollapse.isCollapsed,
                collapseHeight: true,
                child: CoachQuickFilterRow(
                  verifiedOnly: filter.verifiedOnly,
                  availableOnly: filter.availableOnly,
                  favoritesOnly: filter.favoritesOnly,
                  myCoachesOnly: filter.myCoachesOnly,
                  signedIn: _userId != null,
                  locationEnabled: shared?.locationEnabled ?? false,
                  radiusKm: shared?.radiusKm,
                  activeFilterCount:
                      filter.activeCount + (shared?.activeCount ?? 0),
                  filterSummary: _filterSummary,
                  onToggleFilter: _toggleQuickFilter,
                  onShowAdvancedFilter: _showAdvancedFilter,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _reload,
            child: _loading
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: const [
                      Padding(
                        padding: EdgeInsets.only(top: 80),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    ],
                  )
                : _coaches.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 80),
                        child: Column(
                          children: [
                            Icon(
                              Icons.school_rounded,
                              size: 56,
                              color: Colors.grey.shade400,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'ไม่พบโค้ชที่ตรงกับตัวกรอง',
                              style: TextStyle(
                                fontSize: 15,
                                color: Colors.grey.shade700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  )
                : ListView.builder(
                    key: const PageStorageKey<String>('find_coach_feed'),
                    controller: _scrollController,
                    padding: const EdgeInsets.only(top: 8, bottom: 120),
                    itemCount: _coaches.length + (_isLoadingMore ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index >= _coaches.length) {
                        return const Padding(
                          padding: EdgeInsets.all(16),
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }
                      final coach = _coaches[index];
                      return CoachCard(
                        coach: coach,
                        distanceKm: _distanceTo(coach),
                        onTap: () => _openCoach(coach),
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }

  double? _distanceTo(CoachSummary coach) {
    if (_userLat == null || _userLng == null) return null;
    var best = double.infinity;
    for (final a in coach.serviceAreas) {
      if (a.lat == null || a.lng == null) continue;
      final d = distanceKm(_userLat!, _userLng!, a.lat!, a.lng!);
      if (d < best) best = d;
    }
    return best.isFinite ? best : null;
  }

  static String _mapRequestError(Object e) {
    final raw = e.toString();
    if (raw.contains('SLOT_UNAVAILABLE')) {
      return 'ช่วงเวลานี้โค้ชไม่ว่างหรือถูกจองแล้ว';
    }
    if (raw.contains('SPORT_NOT_OFFERED')) {
      return 'โค้ชไม่ได้สอนกีฬานี้';
    }
    if (raw.contains('TEACHING_MODE_NOT_OFFERED')) {
      return 'โค้ชไม่รับสอนรูปแบบนี้';
    }
    if (raw.contains('SELF_REQUEST_NOT_ALLOWED')) {
      return 'ไม่สามารถส่งคำขอให้ตัวเองได้';
    }
    if (raw.contains('COACH_NOT_AVAILABLE')) {
      return 'โค้ชนี้ไม่เปิดรับคำขอแล้ว';
    }
    if (raw.contains('UNAUTHORIZED')) return 'กรุณาเข้าสู่ระบบใหม่';
    return 'ดำเนินการไม่สำเร็จ กรุณาลองใหม่อีกครั้ง';
  }
}
