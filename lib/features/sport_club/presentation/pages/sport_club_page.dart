import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sheserved/services/auth_service.dart';
import 'package:sheserved/core/constants/app_colors.dart';
import 'package:sheserved/features/community/find_buddies/data/fitness_buddies_repository.dart';
import 'package:sheserved/shared/widgets/tlz_drawer.dart';
import 'package:sheserved/shared/widgets/tlz_app_top_bar.dart';
import 'package:sheserved/shared/widgets/tlz_bottom_navigation_bar.dart';
import '../widgets/sheets/session_picker_sheet.dart';
import '../widgets/sheets/create_session_sheet.dart';
import '../widgets/sheets/advanced_filter_sheet.dart';
import '../widgets/sheets/group_detail_sheet.dart';
import '../widgets/feed/sport_category_chips.dart';
import '../widgets/feed/quick_filter_row.dart';
import '../widgets/feed/sport_club_filter_button.dart';
import '../widgets/feed/radius_slider_control.dart';
import '../widgets/feed/group_card.dart';
import '../widgets/feed/empty_filter_state.dart';
import '../widgets/sport_club_utils.dart';
import '../../domain/sport_club_filter.dart';
import '../../application/sport_club_filter_store.dart';
import '../../application/sport_club_group_query.dart';
import '../../application/sport_club_card_hydrator.dart';
import '../../application/sport_club_booking_service.dart';
import '../../application/sport_club_data_freshness_policy.dart';
import '../../application/sport_club_intent.dart';
import '../../application/feed_filter_collapse_controller.dart';
import '../../services/sport_club_deep_link_service.dart';
import '../../shared/application/sports_hub_controller.dart';
import '../../shared/domain/sports_hub_filter_state.dart';

class SportClubPageController {
  /// Sport name the Sports Hub header should show while the Find Buddies
  /// filter bar is collapsed, or null to keep the header default.
  final ValueNotifier<String?> feedTitle = ValueNotifier<String?>(null);

  /// Title the hub header should show for Find Buddies: the active sport name
  /// while the filter bar is collapsed, otherwise null (keep the default).
  static String? feedTitleFor({
    required bool filtersCollapsed,
    required String? sportName,
  }) => filtersCollapsed ? sportName : null;

  Object? _owner;
  Future<void> Function()? _refresh;
  Future<void> Function()? _refreshIfStale;
  Future<void> Function(String roomId, String groupId)? _openChat;
  Future<void> Function()? _createGroup;

  void _attach(
    Object owner, {
    required Future<void> Function() refresh,
    required Future<void> Function() refreshIfStale,
    required Future<void> Function(String roomId, String groupId) openChat,
    required Future<void> Function() createGroup,
  }) {
    _owner = owner;
    _refresh = refresh;
    _refreshIfStale = refreshIfStale;
    _openChat = openChat;
    _createGroup = createGroup;
  }

  void _detach(Object owner) {
    if (!identical(_owner, owner)) return;
    _owner = null;
    _refresh = null;
    _refreshIfStale = null;
    _openChat = null;
    _createGroup = null;
  }

  Future<void> refresh() async {
    await _refresh?.call();
  }

  Future<void> refreshIfStale() async {
    await _refreshIfStale?.call();
  }

  Future<void> openGroupChat(String roomId, String groupId) async {
    await _openChat?.call(roomId, groupId);
  }

  Future<void> createGroup() async {
    await _createGroup?.call();
  }

  void dispose() {
    feedTitle.dispose();
  }
}

class SportClubPage extends StatefulWidget {
  final bool embeddedInSportsHub;
  final SportClubPageController? controller;

  /// Shared Sports Hub filter state. When present, the shared fields of
  /// [_filter] (sport, keyword, province, district, location/radius) follow
  /// the hub so the same values apply on the Book Court and Find Coach
  /// pages, and edits made here propagate back to the hub.
  final SportsHubController? hubController;

  const SportClubPage({
    super.key,
    this.embeddedInSportsHub = false,
    this.controller,
    this.hubController,
  });

  @override
  State<SportClubPage> createState() => _SportClubPageState();
}

class _SportClubPageState extends State<SportClubPage> {
  late final FitnessBuddiesRepository _repo;
  late final SportClubGroupQuery _groupQuery;
  late final SportClubCardHydrator _cardHydrator;
  late final SportClubBookingService _booking;
  final _filterStore = const SportClubFilterStore();
  static const _freshnessPolicy = SportClubDataFreshnessPolicy();
  SupabaseClient get _client => Supabase.instance.client;
  List<Map<String, dynamic>> _groups = [];
  Map<String, SportClubGroupCardData> _cardDataByGroupId = {};
  List<Map<String, dynamic>> _sports = [];
  SportClubFilter _filter = const SportClubFilter();
  bool _loading = true;
  bool _reloadingGroups = false;
  Set<String> _myAdminGroups = {};
  Set<String> _myJoinedGroupIds = {};
  Set<String> _myPendingGroupIds = {};
  Set<String> _myBlockedGroupIds = {};
  Set<String> _myCreatedSportIds = {};
  bool _intentHandled = false;
  double? _userLat;
  double? _userLng;
  int _filterRequestId = 0;
  DateTime? _lastSuccessfulFetchAt;
  bool _backgroundRefreshInFlight = false;
  final _listScrollController = ScrollController();
  final _detailScrollController = ScrollController();
  static const _pageSize = 10;
  int _currentOffset = 0;
  bool _hasMore = true;
  bool _isLoadingMore = false;
  final _filterCollapse = FeedFilterCollapseController();
  final _filterBarKey = GlobalKey();
  double _filterBarHeight = 0;

  // Vertical offsets of the collapsing filter button. They mirror the filter
  // bar layout: 16 padding + 40 sport-chips row + 10 gap, with the button
  // centred inside the 44-high quick-filter row when expanded.
  static const double _filterButtonTopExpanded = 69;
  static const double _filterButtonTopCollapsed = 17;

  // Inset used before the filter bar is measured, so the first frame already
  // matches the usual bar height and the feed does not flash.
  static const double _filterBarFallbackHeight = 110;

  String? get _sportId => _filter.sportId;
  String get _q => _filter.q;
  String? get _province => _filter.province;
  String? get _district => _filter.district;
  double get _radiusKm => _filter.radiusKm;
  bool get _locationEnabled => _filter.locationEnabled;
  bool get _filterOpenOnly => _filter.openOnly;
  bool get _filterJoinedOnly => _filter.joinedOnly;
  bool get _filterManagedOnly => _filter.managedOnly;
  bool get _showRadiusControl =>
      _filter.locationEnabled && _userLat != null && _userLng != null;

  @override
  void initState() {
    super.initState();
    _repo = FitnessBuddiesRepository(Supabase.instance.client);
    _groupQuery = SportClubGroupQuery(
      listGroups: _repo.listGroups,
      idsWithAnySessions: _repo.filterGroupIdsWithAnySessions,
      idsWithUpcomingSessions: _repo.filterGroupIdsWithUpcomingSessions,
      idsWithFees: _repo.filterGroupIdsWithFees,
      idsWithSessionCostItems: _repo.filterGroupIdsWithSessionCostItems,
      pageSize: _pageSize,
    );
    _cardHydrator = SportClubCardHydrator(
      upcomingSessionsForGroups: _repo.listUpcomingSessionsForGroups,
      groupFeesForGroups: _repo.listPublicGroupFeesForGroups,
      sessionCostItemsForGroups: _repo.listPublicSessionCostItemsForGroups,
      groupPositionsForGroups: _repo.listPublicGroupPositionsForGroups,
    );
    _booking = SportClubBookingService(_repo.bookSession);
    _listScrollController.addListener(_onScroll);
    widget.hubController?.addListener(_onHubFilterChanged);
    _attachController();
    _init();
  }

  /// Applies shared hub filter changes (sport, keyword, province, district,
  /// location/radius) into this page's legacy filter and refetches. Buddies
  /// domain toggles that differ are adopted as well; the reverse direction
  /// (page -> hub) goes through [SportsHubController.absorbSportClubFilter]
  /// inside [_applyFilter], and both sides short-circuit on equality so no
  /// notification loop can occur.
  void _onHubFilterChanged() {
    final hub = widget.hubController;
    if (hub == null) return;
    final next = hub.toSportClubFilter();
    if (next == _filter) return;
    unawaited(_applyFilter(next));
  }

  void _attachController() {
    widget.controller?._attach(
      this,
      refresh: _reload,
      refreshIfStale: _refreshIfStale,
      openChat: _openGroupChatFromNotification,
      createGroup: _onCreateGroupPressed,
    );
  }

  @override
  void didUpdateWidget(covariant SportClubPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?._detach(this);
      _attachController();
    }
    if (oldWidget.hubController != widget.hubController) {
      oldWidget.hubController?.removeListener(_onHubFilterChanged);
      widget.hubController?.addListener(_onHubFilterChanged);
      _onHubFilterChanged();
    }
  }

  @override
  void dispose() {
    widget.controller?._detach(this);
    widget.hubController?.removeListener(_onHubFilterChanged);
    _listScrollController.dispose();
    _detailScrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Ensure we reflect latest ordering/data if dependencies change after hot reload.
    if (_sports.isEmpty && !_loading) {
      _init();
    }
  }

  void _onScroll() {
    _updateFilterCollapse();
    if (!_listScrollController.hasClients ||
        _loading ||
        _reloadingGroups ||
        _isLoadingMore ||
        !_hasMore) {
      return;
    }
    if (_listScrollController.position.pixels >=
        _listScrollController.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  /// Collapses the pinned filter rows once the feed is scrolled up past a
  /// threshold, and restores them when the user scrolls back down or taps
  /// the floating filter button.
  void _updateFilterCollapse() {
    if (!_listScrollController.hasClients) return;
    if (_filterCollapse.update(_listScrollController.position.pixels)) {
      setState(() {});
      _publishFeedTitle();
    }
  }

  /// Name of the sport currently selected in the sport filter, or null when
  /// the "ทั้งหมด" chip is active.
  String? get _selectedSportName {
    final sportId = _sportId;
    if (sportId == null) return null;
    for (final sport in _sports) {
      if (sport['id']?.toString() != sportId) continue;
      final name = sport['name_th']?.toString();
      return (name == null || name.isEmpty) ? null : name;
    }
    return null;
  }

  /// Hands the active sport name to the Sports Hub header while the filter
  /// bar is collapsed, so the header keeps showing which sport is filtered.
  void _publishFeedTitle() {
    widget.controller?.feedTitle.value = SportClubPageController.feedTitleFor(
      filtersCollapsed: _filterCollapse.isCollapsed,
      sportName: _selectedSportName,
    );
  }

  /// Measures the filter bar overlay so the feed can start below it and the
  /// refresh indicator stays visible while the bar is shown.
  void _scheduleFilterBarMeasure() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final box = _filterBarKey.currentContext?.findRenderObject();
      if (box is! RenderBox || !box.hasSize) return;
      final height = box.size.height;
      if ((height - _filterBarHeight).abs() < 0.5) return;
      setState(() => _filterBarHeight = height);
    });
  }

  Future<SportClubGroupPage> _fetchGroupPage({
    required int offset,
    required Set<String> adminIds,
    required Set<String> joinedGroupIds,
    required Set<String> blockedGroupIds,
    int? requestId,
  }) {
    return _groupQuery.fetch(
      filter: _filter,
      offset: offset,
      adminIds: adminIds,
      joinedGroupIds: joinedGroupIds,
      blockedGroupIds: blockedGroupIds,
      isAdmin: AuthService.instance.currentUser?.isAdmin == true,
      userLat: _userLat,
      userLng: _userLng,
      isStale: requestId == null ? null : () => requestId != _filterRequestId,
    );
  }

  /// Batch-loads secondary card data (sessions, fees, cost items, positions)
  /// for every group of a fetched page before it is committed to [_groups].
  Future<Map<String, SportClubGroupCardData>> _hydrateCardData(
    SportClubGroupPage page,
  ) {
    final groupIds = page.groups
        .map((g) => g['id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toList();
    return _cardHydrator.hydrate(
      groupIds: groupIds,
      groupIdsWithAnySessions: page.groupIdsWithAnySessions,
    );
  }

  /// Re-hydrates a single group's card data (e.g. after a session was
  /// created from that card) and merges it into the committed map.
  Future<void> _refreshGroupCardData(String groupId) async {
    if (groupId.isEmpty) return;
    try {
      final anySessionIds = await _repo.filterGroupIdsWithAnySessions([
        groupId,
      ]);
      final data = await _cardHydrator.hydrate(
        groupIds: [groupId],
        groupIdsWithAnySessions: anySessionIds,
      );
      if (!mounted || !data.containsKey(groupId)) return;
      setState(() {
        _cardDataByGroupId = {..._cardDataByGroupId, ...data};
      });
    } catch (_) {
      // Keep the previously committed card data on refresh failure.
    }
  }

  Future<void> _loadMore() async {
    if (_loading || _reloadingGroups || _isLoadingMore || !_hasMore) return;
    final requestId = ++_filterRequestId;
    setState(() => _isLoadingMore = true);
    try {
      final page = await _fetchGroupPage(
        offset: _currentOffset,
        adminIds: _myAdminGroups,
        joinedGroupIds: _myJoinedGroupIds,
        blockedGroupIds: _myBlockedGroupIds,
        requestId: requestId,
      );
      final cardData = await _hydrateCardData(page);
      if (!mounted) return;
      if (requestId != _filterRequestId) {
        setState(() => _isLoadingMore = false);
        return;
      }
      setState(() {
        _groups.addAll(page.groups);
        _cardDataByGroupId.addAll(cardData);
        sortGroupsByDistance(
          _groups,
          locationEnabled: _locationEnabled,
          userLat: _userLat,
          userLng: _userLng,
        );
        _currentOffset = page.nextOffset;
        _hasMore = page.hasMore;
        _isLoadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoadingMore = false);
    }
  }

  Future<void> _restoreFilterState(String? userId) async {
    try {
      final saved = await _filterStore.load(userId);
      if (saved != null) _filter = saved;

      if (_filter.locationEnabled) {
        final permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.whileInUse ||
            permission == LocationPermission.always) {
          try {
            final position = await Geolocator.getCurrentPosition();
            _userLat = position.latitude;
            _userLng = position.longitude;
          } catch (_) {
            _filter = _filter.copyWith(locationEnabled: false);
          }
        } else {
          _filter = _filter.copyWith(locationEnabled: false);
        }
      }
    } catch (_) {
      // Ignore malformed or unavailable local preferences and use defaults.
    }

    final hub = widget.hubController;
    if (hub == null) return;
    if (!hub.isLoaded) await hub.load();
    if (hub.state == const SportsHubFilterState()) {
      // Fresh hub namespace: seed it from the legacy persisted filter so
      // existing users keep their sport/location choices (21.7.2 migration
      // path). A hub that already has its own saved state wins instead.
      hub.seedFromSportClubFilter(_filter);
    }
    final hubFilter = hub.toSportClubFilter();
    if (hubFilter != _filter) _filter = hubFilter;
  }

  Future<void> _persistFilterState() =>
      _filterStore.save(AuthService.instance.currentUser?.id, _filter);

  Future<
    ({
      Set<String> admin,
      Set<String> joined,
      Set<String> pending,
      Set<String> blocked,
      Set<String> createdSports,
    })
  >
  _membershipSnapshot(String? userId) async {
    if (userId == null || userId.isEmpty) {
      return (
        admin: <String>{},
        joined: <String>{},
        pending: <String>{},
        blocked: <String>{},
        createdSports: <String>{},
      );
    }
    final results = await Future.wait([
      _repo.listMyAdminGroupIds(userId),
      _repo.listMyJoinedGroupIds(userId),
      _repo.listMyPendingGroupIds(userId),
      _repo.listMyBlockedGroupIds(userId),
      _repo.listMyCreatedSportIds(userId),
    ]);
    return (
      admin: results[0],
      joined: results[1],
      pending: results[2],
      blocked: results[3],
      createdSports: results[4],
    );
  }

  Future<void> _init() async {
    final requestId = ++_filterRequestId;
    try {
      final userId = AuthService.instance.currentUser?.id;
      await _restoreFilterState(userId);
      if (requestId != _filterRequestId) return;
      final sports = await _repo.getApprovedSports(userId: userId);
      final membership = await _membershipSnapshot(userId);
      final page = await _fetchGroupPage(
        offset: 0,
        adminIds: membership.admin,
        joinedGroupIds: membership.joined,
        blockedGroupIds: membership.blocked,
        requestId: requestId,
      );
      final cardData = await _hydrateCardData(page);

      if (!mounted || requestId != _filterRequestId) return;
      setState(() {
        _sports = sports;
        _groups = page.groups;
        _cardDataByGroupId = cardData;
        _loading = false;
        _currentOffset = page.nextOffset;
        _hasMore = page.hasMore;
        _myAdminGroups = membership.admin;
        _myJoinedGroupIds = membership.joined;
        _myPendingGroupIds = membership.pending;
        _myBlockedGroupIds = membership.blocked;
        _myCreatedSportIds = membership.createdSports;
      });
      _lastSuccessfulFetchAt = DateTime.now();

      _publishFeedTitle();
      // Phase 2.3: handle redirect+intent after login
      _handleIntent();
      // Phase 20: handle pending deep link
      _handlePendingDeepLink();
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _handlePendingDeepLink() async {
    final deepLink = SportClubDeepLinkService.consumePendingDeepLink();
    if (deepLink == null) return;

    try {
      final groupData = await _repo.getGroupById(deepLink.groupId);
      if (groupData != null && mounted) {
        if (deepLink.src == 'share' || deepLink.src == 'qr') {
          // Record visit anonymously or authenticated
          await _client
              .rpc(
                'record_fitness_group_share_visit',
                params: {'p_group_id': deepLink.groupId},
              )
              .catchError((_) => null);
        }
        // Show group detail. The sheet itself handles Guest mode correctly.
        _showGroupDetailSheet(groupData);
      }
    } catch (e) {
      debugPrint('Failed to load group for deep link: $e');
    }
  }

  void _handleIntent() {
    if (_intentHandled) return;
    final resolved = resolveSportClubIntent(
      ModalRoute.of(context)?.settings.arguments,
      _groups,
      AuthService.instance.currentUser?.id,
    );
    if (!resolved.recognized) return;

    _intentHandled = true;
    final groupId = resolved.groupId;
    if (groupId == null) return;

    if (resolved.kind == 'open_chat') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _openGroupChatForGroup(
          groupId,
          group: resolved.group,
          chatRoomId: resolved.chatRoomId,
        );
      });
      return;
    }

    final group = resolved.group;
    if (group == null) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (resolved.kind == 'review_pending') {
        _showGroupDetailSheet(group);
        return;
      }

      SessionPickerSheet.show(
        context,
        repo: _repo,
        client: _client,
        groupId: groupId,
        requiresOwnerApproval: resolved.requiresOwnerApproval,
        onBook: (sessionId, {positionId}) => _book(
          sessionId,
          requiresOwnerApproval: resolved.requiresOwnerApproval,
          groupId: groupId,
          positionId: positionId,
        ),
      );
    });
  }

  Future<void> _reload() async {
    final requestId = ++_filterRequestId;
    if (mounted) setState(() => _reloadingGroups = true);
    final userId = AuthService.instance.currentUser?.id;
    try {
      final membership = await _membershipSnapshot(userId);
      final page = await _fetchGroupPage(
        offset: 0,
        adminIds: membership.admin,
        joinedGroupIds: membership.joined,
        blockedGroupIds: membership.blocked,
        requestId: requestId,
      );
      final cardData = await _hydrateCardData(page);

      if (!mounted || requestId != _filterRequestId) return;
      setState(() {
        _groups = page.groups;
        _cardDataByGroupId = cardData;
        _currentOffset = page.nextOffset;
        _hasMore = page.hasMore;
        _myAdminGroups = membership.admin;
        _myJoinedGroupIds = membership.joined;
        _myPendingGroupIds = membership.pending;
        _myBlockedGroupIds = membership.blocked;
        _myCreatedSportIds = membership.createdSports;
      });
      _lastSuccessfulFetchAt = DateTime.now();
    } on StateError catch (error) {
      if (error.message != 'STALE_FILTER_REQUEST') rethrow;
    } finally {
      if (mounted && requestId == _filterRequestId) {
        setState(() => _reloadingGroups = false);
      }
    }
  }

  Future<void> _refreshIfStale() async {
    if (!mounted ||
        _loading ||
        _reloadingGroups ||
        _isLoadingMore ||
        _backgroundRefreshInFlight ||
        !_freshnessPolicy.shouldRefresh(
          _lastSuccessfulFetchAt,
          now: DateTime.now(),
        )) {
      return;
    }

    _backgroundRefreshInFlight = true;
    final requestId = ++_filterRequestId;
    try {
      final userId = AuthService.instance.currentUser?.id;
      final membership = await _membershipSnapshot(userId);
      final targetOffset = _currentOffset;
      final refreshedGroups = <Map<String, dynamic>>[];
      final groupIdsWithAnySessions = <String>{};
      var offset = 0;
      var hasMore = true;

      do {
        final page = await _fetchGroupPage(
          offset: offset,
          adminIds: membership.admin,
          joinedGroupIds: membership.joined,
          blockedGroupIds: membership.blocked,
          requestId: requestId,
        );
        refreshedGroups.addAll(page.groups);
        groupIdsWithAnySessions.addAll(page.groupIdsWithAnySessions);
        offset = page.nextOffset;
        hasMore = page.hasMore;
      } while (hasMore &&
          (offset < targetOffset || refreshedGroups.length < _groups.length));

      sortGroupsByDistance(
        refreshedGroups,
        locationEnabled: _locationEnabled,
        userLat: _userLat,
        userLng: _userLng,
      );
      final refreshedPage = SportClubGroupPage(
        groups: refreshedGroups,
        nextOffset: offset,
        hasMore: hasMore,
        groupIdsWithAnySessions: groupIdsWithAnySessions,
      );
      final cardData = await _hydrateCardData(refreshedPage);

      if (!mounted || requestId != _filterRequestId) return;
      setState(() {
        _groups = refreshedGroups;
        _cardDataByGroupId = cardData;
        _currentOffset = offset;
        _hasMore = hasMore;
        _myAdminGroups = membership.admin;
        _myJoinedGroupIds = membership.joined;
        _myPendingGroupIds = membership.pending;
        _myBlockedGroupIds = membership.blocked;
        _myCreatedSportIds = membership.createdSports;
      });
      _lastSuccessfulFetchAt = DateTime.now();
    } catch (_) {
    } finally {
      _backgroundRefreshInFlight = false;
    }
  }

  Future<void> _book(
    String sessionId, {
    required bool requiresOwnerApproval,
    String? groupId,
    String? positionId,
  }) async {
    String? bookingId;
    try {
      bookingId = await _booking.book(
        userId: AuthService.instance.currentUser?.id,
        sessionId: sessionId,
        positionId: positionId,
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
          'SportClub booking failed: '
          'type=${e.runtimeType}, code=${bookingErrorCode(e)}',
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(mapBookingError(e))));
      return;
    }
    if (bookingId == null) {
      if (!mounted) return;
      Navigator.pushNamed(
        context,
        '/login',
        arguments: {
          'redirect': '/community/sport-club',
          if (groupId != null)
            'args': {'groupId': groupId, 'intent': 'join_group'},
        },
      );
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          requiresOwnerApproval
              ? 'ส่งคำขอเข้าร่วมแล้ว รอให้แอดมินอนุมัติ'
              : 'เข้าร่วมก๊วนสำเร็จ',
        ),
      ),
    );
    await _reload();
  }

  bool _canViewFullGroup(Map<String, dynamic> _) => true;

  @override
  Widget build(BuildContext context) {
    if (widget.embeddedInSportsHub) return _buildFindBuddiesContent();

    return Scaffold(
      backgroundColor: AppColors.primary,
      extendBody: true,
      drawer: TlzDrawer(),
      bottomNavigationBar: TlzBottomNavigationBar(
        currentIndex: -1,
        onIndexChanged: (index) => _onNavIndexChanged(index),
        onAddPressed: () => _onAddPressed(),
      ),
      body: Column(
        children: [
          // Custom Header matching home page style
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(32),
                bottomRight: Radius.circular(32),
              ),
            ),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: TlzAppTopBar.onPrimary(
                  // Menu button
                  // Title
                  middle: const FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'หาเพื่อนออกกำลังกาย',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                    ),
                  ),
                  onChatRoomTap: _openGroupChatFromNotification,
                  // Action buttons
                  actions: [
                    IconButton(
                      tooltip: 'รีเฟรช',
                      icon: const Icon(Icons.refresh, color: Colors.white),
                      onPressed: _reloadingGroups ? null : _reload,
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Body content
          Expanded(
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(32),
                  topRight: Radius.circular(32),
                ),
              ),
              child: _buildFindBuddiesContent(),
            ),
          ),
        ],
      ),
      floatingActionButton: _buildFloatingButtons(),
    );
  }

  Widget _buildFindBuddiesContent() {
    _scheduleFilterBarMeasure();
    final barHeight = _filterBarHeight > 0
        ? _filterBarHeight
        : _filterBarFallbackHeight;
    final filterBarInset = barHeight + 8;
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
      child: Stack(
        children: [
          RefreshIndicator(
            onRefresh: _reload,
            displacement: barHeight + 24,
            child: ListView(
              key: const PageStorageKey<String>('find_buddies_feed'),
              controller: _listScrollController,
              padding: EdgeInsets.fromLTRB(16, filterBarInset, 16, 16),
              children: [
                RadiusSliderControl(
                  visible: _showRadiusControl && _locationEnabled,
                  radiusKm: _radiusKm,
                  onChanged: (value) => setState(
                    () => _filter = _filter.copyWith(radiusKm: value),
                  ),
                  onChangeEnd: (_) async {
                    await _persistFilterState();
                    await _reload();
                  },
                  onReset: _resetRadiusFilter,
                ),
                if (_showRadiusControl && _locationEnabled)
                  const SizedBox(height: 12),
                if (_loading || _reloadingGroups)
                  for (var i = 0; i < 3; i++) const SkeletonGroupCard(),
                if (!_loading && !_reloadingGroups && _groups.isEmpty)
                  EmptyFilterState(
                    activeFilterCount: _activeFilterCount,
                    filterSummary: _filterSummary,
                    onClearFilters: _clearAllFilters,
                  ),
                if (!_loading && !_reloadingGroups) ...[
                  for (final g in _groups)
                    if (_canViewFullGroup(g))
                      GroupCard(
                        group: g,
                        cardData:
                            _cardDataByGroupId[g['id']?.toString() ?? ''] ??
                            SportClubGroupCardData.empty,
                        repo: _repo,
                        client: _client,
                        myAdminGroups: _myAdminGroups,
                        myJoinedGroupIds: _myJoinedGroupIds,
                        myPendingGroupIds: _myPendingGroupIds,
                        myBlockedGroupIds: _myBlockedGroupIds,
                        onTap: () => _showGroupDetailSheet(g),
                        onBook: _book,
                        onSessionCreated: () =>
                            _refreshGroupCardData(g['id']?.toString() ?? ''),
                      ),
                ],
                if (_isLoadingMore)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                const SizedBox(height: 120),
              ],
            ),
          ),
          // Filter bar overlay: slides up and fades away while the feed
          // scrolls, without changing its layout height, so the cards never
          // jump. Its opaque background hides the feed while it is visible.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: AnimatedSlide(
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOutCubic,
              offset: _filterCollapse.isCollapsed
                  ? const Offset(0, -0.6)
                  : Offset.zero,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 240),
                opacity: _filterCollapse.isCollapsed ? 0 : 1,
                child: Container(
                  key: _filterBarKey,
                  width: double.infinity,
                  color: Colors.white,
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: SportCategoryChips(
                              sports: _sports,
                              selectedSportId: _sportId,
                              myCreatedSportIds: _myCreatedSportIds,
                              onSportSelected: (id, selected) async {
                                setState(() {
                                  final nextSportId = selected ? id : null;
                                  _filter = _filter.copyWith(
                                    sportId: nextSportId,
                                    clearSportId: nextSportId == null,
                                  );
                                  _reloadingGroups = true;
                                });
                                _publishFeedTitle();
                                await _persistFilterState();
                                widget.hubController?.absorbSportClubFilter(
                                  _filter,
                                );
                                await _reload();
                              },
                            ),
                          ),
                          const AddSportFab(),
                        ],
                      ),
                      const SizedBox(height: 10),
                      QuickFilterRow(
                        filterOpenOnly: _filterOpenOnly,
                        filterJoinedOnly: _filterJoinedOnly,
                        filterManagedOnly: _filterManagedOnly,
                        locationEnabled: _locationEnabled,
                        radiusKm: _radiusKm,
                        activeFilterCount: _activeFilterCount,
                        filterSummary: _filterSummary,
                        onToggleFilter: _toggleQuickFilter,
                        onShowAdvancedFilter: _showAdvancedFilterSheet,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // Filter button overlay: slides from the quick-filter row position up
          // to the sport-chips row while the filter bar fades away, so it reads
          // as the same button that moved up.
          AnimatedPositioned(
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
            left: 16,
            top: _filterCollapse.isCollapsed
                ? _filterButtonTopCollapsed
                : _filterButtonTopExpanded,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 200),
              opacity: _filterCollapse.isCollapsed ? 1 : 0,
              child: IgnorePointer(
                ignoring: !_filterCollapse.isCollapsed,
                child: ExcludeSemantics(
                  excluding: !_filterCollapse.isCollapsed,
                  child: SportClubFilterButton(
                    activeFilterCount: _activeFilterCount,
                    filterSummary: _filterSummary,
                    onTap: () {
                      setState(_filterCollapse.expand);
                      _publishFeedTitle();
                      _showAdvancedFilterSheet();
                    },
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  int get _activeFilterCount => _filter.activeCount;

  String get _filterSummary => _filter.summary;

  Future<bool> _requireLoginForFilter() async {
    if (AuthService.instance.currentUser != null) return true;
    await Navigator.pushNamed(
      context,
      '/login',
      arguments: {'redirect': '/community/sport-club'},
    );
    return AuthService.instance.currentUser != null;
  }

  Future<void> _applyFilter(SportClubFilter next) async {
    setState(() => _filter = next);
    _publishFeedTitle();
    await _persistFilterState();
    // Push shared fields back into the hub so Book Court / Find Coach see
    // the same sport and location. No-op when the change came from the hub.
    widget.hubController?.absorbSportClubFilter(next);
    await _reload();
  }

  Future<void> _toggleQuickFilter(String filter) async {
    if (filter == 'radius') {
      if (_filter.locationEnabled) {
        await _applyFilter(_filter.copyWith(locationEnabled: false));
        return;
      }
      final ok = await _requestLocation();
      if (!ok || !mounted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'ไม่สามารถเข้าถึงตำแหน่งได้ กรุณาอนุญาตสิทธิ์ตำแหน่ง',
              ),
            ),
          );
        }
        return;
      }
      await _applyFilter(_filter.copyWith(locationEnabled: true));
      return;
    }
    if ((filter == 'joined' || filter == 'managed') &&
        !await _requireLoginForFilter()) {
      return;
    }
    await _applyFilter(_filter.toggleQuickFilter(filter));
  }

  Future<void> _resetRadiusFilter() =>
      _applyFilter(_filter.copyWith(radiusKm: SportClubFilter.defaultRadiusKm));

  Future<void> _clearAllFilters() => _applyFilter(_filter.clearAll());

  Future<void> _openGroupChatFromNotification(
    String roomId,
    String groupId,
  ) async {
    await _openGroupChatForGroup(groupId, chatRoomId: roomId);
  }

  Future<void> _openGroupChatForGroup(
    String groupId, {
    Map<String, dynamic>? group,
    String? chatRoomId,
  }) async {
    Map<String, dynamic>? target = group;
    if (target == null) {
      for (final candidate in _groups) {
        if (candidate['id']?.toString() == groupId) {
          target = candidate;
          break;
        }
      }
    }
    if (target == null) {
      try {
        target = await _repo.getGroupById(groupId);
      } catch (_) {
        target = null;
      }
    }
    if (!mounted || target == null) return;
    await _showGroupDetailSheet(
      target,
      openChatOnShow: true,
      chatRoomId: chatRoomId,
    );
  }

  Future<void> _showGroupDetailSheet(
    Map<String, dynamic> group, {
    bool openChatOnShow = false,
    String? chatRoomId,
  }) {
    return GroupDetailSheet.show(
      context,
      group: group,
      repo: _repo,
      client: _client,
      myAdminGroups: _myAdminGroups,
      myJoinedGroupIds: _myJoinedGroupIds,
      myPendingGroupIds: _myPendingGroupIds,
      detailScrollController: _detailScrollController,
      onBook: _book,
      onFeedRefresh: _reload,
      onPageRefresh: _init,
      openChatOnShow: openChatOnShow,
      chatRoomId: chatRoomId,
    );
  }

  Future<void> _onCreateGroupPressed() async {
    final currentUser = AuthService.instance.currentUser;
    if (currentUser == null) {
      await Navigator.pushNamed(
        context,
        '/login',
        arguments: {'returnAfterLogin': true},
      );
      if (!mounted) return;
      if (AuthService.instance.currentUser == null) return;
    }
    final result = await Navigator.pushNamed(
      context,
      '/community/sport-club/group/create',
      arguments: {'sportId': _sportId},
    );
    if (result is! Map) return;
    final String groupId = result['groupId']?.toString() ?? '';
    final String? newSportId = result['sportId']?.toString();
    if (newSportId != null && _sportId != newSportId) {
      setState(() => _filter = _filter.copyWith(sportId: newSportId));
    }
    final refreshFuture = _reload();
    if (groupId.isNotEmpty) {
      try {
        await refreshFuture;
      } catch (_) {}
      if (!mounted) return;
      await CreateSessionSheet.show(
        context,
        repo: _repo,
        client: _client,
        groupId: groupId,
        onSessionCreated: () => _refreshGroupCardData(groupId),
      );
    } else {
      try {
        await refreshFuture;
      } catch (_) {}
    }
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_listScrollController.hasClients) {
        _listScrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Widget _buildFloatingButtons() {
    return Padding(
      padding: const EdgeInsets.only(right: 4, bottom: 4),
      child: FloatingActionButton.extended(
        heroTag: 'createGroupFab',
        onPressed: _onCreateGroupPressed,
        icon: const Icon(Icons.add),
        label: const Text('สร้างก๊วน'),
      ),
    );
  }

  void _onNavIndexChanged(int index) {
    final routes = <int, String>{
      0: '/home',
      1: '/volunteer',
      3: '/pharmacy',
      4: '/profile',
    };
    final route = routes[index];
    if (route == null) return;
    Navigator.pushReplacementNamed(context, route);
  }

  void _onAddPressed() {
    Navigator.pushNamed(context, '/emergency');
  }

  Future<bool> _requestLocation() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return false;
      }
      final pos = await Geolocator.getCurrentPosition();
      _userLat = pos.latitude;
      _userLng = pos.longitude;
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _showAdvancedFilterSheet() async {
    final appliedFilter = await AdvancedFilterSheet.show(
      context,
      currentFilter: AdvancedFilterValues(
        q: _q,
        province: _province,
        district: _district,
        openOnly: _filterOpenOnly,
        joinedOnly: _filterJoinedOnly,
        managedOnly: _filterManagedOnly,
        allLevelsOnly: _filter.allLevelsOnly,
        genderAnyOnly: _filter.genderAnyOnly,
        noFeesOnly: _filter.noFeesOnly,
        locationEnabled: _locationEnabled,
        radiusKm: _filter.radiusKm,
        locationReady: _userLat != null && _userLng != null,
      ),
      onRequestLocation: _requestLocation,
      onRequireLogin: _requireLoginForFilter,
    );
    if (appliedFilter == null || !mounted) return;
    await _applyFilter(
      _filter.copyWith(
        q: appliedFilter.q,
        province: appliedFilter.province,
        clearProvince: appliedFilter.province == null,
        district: appliedFilter.district,
        clearDistrict: appliedFilter.district == null,
        openOnly: appliedFilter.openOnly,
        joinedOnly: appliedFilter.joinedOnly,
        managedOnly: appliedFilter.managedOnly,
        allLevelsOnly: appliedFilter.allLevelsOnly,
        genderAnyOnly: appliedFilter.genderAnyOnly,
        noFeesOnly: appliedFilter.noFeesOnly,
        locationEnabled: appliedFilter.locationEnabled,
        radiusKm: appliedFilter.radiusKm,
      ),
    );
  }
}
