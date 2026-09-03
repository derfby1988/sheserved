import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:shimmer/shimmer.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../../../services/auth_service.dart';
import '../../../../../../core/constants/app_colors.dart';
import '../../../find_buddies/data/fitness_buddies_repository.dart';
import '../../../../../../shared/widgets/tlz_drawer.dart';
import '../../../../../../shared/widgets/tlz_app_top_bar.dart';
import '../../../../../../shared/widgets/tlz_bottom_navigation_bar.dart';
import '../../../../../../shared/widgets/thai_buddhist_date_picker.dart';
import '../../../find_buddies/presentation/widgets/group_chat_popup.dart';

class _GroupPageResult {
  final List<Map<String, dynamic>> groups;
  final int nextOffset;
  final bool hasMore;

  const _GroupPageResult({
    required this.groups,
    required this.nextOffset,
    required this.hasMore,
  });
}

class SportClubPage extends StatefulWidget {
  const SportClubPage({super.key});

  @override
  State<SportClubPage> createState() => _SportClubPageState();
}

class _SportClubPageState extends State<SportClubPage> {
  late final FitnessBuddiesRepository _repo;
  List<Map<String, dynamic>> _groups = [];
  List<Map<String, dynamic>> _sports = [];
  String? _sportId;
  String _q = '';
  bool _loading = true;
  bool _reloadingGroups = false;
  Set<String> _myAdminGroups = {};
  Set<String> _myJoinedGroupIds = {};
  Set<String> _myPendingGroupIds = {};
  Set<String> _myBlockedGroupIds = {};
  Set<String> _myCreatedSportIds = {};
  bool _intentHandled = false;
  bool _showMapView = false;
  String? _province;
  String? _district;
  double? _radiusKm;
  double? _userLat;
  double? _userLng;
  bool _locationEnabled = false;
  bool _filterOpenOnly = false;
  final _listScrollController = ScrollController();
  final _detailScrollController = ScrollController();
  static const _pageSize = 10;
  int _currentOffset = 0;
  bool _hasMore = true;
  bool _isLoadingMore = false;

  @override
  void initState() {
    super.initState();
    _repo = FitnessBuddiesRepository(Supabase.instance.client);
    _listScrollController.addListener(_onScroll);
    _init();
  }

  @override
  void dispose() {
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

  Future<_GroupPageResult> _fetchGroupPage({
    required int offset,
    required Set<String> adminIds,
    required Set<String> joinedGroupIds,
    required Set<String> blockedGroupIds,
  }) async {
    var nextOffset = offset;
    var hasMore = true;
    final visibleGroups = <Map<String, dynamic>>[];
    final isSheservedAdmin = AuthService.instance.currentUser?.isAdmin == true;

    while (visibleGroups.length < _pageSize && hasMore) {
      final page = await _repo.listGroups(
        sportId: _sportId,
        q: _q,
        openOnly: _filterOpenOnly,
        province: _province,
        district: _district,
        limit: _pageSize,
        offset: nextOffset,
      );
      if (page.isEmpty) {
        hasMore = false;
        break;
      }

      nextOffset += page.length;
      hasMore = page.length >= _pageSize;
      final locationFiltered = _applyLocationFilter(page);
      final groupIds = locationFiltered
          .map((g) => g['id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toList();
      final groupIdsWithSessions = await _repo
          .filterGroupIdsWithUpcomingSessions(groupIds);

      visibleGroups.addAll(
        locationFiltered.where((group) {
          final groupId = group['id']?.toString() ?? '';
          if (isSheservedAdmin ||
              adminIds.contains(groupId) ||
              joinedGroupIds.contains(groupId) ||
              blockedGroupIds.contains(groupId)) {
            return true;
          }
          return groupIdsWithSessions.contains(groupId);
        }),
      );
    }

    return _GroupPageResult(
      groups: visibleGroups,
      nextOffset: nextOffset,
      hasMore: hasMore,
    );
  }

  Future<void> _loadMore() async {
    if (_loading || _reloadingGroups || _isLoadingMore || !_hasMore) return;
    setState(() => _isLoadingMore = true);
    try {
      final page = await _fetchGroupPage(
        offset: _currentOffset,
        adminIds: _myAdminGroups,
        joinedGroupIds: _myJoinedGroupIds,
        blockedGroupIds: _myBlockedGroupIds,
      );
      if (!mounted) return;
      setState(() {
        _groups.addAll(page.groups);
        _currentOffset = page.nextOffset;
        _hasMore = page.hasMore;
        _isLoadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoadingMore = false);
    }
  }

  Future<void> _init() async {
    try {
      final userId = AuthService.instance.currentUser?.id;
      final sports = await _repo.getApprovedSports(userId: userId);
      final adminIds = userId != null
          ? await _repo.listMyAdminGroupIds(userId)
          : <String>{};
      final joinedGroupIds = userId != null
          ? await _repo.listMyJoinedGroupIds(userId)
          : <String>{};
      final createdSportIds = userId != null
          ? await _repo.listMyCreatedSportIds(userId)
          : <String>{};
      final pendingGroupIds = userId != null
          ? await _repo.listMyPendingGroupIds(userId)
          : <String>{};
      final blockedGroupIds = userId != null
          ? await _repo.listMyBlockedGroupIds(userId)
          : <String>{};
      final page = await _fetchGroupPage(
        offset: 0,
        adminIds: adminIds,
        joinedGroupIds: joinedGroupIds,
        blockedGroupIds: blockedGroupIds,
      );

      if (!mounted) return;
      setState(() {
        _sports = sports;
        _groups = page.groups;
        _loading = false;
        _currentOffset = page.nextOffset;
        _hasMore = page.hasMore;
        _myAdminGroups = adminIds;
        _myJoinedGroupIds = joinedGroupIds;
        _myPendingGroupIds = pendingGroupIds;
        _myBlockedGroupIds = blockedGroupIds;
        _myCreatedSportIds = createdSportIds;
      });

      // Phase 2.3: handle redirect+intent after login
      _handleIntent();
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  void _handleIntent() {
    if (_intentHandled) return;
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is! Map) return;

    final intent = args['intent']?.toString();
    final groupId = args['groupId']?.toString();
    if (groupId == null ||
        groupId.isEmpty ||
        (intent != 'join_group' && intent != 'review_pending')) {
      return;
    }

    _intentHandled = true;
    final group = _groups.cast<Map<String, dynamic>?>().firstWhere(
      (g) => g?['id']?.toString() == groupId,
      orElse: () => null,
    );
    if (group == null) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (intent == 'review_pending') {
        _showGroupDetailSheet(group);
        return;
      }

      final isGroupOwner =
          group['created_by']?.toString() ==
          AuthService.instance.currentUser?.id;
      final requiresOwnerApproval =
          group['requires_owner_approval'] == true && !isGroupOwner;
      _showSessionPickerSheet(
        groupId,
        requiresOwnerApproval: requiresOwnerApproval,
      );
    });
  }

  Future<void> _reload() async {
    setState(() => _reloadingGroups = true);
    final userId = AuthService.instance.currentUser?.id;
    try {
      final adminIds = userId != null
          ? await _repo.listMyAdminGroupIds(userId)
          : <String>{};
      final joinedGroupIds = userId != null
          ? await _repo.listMyJoinedGroupIds(userId)
          : <String>{};
      final createdSportIds = userId != null
          ? await _repo.listMyCreatedSportIds(userId)
          : <String>{};
      final pendingGroupIds = userId != null
          ? await _repo.listMyPendingGroupIds(userId)
          : <String>{};
      final blockedGroupIds = userId != null
          ? await _repo.listMyBlockedGroupIds(userId)
          : <String>{};
      final page = await _fetchGroupPage(
        offset: 0,
        adminIds: adminIds,
        joinedGroupIds: joinedGroupIds,
        blockedGroupIds: blockedGroupIds,
      );

      if (!mounted) return;
      setState(() {
        _groups = page.groups;
        _currentOffset = page.nextOffset;
        _hasMore = page.hasMore;
        _myAdminGroups = adminIds;
        _myJoinedGroupIds = joinedGroupIds;
        _myPendingGroupIds = pendingGroupIds;
        _myBlockedGroupIds = blockedGroupIds;
        _myCreatedSportIds = createdSportIds;
      });
    } finally {
      if (mounted) setState(() => _reloadingGroups = false);
    }
  }

  Future<void> _showSessionPickerSheet(
    String groupId, {
    required bool requiresOwnerApproval,
  }) async {
    final sessions = await _repo.listUpcomingSessions(groupId);
    if (!mounted) return;
    if (sessions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ยังไม่มีรอบนัดให้เข้าร่วม')),
      );
      return;
    }
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.6,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'เลือกรอบนัดที่ต้องการเข้าร่วม',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: sessions.length,
                    separatorBuilder: (_, __) => const Divider(),
                    itemBuilder: (ctx, i) {
                      final s = sessions[i];
                      final startsAt = DateTime.parse(
                        s['starts_at'].toString(),
                      ).toLocal();
                      final endsAt = DateTime.parse(
                        s['ends_at'].toString(),
                      ).toLocal();
                      final note = s['note']?.toString();
                      final capacity = (s['capacity'] as num?)?.toInt() ?? 0;
                      final confirmedCount =
                          (s['confirmed_count'] as num?)?.toInt() ?? 0;
                      final pendingCount =
                          (s['pending_count'] as num?)?.toInt() ?? 0;
                      final availableCount =
                          (s['available_count'] as num?)?.toInt() ??
                          (capacity - confirmedCount).clamp(0, capacity);
                      final isFull = capacity > 0 && availableCount <= 0;
                      final subtitleLines = <String>[
                        'ยืนยันแล้ว $confirmedCount / $capacity คน · เหลือ $availableCount ที่',
                        if (pendingCount > 0) 'รออนุมัติ $pendingCount คน',
                        if (note != null && note.isNotEmpty) note,
                      ];
                      return ListTile(
                        title: Text(_formatThaiSessionRange(startsAt, endsAt)),
                        subtitle: Text(
                          subtitleLines.join('\n'),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: isFull
                            ? const Text('เต็ม')
                            : const Icon(Icons.chevron_right),
                        onTap: isFull
                            ? null
                            : () {
                                Navigator.pop(ctx);
                                _book(
                                  s['id'].toString(),
                                  requiresOwnerApproval: requiresOwnerApproval,
                                  groupId: groupId,
                                );
                              },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _book(
    String sessionId, {
    required bool requiresOwnerApproval,
    String? groupId,
  }) async {
    final user = AuthService.instance.currentUser;
    if (user == null) {
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
    try {
      await _repo.bookSession(sessionId, user.id);
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
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_mapBookingError(e))));
    }
  }

  String _mapBookingError(Object e) {
    final raw = e.toString();
    if (raw.contains('GROUP_FULL') || raw.contains('SESSION_FULL')) {
      return 'รอบนัดนี้เต็มแล้ว กรุณาเลือกรอบนัดอื่น';
    }
    if (raw.contains('OVERLAP_BOOKING')) {
      return 'คุณมีรอบนัดซ้อนทับในช่วงเวลานี้ กรุณาเลือกเวลาอื่น';
    }
    if (raw.contains('SESSION_NOT_FOUND')) {
      return 'ไม่พบรอบนัดนี้ กรุณารีเฟรชและลองใหม่';
    }
    if (raw.contains('BOOKING_NOT_FOUND')) {
      return 'ไม่พบรอบจองนี้';
    }
    if (raw.contains('NOT_GROUP_ADMIN')) {
      return 'คุณไม่มีสิทธิ์ดำเนินการรายการนี้';
    }
    if (raw.contains('UNAUTHORIZED')) {
      return 'กรุณาเข้าสู่ระบบใหม่แล้วลองอีกครั้ง';
    }
    if (raw.contains('USER_BLOCKED')) {
      return 'คุณถูกบล็อกจากก๊วนนี้ ไม่สามารถจองรอบได้';
    }
    return 'จองไม่สำเร็จ กรุณาลองใหม่อีกครั้ง';
  }

  String _mapManagementError(Object e) {
    final raw = e.toString();
    if (raw.contains('SESSION_CAPACITY_BELOW_CONFIRMED')) {
      return 'จำนวนคนสูงสุดต้องไม่น้อยกว่าจำนวนผู้ยืนยันแล้วในรอบนี้';
    }
    if (raw.contains('OWNER_AUTO_JOIN_CAPACITY')) {
      return 'ไม่สามารถเปิดเข้าร่วมทุกรอบได้ เพราะมีรอบที่เต็มแล้ว';
    }
    if (raw.contains('OWNER_AUTO_JOIN_OVERLAP')) {
      return 'ไม่สามารถเปิดเข้าร่วมทุกรอบได้ เพราะมีรอบเวลาทับซ้อนกัน';
    }
    if (raw.contains('OWNER_ONLY')) {
      return 'เฉพาะเจ้าของก๊วนเท่านั้นที่เปลี่ยนการเข้าร่วมอัตโนมัติได้';
    }
    if (raw.contains('SESSION_FULL')) {
      return 'รอบนัดนี้เต็มแล้ว';
    }
    if (raw.contains('BOOKING_NOT_CONFIRMED')) {
      return 'ผู้ใช้นี้ไม่ได้ยืนยันเข้าร่วมรอบนี้แล้ว';
    }
    if (raw.contains('OWNER_USE_PARTICIPATION_TOGGLE')) {
      return 'เจ้าของก๊วนต้องใช้เมนูการเข้าร่วมของเจ้าของก๊วน';
    }
    if (raw.contains('NOT_GROUP_ADMIN')) {
      return 'คุณไม่มีสิทธิ์จัดการก๊วนนี้';
    }
    if (raw.contains('UNAUTHORIZED')) {
      return 'กรุณาเข้าสู่ระบบใหม่แล้วลองอีกครั้ง';
    }
    return 'ดำเนินการไม่สำเร็จ กรุณาลองใหม่อีกครั้ง';
  }

  String _mapApprovalError(Object e) {
    final raw = e.toString();
    if (raw.contains('SESSION_FULL')) {
      return 'รอบนัดนี้เต็มแล้ว ไม่สามารถอนุมัติผู้ขอรายนี้ได้\n'
          'กรุณาปฏิเสธคำขอ หรือเพิ่ม capacity ของรอบนัดก่อน';
    }
    return 'อนุมัติไม่สำเร็จ: ${_mapManagementError(e)}';
  }

  String _sessionCapacitySummary(
    Map<String, dynamic> session, {
    bool detailed = false,
    int? pendingCountOverride,
  }) {
    final capacity = (session['capacity'] as num?)?.toInt() ?? 0;
    final confirmed = (session['confirmed_count'] as num?)?.toInt() ?? 0;
    final pending =
        pendingCountOverride ??
        (session['pending_count'] as num?)?.toInt() ??
        0;
    final available =
        (session['available_count'] as num?)?.toInt() ??
        (capacity - confirmed).clamp(0, capacity);
    final pendingLabel = pending > 0 ? ' · รออนุมัติ $pending คน' : '';
    final confirmedLabel = detailed ? 'ผู้เข้าร่วม' : 'ยืนยันแล้ว';
    return '$confirmedLabel $confirmed / $capacity คน · เหลือ $available ที่$pendingLabel';
  }

  DateTime _roundUpToNearest(DateTime dt, {int roundMinutes = 30}) {
    final roundedDown = DateTime(
      dt.year,
      dt.month,
      dt.day,
      dt.hour,
      dt.minute - (dt.minute % roundMinutes),
    );
    return roundedDown.add(Duration(minutes: roundMinutes));
  }

  DateTime _dateTimeAt(DateTime date, TimeOfDay time) {
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  DateTime _endDateTimeAt(
    DateTime date,
    TimeOfDay startTime,
    TimeOfDay endTime,
  ) {
    final start = _dateTimeAt(date, startTime);
    var end = _dateTimeAt(date, endTime);
    if (!end.isAfter(start)) end = end.add(const Duration(days: 1));
    return end;
  }

  bool _canViewFullGroup(Map<String, dynamic> _) => true;

  @override
  Widget build(BuildContext context) {
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
                  // Action buttons
                  actions: [
                    IconButton(
                      tooltip: 'รีเฟรช',
                      icon: const Icon(Icons.refresh, color: Colors.white),
                      onPressed: _reloadingGroups ? null : _reload,
                    ),
                    IconButton(
                      tooltip: 'ค้นหา',
                      icon: const Icon(Icons.search, color: Colors.white),
                      onPressed: _showSearchDialog,
                    ),
                    PopupMenuButton<String>(
                      tooltip: 'เพิ่มเติม',
                      icon: const Icon(Icons.more_vert, color: Colors.white),
                      onSelected: (value) {
                        switch (value) {
                          case 'my_groups':
                            Navigator.pushNamed(
                              context,
                              '/community/sport-club/my-groups',
                            );
                          case 'toggle_view':
                            setState(() => _showMapView = !_showMapView);
                        }
                      },
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: 'my_groups',
                          child: Text('ก๊วนของฉัน'),
                        ),
                        PopupMenuItem(
                          value: 'toggle_view',
                          child: Text(
                            _showMapView ? 'แสดงรายการ' : 'แสดงแผนที่',
                          ),
                        ),
                      ],
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
              child: _showMapView && !_loading
                  ? _buildMapView()
                  : RefreshIndicator(
                      onRefresh: _reload,
                      child: ListView(
                        controller: _listScrollController,
                        padding: const EdgeInsets.all(16),
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: Row(
                                    children: [
                                      _buildSportChip(
                                        null,
                                        'ทั้งหมด',
                                        icon: '🏅',
                                      ),
                                      ..._sports.map(
                                        (s) => _buildSportChip(
                                          s['id']?.toString(),
                                          s['name_th']?.toString() ?? 'กีฬา',
                                          icon: s['icon']?.toString(),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              _buildAddSportFab(),
                            ],
                          ),
                          const SizedBox(height: 16),
                          if (_loading || _reloadingGroups)
                            for (var i = 0; i < 3; i++) _buildSkeletonCard(),
                          if (!_loading && !_reloadingGroups) ...[
                            for (final g in _groups)
                              if (_canViewFullGroup(g))
                                InkWell(
                                  onTap: () => _showGroupDetailSheet(g),
                                  child: Container(
                                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.7),
                                      borderRadius: BorderRadius.circular(24),
                                      border: Border.all(
                                        color: Colors.white.withOpacity(0.5),
                                        width: 1,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.05),
                                          blurRadius: 10,
                                          offset: const Offset(0, 4),
                                        ),
                                      ],
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.all(16),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          if ((g['venue_photo_url']
                                                      ?.toString() ??
                                                  g['cover_image_url']
                                                      ?.toString() ??
                                                  '')
                                              .isNotEmpty)
                                            ClipRRect(
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              child: Image.network(
                                                (g['venue_photo_url']
                                                            ?.toString()
                                                            .isNotEmpty ??
                                                        false)
                                                    ? g['venue_photo_url']
                                                          .toString()
                                                    : g['cover_image_url']
                                                          .toString(),
                                                height: 140,
                                                width: double.infinity,
                                                fit: BoxFit.cover,
                                              ),
                                            ),
                                          if ((g['venue_photo_url']
                                                      ?.toString() ??
                                                  g['cover_image_url']
                                                      ?.toString() ??
                                                  '')
                                              .isNotEmpty)
                                            const SizedBox(height: 8),
                                          Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Expanded(
                                                child: Row(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.center,
                                                  children: [
                                                    if ((g['sport_name']
                                                                ?.toString() ??
                                                            '')
                                                        .isNotEmpty)
                                                      _buildSportChipLabel(
                                                        g['sport_icon']
                                                            ?.toString(),
                                                        g['sport_name']
                                                            .toString(),
                                                      ),
                                                    if ((g['sport_name']
                                                                ?.toString() ??
                                                            '')
                                                        .isNotEmpty)
                                                      const SizedBox(width: 6),
                                                    Expanded(
                                                      child: Text(
                                                        g['name']?.toString() ??
                                                            '',
                                                        style: const TextStyle(
                                                          fontSize: 16,
                                                          fontWeight:
                                                              FontWeight.w600,
                                                        ),
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              const SizedBox(width: 6),
                                              if (g['gender_preference'] !=
                                                      null &&
                                                  g['gender_preference']
                                                          .toString() !=
                                                      'any')
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                                  decoration: BoxDecoration(
                                                    color: (g['gender_preference']
                                                                .toString() ==
                                                            'male'
                                                        ? Colors.blue
                                                        : Colors.pink).withOpacity(0.1),
                                                    borderRadius: BorderRadius.circular(12),
                                                    border: Border.all(
                                                      color: (g['gender_preference']
                                                                  .toString() ==
                                                              'male'
                                                          ? Colors.blue
                                                          : Colors.pink).withOpacity(0.2),
                                                    ),
                                                  ),
                                                  child: Text(
                                                    g['gender_preference']
                                                                .toString() ==
                                                            'male'
                                                        ? 'ช.'
                                                        : 'ญ.',
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      fontWeight: FontWeight.w600,
                                                      color: g['gender_preference']
                                                                  .toString() ==
                                                              'male'
                                                          ? Colors.blue.shade700
                                                          : Colors.pink.shade700,
                                                    ),
                                                  ),
                                                )
                                              else
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                                  decoration: BoxDecoration(
                                                    color: Colors.green.withOpacity(0.1),
                                                    borderRadius: BorderRadius.circular(12),
                                                    border: Border.all(
                                                      color: Colors.green.withOpacity(0.2),
                                                    ),
                                                  ),
                                                  child: Text(
                                                    'เสรี',
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      fontWeight: FontWeight.w600,
                                                      color: Colors.green.shade700,
                                                    ),
                                                  ),
                                                ),
                                            ],
                                          ),
                                          if ((g['description']?.toString() ??
                                                  '')
                                              .isNotEmpty)
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                top: 6,
                                              ),
                                              child: Text(
                                                g['description'].toString(),
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          if ((g['province']?.toString() ?? '')
                                              .isNotEmpty)
                                            Text(
                                              'พื้นที่: ' +
                                                  g['province'].toString() +
                                                  (g['district'] != null &&
                                                          g['district']
                                                              .toString()
                                                              .isNotEmpty
                                                      ? ' · ' +
                                                            g['district']
                                                                .toString()
                                                      : ''),
                                            ),
                                          const SizedBox(height: 8),
                                          FutureBuilder<List<dynamic>>(
                                            future: Future.wait<dynamic>([
                                              _repo.listUpcomingSessions(
                                                g['id'].toString(),
                                              ),
                                              _repo.hasAnySessions(
                                                g['id'].toString(),
                                              ),
                                            ]),
                                            builder: (context, snapshot) {
                                              final items =
                                                  (snapshot.data?[0] as List?)
                                                      ?.cast<
                                                        Map<String, dynamic>
                                                      >() ??
                                                  const <
                                                    Map<String, dynamic>
                                                  >[];
                                              final hasAnySessions =
                                                  snapshot.data?[1] == true;
                                              if (snapshot.connectionState !=
                                                  ConnectionState.done) {
                                                return const Padding(
                                                  padding: EdgeInsets.all(8.0),
                                                  child:
                                                      LinearProgressIndicator(
                                                        minHeight: 2,
                                                      ),
                                                );
                                              }
                                              if (snapshot.hasError) {
                                                return Text(
                                                  'โหลดรอบนัดไม่สำเร็จ: ${snapshot.error}',
                                                  style: const TextStyle(
                                                    color: Colors.red,
                                                  ),
                                                );
                                              }
                                              final gid =
                                                  g['id']?.toString() ?? '';
                                              if (items.isEmpty) {
                                                return Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      hasAnySessions
                                                          ? 'รอบนัดล่าสุดสิ้นสุดแล้ว'
                                                          : 'ยังไม่มีรอบนัด',
                                                    ),
                                                    if (_myBlockedGroupIds
                                                        .contains(gid))
                                                      Align(
                                                        alignment: Alignment
                                                            .centerRight,
                                                        child: TextButton.icon(
                                                          onPressed: null,
                                                          icon: const Icon(
                                                            Icons
                                                                .hourglass_empty,
                                                          ),
                                                          label: const Text(
                                                            'รอคิว',
                                                          ),
                                                        ),
                                                      ),
                                                    if (AuthService
                                                                .instance
                                                                .currentUser
                                                                ?.isAdmin ==
                                                            true ||
                                                        _myAdminGroups.contains(
                                                          gid,
                                                        ))
                                                      Align(
                                                        alignment: Alignment
                                                            .centerRight,
                                                        child: TextButton.icon(
                                                          onPressed: () =>
                                                              _showCreateSessionSheet(
                                                                g['id']
                                                                    .toString(),
                                                              ),
                                                          icon: const Icon(
                                                            Icons
                                                                .add_circle_outline,
                                                          ),
                                                          label: const Text(
                                                            'เพิ่มรอบนัด',
                                                          ),
                                                        ),
                                                      ),
                                                  ],
                                                );
                                              }
                                              final isAdmin =
                                                  AuthService
                                                          .instance
                                                          .currentUser
                                                          ?.isAdmin ==
                                                      true ||
                                                  _myAdminGroups.contains(gid);
                                              final isGroupOwner =
                                                  g['created_by']?.toString() ==
                                                  AuthService
                                                      .instance
                                                      .currentUser
                                                      ?.id;
                                              final hasJoined =
                                                  _myJoinedGroupIds.contains(
                                                    gid,
                                                  );
                                              final hasPending =
                                                  _myPendingGroupIds.contains(
                                                    gid,
                                                  );
                                              final hasBlocked =
                                                  _myBlockedGroupIds.contains(
                                                    gid,
                                                  );
                                              final requiresOwnerApproval =
                                                  g['requires_owner_approval'] ==
                                                      true &&
                                                  !isGroupOwner;
                                              final joinButton = hasBlocked
                                                  ? TextButton.icon(
                                                      onPressed: null,
                                                      icon: const Icon(
                                                        Icons.hourglass_empty,
                                                      ),
                                                      label: const Text(
                                                        'รอคิว',
                                                      ),
                                                    )
                                                  : hasJoined
                                                  ? TextButton.icon(
                                                      onPressed: null,
                                                      icon: const Icon(
                                                        Icons
                                                            .check_circle_outline,
                                                      ),
                                                      label: const Text(
                                                        'เข้าร่วมก๊วนแล้ว',
                                                      ),
                                                    )
                                                  : hasPending && !isGroupOwner
                                                  ? TextButton.icon(
                                                      onPressed: null,
                                                      icon: const Icon(
                                                        Icons.hourglass_empty,
                                                      ),
                                                      label: const Text(
                                                        'รออนุมัติ',
                                                      ),
                                                    )
                                                  : TextButton.icon(
                                                      onPressed: () =>
                                                          _showSessionPickerSheet(
                                                            gid,
                                                            requiresOwnerApproval:
                                                                requiresOwnerApproval,
                                                          ),
                                                      icon: const Icon(
                                                        Icons.event_available,
                                                      ),
                                                      label: Text(
                                                        isGroupOwner
                                                            ? 'กลับเข้าร่วมก๊วน'
                                                            : requiresOwnerApproval
                                                            ? 'ขอเข้าร่วมก๊วน'
                                                            : 'เข้าร่วมก๊วน',
                                                      ),
                                                    );
                                              return Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  for (final s in items.take(3))
                                                    Padding(
                                                      padding:
                                                          const EdgeInsets.only(
                                                            bottom: 8,
                                                          ),
                                                      child: Column(
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .start,
                                                        children: [
                                                          Row(
                                                            children: [
                                                              const Text(
                                                                'ห้วง: ',
                                                                style: TextStyle(
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w500,
                                                                ),
                                                              ),
                                                              Expanded(
                                                                child: Text(
                                                                  _formatThaiSessionRange(
                                                                    DateTime.parse(
                                                                      s['starts_at']
                                                                          .toString(),
                                                                    ).toLocal(),
                                                                    DateTime.parse(
                                                                      s['ends_at']
                                                                          .toString(),
                                                                    ).toLocal(),
                                                                  ),
                                                                  maxLines: 1,
                                                                  overflow:
                                                                      TextOverflow
                                                                          .ellipsis,
                                                                ),
                                                              ),
                                                            ],
                                                          ),
                                                          Padding(
                                                            padding:
                                                                const EdgeInsets.only(
                                                                  left: 40,
                                                                  top: 2,
                                                                ),
                                                            child: Text(
                                                              _sessionCapacitySummary(
                                                                s,
                                                              ),
                                                              style:
                                                                  const TextStyle(
                                                                    fontSize:
                                                                        12,
                                                                    color: Colors
                                                                        .grey,
                                                                  ),
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  if (isAdmin)
                                                    Row(
                                                      mainAxisAlignment:
                                                          MainAxisAlignment.end,
                                                      children: [
                                                        joinButton,
                                                        TextButton.icon(
                                                          onPressed: () =>
                                                              _showCreateSessionSheet(
                                                                g['id']
                                                                    .toString(),
                                                              ),
                                                          icon: const Icon(
                                                            Icons
                                                                .add_circle_outline,
                                                          ),
                                                          label: const Text(
                                                            'เพิ่มรอบนัด',
                                                          ),
                                                        ),
                                                      ],
                                                    )
                                                  else
                                                    Align(
                                                      alignment:
                                                          Alignment.centerRight,
                                                      child: joinButton,
                                                    ),
                                                ],
                                              );
                                            },
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
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
            ),
          ),
        ],
      ),
      floatingActionButton: _buildFloatingButtons(),
    );
  }

  Widget _buildSportChip(String? id, String label, {String? icon}) {
    final isSelected = _sportId == id;
    final isMyCreated = id != null && _myCreatedSportIds.contains(id);
    final borderColor = isMyCreated
        ? Colors.blue.shade100
        : Colors.grey.shade300;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: _buildSportChipLabel(icon, label),
        selected: isSelected,
        onSelected: (selected) {
          setState(() {
            _sportId = selected ? id : null;
            _reloadingGroups = true;
          });
          _reload();
        },
        selectedColor: Colors.blue.shade100,
        checkmarkColor: Colors.blue,
        shape: StadiumBorder(
          side: BorderSide(color: borderColor, width: isMyCreated ? 2.0 : 1.0),
        ),
      ),
    );
  }

  Widget _buildResponsiveSlidableAction({
    required void Function(BuildContext) onPressed,
    required Color backgroundColor,
    required Color foregroundColor,
    required IconData icon,
    required String label,
  }) {
    return CustomSlidableAction(
      onPressed: onPressed,
      backgroundColor: backgroundColor,
      foregroundColor: foregroundColor,
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: foregroundColor, size: 20),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 1,
              softWrap: false,
              style: TextStyle(
                color: foregroundColor,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showCreateSessionSheet(
    String groupId, {
    Future<void>? refreshFuture,
  }) async {
    final actorUserId = AuthService.instance.currentUser?.id;
    if (actorUserId == null) return;

    final now = DateTime.now();
    // ปัดขึ้นครึ่งชั่วโมงถัดไป
    final roundedStart = _roundUpToNearest(
      now.add(const Duration(minutes: 15)),
    );
    DateTime selectedDate = DateTime(
      roundedStart.year,
      roundedStart.month,
      roundedStart.day,
    );
    TimeOfDay startTime = TimeOfDay(
      hour: roundedStart.hour,
      minute: roundedStart.minute,
    );
    TimeOfDay endTime = TimeOfDay(
      hour: (roundedStart.add(const Duration(hours: 1))).hour,
      minute: roundedStart.minute,
    );
    final noteCtrl = TextEditingController();
    int capacity = 5;
    String? errorText;
    bool submitting = false;
    bool waitingForRefresh = refreshFuture != null;
    var refreshListenerAttached = false;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            if (refreshFuture != null && !refreshListenerAttached) {
              refreshListenerAttached = true;
              refreshFuture.then(
                (_) {
                  if (!ctx.mounted) return;
                  setModalState(() => waitingForRefresh = false);
                },
                onError: (Object error, StackTrace stackTrace) {
                  if (!ctx.mounted) return;
                  setModalState(() => waitingForRefresh = false);
                },
              );
            }

            Future<void> pickStartTime() async {
              final picked = await showTimePicker(
                context: ctx,
                initialTime: startTime,
              );
              if (picked == null) return;

              final previousStart = _dateTimeAt(selectedDate, startTime);
              final previousEnd = _endDateTimeAt(
                selectedDate,
                startTime,
                endTime,
              );
              final proposedStart = _dateTimeAt(selectedDate, picked);
              final earliest = _roundUpToNearest(
                DateTime.now().add(const Duration(minutes: 15)),
              );
              final actualStart = proposedStart.isBefore(earliest)
                  ? earliest
                  : proposedStart;
              DateTime actualEnd;
              if (actualStart != proposedStart) {
                var proposedEnd = _dateTimeAt(selectedDate, endTime);
                if (!proposedEnd.isAfter(proposedStart)) {
                  proposedEnd = proposedEnd.add(const Duration(days: 1));
                }
                final duration = proposedEnd.difference(proposedStart);
                actualEnd = actualStart.add(
                  duration.isNegative || duration == Duration.zero
                      ? const Duration(hours: 1)
                      : duration,
                );
              } else {
                final shift = actualStart.difference(previousStart);
                actualEnd = previousEnd.add(shift);
              }
              if (!actualEnd.isAfter(actualStart)) {
                actualEnd = actualStart.add(const Duration(hours: 1));
              }

              setModalState(() {
                selectedDate = DateTime(
                  actualStart.year,
                  actualStart.month,
                  actualStart.day,
                );
                startTime = TimeOfDay.fromDateTime(actualStart);
                endTime = TimeOfDay.fromDateTime(actualEnd);
              });
            }

            Future<void> pickEndTime() async {
              final picked = await showTimePicker(
                context: ctx,
                initialTime: endTime,
              );
              if (picked != null) {
                final proposedEnd = DateTime(
                  selectedDate.year,
                  selectedDate.month,
                  selectedDate.day,
                  picked.hour,
                  picked.minute,
                );
                final currentStart = DateTime(
                  selectedDate.year,
                  selectedDate.month,
                  selectedDate.day,
                  startTime.hour,
                  startTime.minute,
                );
                if (!proposedEnd.isAfter(currentStart)) {
                  final actualEnd = currentStart.add(const Duration(hours: 1));
                  setModalState(
                    () => endTime = TimeOfDay.fromDateTime(actualEnd),
                  );
                } else {
                  setModalState(() => endTime = picked);
                }
              }
            }

            Future<void> submit() async {
              if (waitingForRefresh) return;
              setModalState(() => errorText = null);
              var startsAt = _dateTimeAt(selectedDate, startTime);
              var endsAt = _endDateTimeAt(selectedDate, startTime, endTime);
              final earliest = _roundUpToNearest(
                DateTime.now().add(const Duration(minutes: 15)),
              );
              if (startsAt.isBefore(earliest)) {
                final delta = earliest.difference(startsAt);
                startsAt = earliest;
                endsAt = endsAt.add(delta);
                setModalState(() {
                  selectedDate = DateTime(
                    startsAt.year,
                    startsAt.month,
                    startsAt.day,
                  );
                  startTime = TimeOfDay.fromDateTime(startsAt);
                  endTime = TimeOfDay.fromDateTime(endsAt);
                });
              }
              if (!endsAt.isAfter(startsAt)) {
                endsAt = startsAt.add(const Duration(hours: 1));
                setModalState(() => endTime = TimeOfDay.fromDateTime(endsAt));
              }
              if (capacity < 1 || capacity > 30) {
                setModalState(
                  () => errorText = 'จำนวนผู้เข้าร่วมต้องอยู่ระหว่าง 1–30 คน',
                );
                return;
              }
              setModalState(() => submitting = true);
              try {
                await _repo.createSession(
                  groupId: groupId,
                  actorUserId: actorUserId,
                  capacity: capacity,
                  startsAt: startsAt,
                  endsAt: endsAt,
                  placeName: null,
                  note: noteCtrl.text.trim().isEmpty
                      ? null
                      : noteCtrl.text.trim(),
                );
                if (!mounted) return;
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('สร้างรอบนัดสำเร็จ')),
                );
                setState(() {}); // trigger refresh of FutureBuilder
              } catch (e) {
                setModalState(() => submitting = false);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('บันทึกไม่สำเร็จ: ${_mapManagementError(e)}'),
                  ),
                );
              }
            }

            final content = Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 12,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 6),
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey[300],
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'สร้างรอบนัด',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ThaiBuddhistDatePickerField(
                      value: selectedDate,
                      label: 'วันที่',
                      onDateSelected: (d) {
                        var nextStart = _dateTimeAt(d, startTime);
                        var nextEnd = _endDateTimeAt(d, startTime, endTime);
                        final earliest = _roundUpToNearest(
                          DateTime.now().add(const Duration(minutes: 15)),
                        );
                        if (nextStart.isBefore(earliest)) {
                          final delta = earliest.difference(nextStart);
                          nextStart = earliest;
                          nextEnd = nextEnd.add(delta);
                        }
                        setModalState(() {
                          selectedDate = DateTime(
                            nextStart.year,
                            nextStart.month,
                            nextStart.day,
                          );
                          startTime = TimeOfDay.fromDateTime(nextStart);
                          endTime = TimeOfDay.fromDateTime(nextEnd);
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: pickStartTime,
                            icon: const Icon(Icons.schedule),
                            label: Text('เริ่ม ${startTime.format(ctx)} น.'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: pickEndTime,
                            icon: const Icon(Icons.timer_off_outlined),
                            label: Text('สิ้นสุด ${endTime.format(ctx)} น.'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('จำนวนผู้เข้าร่วมสูงสุดในรอบนี้'),
                        Text('$capacity คน'),
                      ],
                    ),
                    Slider(
                      value: capacity.toDouble(),
                      min: 1,
                      max: 30,
                      divisions: 29,
                      label: '$capacity',
                      onChanged: (value) =>
                          setModalState(() => capacity = value.toInt()),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: noteCtrl,
                      decoration: const InputDecoration(
                        labelText: 'หมายเหตุ (ไม่บังคับ)',
                      ),
                      maxLines: 2,
                    ),
                    if (errorText != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        errorText!,
                        style: const TextStyle(color: Colors.redAccent),
                      ),
                    ],
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: submitting || waitingForRefresh
                            ? null
                            : submit,
                        icon: submitting || waitingForRefresh
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.save),
                        label: Text(
                          waitingForRefresh
                              ? 'กำลังรีเฟรชรายการก๊วน...'
                              : 'บันทึกรอบนัด',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );

            return SafeArea(
              top: false,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(ctx).size.height * 0.75,
                ),
                child: content,
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showGroupDetailSheet(Map<String, dynamic> group) async {
    final groupId = group['id'].toString();
    final currentUser = AuthService.instance.currentUser;
    final currentUserId = currentUser?.id;
    final groupOwnerId = group['created_by']?.toString();
    final isGroupOwner = groupOwnerId == currentUserId;
    final isSheservedAdmin = currentUser?.isAdmin == true;
    final isGroupAdmin =
        _myAdminGroups.contains(groupId) && !isGroupOwner && !isSheservedAdmin;
    final isAdmin = isGroupOwner || isGroupAdmin || isSheservedAdmin;
    final permissionLabel = isGroupOwner
        ? 'เจ้าของก๊วน'
        : isSheservedAdmin
        ? 'ผู้ดูแล Sheserved'
        : isGroupAdmin
        ? 'ผู้ดูแลก๊วน'
        : currentUserId != null && _myJoinedGroupIds.contains(groupId)
        ? 'สมาชิกก๊วน'
        : currentUserId != null && _myPendingGroupIds.contains(groupId)
        ? 'ผู้ขอเข้าร่วม'
        : 'ผู้เยี่ยมชม';
    final permissionColor = isAdmin
        ? AppColors.primary
        : permissionLabel == 'ผู้ขอเข้าร่วม'
        ? Colors.orange.shade800
        : Colors.grey.shade600;
    final isCurrentUserMember =
        currentUserId != null && _myJoinedGroupIds.contains(groupId);
    final canSelectSession = isCurrentUserMember || isGroupOwner;
    final canViewBlockedUsers = isAdmin;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          return SafeArea(
            top: false,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(ctx).size.height * 0.75,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 20,
                ),
                child: FutureBuilder<List<dynamic>>(
                  future: Future.wait([
                    _repo.listSessions(groupId),
                    _repo.listGroupMembers(groupId),
                    if (isAdmin)
                      _repo.listGroupPendingBookings(
                        groupId,
                        requesterUserId: currentUserId ?? '',
                      )
                    else
                      Future.value(<Map<String, dynamic>>[]),
                    if (!isAdmin && currentUserId != null)
                      _repo.listMyPendingBookingsForGroup(
                        groupId,
                        currentUserId,
                      )
                    else
                      Future.value(<Map<String, dynamic>>[]),
                    if (canViewBlockedUsers)
                      _repo.listBlockedUsers(
                        groupId,
                        requesterUserId: currentUserId ?? '',
                      )
                    else
                      Future.value(<Map<String, dynamic>>[]),
                  ]),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      return Center(
                        child: Text('โหลดข้อมูลไม่สำเร็จ: ${snapshot.error}'),
                      );
                    }
                    final sessions =
                        (snapshot.data?[0] as List?)
                            ?.cast<Map<String, dynamic>>() ??
                        [];
                    final members =
                        (snapshot.data?[1] as List?)
                            ?.cast<Map<String, dynamic>>() ??
                        [];
                    final managerPendingBookings =
                        (snapshot.data?.length ?? 0) > 2
                        ? (snapshot.data![2] as List?)
                                  ?.cast<Map<String, dynamic>>() ??
                              []
                        : <Map<String, dynamic>>[];
                    final ownPendingBookings = (snapshot.data?.length ?? 0) > 3
                        ? (snapshot.data![3] as List?)
                                  ?.cast<Map<String, dynamic>>() ??
                              []
                        : <Map<String, dynamic>>[];
                    final pendingBookings = isAdmin
                        ? managerPendingBookings
                        : ownPendingBookings;
                    final blockedUsers = (snapshot.data?.length ?? 0) > 4
                        ? (snapshot.data![4] as List?)
                                  ?.cast<Map<String, dynamic>>() ??
                              []
                        : <Map<String, dynamic>>[];

                    final pendingBySession =
                        <String, List<Map<String, dynamic>>>{};
                    for (final booking in pendingBookings) {
                      final rawSession = booking['session'];
                      final session =
                          rawSession is List && rawSession.isNotEmpty
                          ? rawSession.first
                          : rawSession is Map
                          ? rawSession
                          : null;
                      final sessionId = session is Map
                          ? session['id']?.toString() ?? ''
                          : '';
                      if (sessionId.isEmpty) continue;
                      pendingBySession
                          .putIfAbsent(sessionId, () => [])
                          .add(booking);
                    }
                    final confirmedMembersBySession =
                        <String, List<Map<String, dynamic>>>{};
                    for (final member in members) {
                      final confirmedSessions =
                          (member['confirmed_sessions'] as List?) ?? [];
                      for (final rawSession in confirmedSessions) {
                        if (rawSession is! Map) continue;
                        final sessionId = rawSession['id']?.toString() ?? '';
                        if (sessionId.isEmpty) continue;
                        confirmedMembersBySession
                            .putIfAbsent(sessionId, () => [])
                            .add(member);
                      }
                    }
                    return Scrollbar(
                      controller: _detailScrollController,
                      thumbVisibility:
                          (members.length +
                              pendingBookings.length +
                              blockedUsers.length) >
                          10,
                      child: SingleChildScrollView(
                        controller: _detailScrollController,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Center(
                              child: Text(
                                'ก๊วน ${group['name']?.toString() ?? ''}',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Align(
                              alignment: Alignment.centerRight,
                              child: Text(
                                'สิทธิ์ของคุณ: $permissionLabel',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: permissionColor,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            if (group['requires_owner_approval'] == true &&
                                !isGroupOwner) ...[
                              const SizedBox(height: 8),
                              Align(
                                alignment: Alignment.centerRight,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.lock,
                                      size: 14,
                                      color: Colors.orange,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      'การจองรอบใหม่ต้องรออนุมัติ',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.orange.shade800,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                            const SizedBox(height: 12),
                            const Text(
                              'รอบนัด',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if ((isAdmin || canSelectSession) &&
                                sessions.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  isAdmin && canSelectSession
                                      ? 'ปัดรอบนัดไปทางซ้ายเพื่อเลือกเพิ่มรอบหรือจัดการ'
                                      : isAdmin
                                      ? 'ปัดรอบนัดไปทางซ้ายเพื่อจัดการ'
                                      : 'ปัดรอบนัดไปทางซ้ายเพื่อเลือกเพิ่มรอบ',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[500],
                                  ),
                                ),
                              ),
                            const SizedBox(height: 8),
                            if (sessions.isEmpty)
                              const Text('ยังไม่มีรอบนัด')
                            else
                              ListView.separated(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: sessions.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 8),
                                itemBuilder: (ctx, i) {
                                  final s = sessions[i];
                                  final sessionId = s['id']?.toString() ?? '';
                                  final sessionLabel = _formatThaiSessionRange(
                                    DateTime.parse(
                                      s['starts_at'].toString(),
                                    ).toLocal(),
                                    DateTime.parse(
                                      s['ends_at'].toString(),
                                    ).toLocal(),
                                  );
                                  final confirmedMembers =
                                      confirmedMembersBySession[sessionId] ??
                                      [];
                                  final pendingForSession =
                                      pendingBySession[sessionId] ?? [];
                                  final sessionChildren = <Widget>[];

                                  if (confirmedMembers.isNotEmpty) {
                                    sessionChildren.add(
                                      Align(
                                        alignment: Alignment.centerLeft,
                                        child: Padding(
                                          padding: const EdgeInsets.fromLTRB(
                                            16,
                                            8,
                                            16,
                                            4,
                                          ),
                                          child: Text(
                                            'ผู้เข้าร่วมรอบนี้ ${confirmedMembers.length} คน',
                                            style: TextStyle(
                                              fontSize: 13,
                                              color: Colors.grey[700],
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      ),
                                    );
                                    sessionChildren.addAll(
                                      confirmedMembers.map<Widget>((member) {
                                        final user =
                                            (member['user'] as Map?) ?? {};
                                        final firstName =
                                            user['first_name']
                                                ?.toString()
                                                .trim() ??
                                            '';
                                        final lastName =
                                            user['last_name']
                                                ?.toString()
                                                .trim() ??
                                            '';
                                        final fullName = '$firstName $lastName'
                                            .trim();
                                        final image =
                                            user['profile_image_url']
                                                ?.toString() ??
                                            '';
                                        final memberUserId =
                                            user['id']?.toString() ??
                                            member['user_id']?.toString() ??
                                            '';
                                        final role =
                                            memberUserId == groupOwnerId
                                            ? 'เจ้าของก๊วน'
                                            : member['role']?.toString() ==
                                                  'admin'
                                            ? 'ผู้ดูแล'
                                            : 'สมาชิก';
                                        final confirmedSessions =
                                            (member['confirmed_sessions']
                                                    as List?)
                                                ?.whereType<Map>() ??
                                            [];
                                        Map<String, dynamic>? sessionBooking;
                                        for (final rawSession
                                            in confirmedSessions) {
                                          if (rawSession['id']?.toString() ==
                                              sessionId) {
                                            sessionBooking =
                                                Map<String, dynamic>.from(
                                                  rawSession,
                                                );
                                            break;
                                          }
                                        }
                                        final bookingId =
                                            sessionBooking?['booking_id']
                                                ?.toString() ??
                                            '';
                                        final tile = ListTile(
                                          dense: true,
                                          contentPadding: const EdgeInsets.only(
                                            left: 16,
                                            right: 16,
                                          ),
                                          leading: CircleAvatar(
                                            radius: 18,
                                            backgroundImage: image.isNotEmpty
                                                ? NetworkImage(image)
                                                : null,
                                            child: image.isEmpty
                                                ? const Icon(Icons.person)
                                                : null,
                                          ),
                                          title: Text(
                                            fullName.isNotEmpty
                                                ? fullName
                                                : 'ไม่ระบุชื่อ',
                                          ),
                                          subtitle: Text('$role · ยืนยันแล้ว'),
                                        );
                                        if (!isAdmin ||
                                            memberUserId == groupOwnerId ||
                                            bookingId.isEmpty) {
                                          return tile;
                                        }
                                        return Slidable(
                                          key: ValueKey(
                                            'session_member_${sessionId}_$memberUserId',
                                          ),
                                          endActionPane: ActionPane(
                                            motion: const ScrollMotion(),
                                            extentRatio: 0.26,
                                            children: [
                                              _buildResponsiveSlidableAction(
                                                onPressed: (_) =>
                                                    _removeParticipantFromSessionDialog(
                                                      ctx,
                                                      bookingId,
                                                      fullName,
                                                      sessionLabel,
                                                      setSheetState,
                                                    ),
                                                backgroundColor: Colors.red,
                                                foregroundColor: Colors.white,
                                                icon: Icons.person_remove,
                                                label: 'ถอดจากรอบนี้',
                                              ),
                                            ],
                                          ),
                                          child: tile,
                                        );
                                      }),
                                    );
                                  }

                                  if (pendingForSession.isNotEmpty) {
                                    sessionChildren.add(
                                      Align(
                                        alignment: Alignment.centerLeft,
                                        child: Padding(
                                          padding: const EdgeInsets.fromLTRB(
                                            16,
                                            12,
                                            16,
                                            4,
                                          ),
                                          child: Text(
                                            isAdmin
                                                ? 'คำขอรออนุมัติ ${pendingForSession.length} คน'
                                                : 'คำขอของฉัน ${pendingForSession.length} รายการ',
                                            style: TextStyle(
                                              fontSize: 13,
                                              color: Colors.orange.shade800,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      ),
                                    );
                                    sessionChildren.addAll(
                                      pendingForSession.map<Widget>(
                                        (booking) => _buildPendingBookingTile(
                                          actionContext: ctx,
                                          booking: booking,
                                          sessionId: sessionId,
                                          groupId: groupId,
                                          canManage: isAdmin,
                                          setSheetState: setSheetState,
                                        ),
                                      ),
                                    );
                                  }

                                  if (sessionChildren.isEmpty) {
                                    sessionChildren.add(
                                      const Padding(
                                        padding: EdgeInsets.fromLTRB(
                                          16,
                                          8,
                                          16,
                                          12,
                                        ),
                                        child: Text(
                                          'ยังไม่มีผู้เข้าร่วมรอบนี้',
                                        ),
                                      ),
                                    );
                                  }

                                  final sessionTile = ExpansionTile(
                                    tilePadding: EdgeInsets.zero,
                                    initiallyExpanded:
                                        pendingForSession.isNotEmpty || i == 0,
                                    title: Text(
                                      'รอบที่ ${i + 1} · $sessionLabel',
                                    ),
                                    subtitle: Text(
                                      _sessionCapacitySummary(
                                        s,
                                        detailed: true,
                                        pendingCountOverride: isAdmin
                                            ? null
                                            : pendingForSession.length,
                                      ),
                                    ),
                                    children: sessionChildren,
                                  );
                                  final sessionActions = <Widget>[];
                                  if (canSelectSession) {
                                    sessionActions.add(
                                      _buildResponsiveSlidableAction(
                                        onPressed: (_) {
                                          Navigator.pop(ctx);
                                          _showSessionPickerSheet(
                                            groupId,
                                            requiresOwnerApproval:
                                                group['requires_owner_approval'] ==
                                                    true &&
                                                group['created_by']
                                                        ?.toString() !=
                                                    currentUserId,
                                          );
                                        },
                                        backgroundColor: Colors.teal,
                                        foregroundColor: Colors.white,
                                        icon: Icons.event_available,
                                        label: 'เลือกเพิ่มรอบ',
                                      ),
                                    );
                                  }
                                  if (isAdmin) {
                                    sessionActions.add(
                                      _buildResponsiveSlidableAction(
                                        onPressed: (_) {
                                          Navigator.pop(ctx);
                                          _showEditSessionSheet(s);
                                        },
                                        backgroundColor: AppColors.primary,
                                        foregroundColor: Colors.white,
                                        icon: Icons.edit,
                                        label: 'แก้ไข',
                                      ),
                                    );
                                    sessionActions.add(
                                      _buildResponsiveSlidableAction(
                                        onPressed: (_) async {
                                          final confirm = await showDialog<bool>(
                                            context: ctx,
                                            builder: (ctx2) => AlertDialog(
                                              title: const Text('ยกเลิกรอบนัด'),
                                              content: const Text(
                                                'ต้องการลบรอบนัดนี้ใช่หรือไม่?',
                                              ),
                                              actions: [
                                                TextButton(
                                                  onPressed: () => Navigator.of(
                                                    ctx2,
                                                  ).pop(false),
                                                  child: const Text('ยกเลิก'),
                                                ),
                                                TextButton(
                                                  onPressed: () => Navigator.of(
                                                    ctx2,
                                                  ).pop(true),
                                                  child: const Text('ยืนยัน'),
                                                ),
                                              ],
                                            ),
                                          );
                                          if (confirm != true) return;
                                          try {
                                            final actorUserId = currentUserId;
                                            if (actorUserId == null) return;
                                            await _repo.cancelSession(
                                              s['id'].toString(),
                                              actorUserId: actorUserId,
                                            );
                                            if (!context.mounted) return;
                                            ScaffoldMessenger.of(
                                              context,
                                            ).showSnackBar(
                                              const SnackBar(
                                                content: Text(
                                                  'ยกเลิกรอบนัดแล้ว',
                                                ),
                                              ),
                                            );
                                            setSheetState(() {});
                                          } catch (e) {
                                            if (!context.mounted) return;
                                            ScaffoldMessenger.of(
                                              context,
                                            ).showSnackBar(
                                              SnackBar(
                                                content: Text(
                                                  'ยกเลิกไม่สำเร็จ: $e',
                                                ),
                                              ),
                                            );
                                          }
                                        },
                                        backgroundColor: Colors.red,
                                        foregroundColor: Colors.white,
                                        icon: Icons.event_busy,
                                        label: 'ยกเลิก',
                                      ),
                                    );
                                  }
                                  if (sessionActions.isEmpty)
                                    return sessionTile;
                                  return Slidable(
                                    key: ValueKey('session_$sessionId'),
                                    endActionPane: ActionPane(
                                      motion: const ScrollMotion(),
                                      extentRatio: sessionActions.length * 0.2,
                                      children: sessionActions,
                                    ),
                                    child: sessionTile,
                                  );
                                },
                              ),
                            const SizedBox(height: 16),
                            ExpansionTile(
                              initiallyExpanded: false,
                              tilePadding: EdgeInsets.zero,
                              title: Text(
                                'สมาชิกก๊วนรวม (ไม่ซ้ำ) ${members.length} คน',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              subtitle: const Text(
                                'นับผู้ใช้ไม่ซ้ำ ไม่ใช่จำนวนที่นั่งของรอบนัด',
                              ),
                              children: [
                                if (isAdmin)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(
                                      'ปัดรายชื่อไปทางซ้ายเพื่อจัดการ',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey[500],
                                      ),
                                    ),
                                  ),
                                const SizedBox(height: 8),
                                if (members.isEmpty)
                                  const Text('ยังไม่มีสมาชิก')
                                else
                                  ListView.separated(
                                    shrinkWrap: true,
                                    physics:
                                        const NeverScrollableScrollPhysics(),
                                    itemCount: members.length,
                                    separatorBuilder: (_, __) =>
                                        const SizedBox(height: 4),
                                    itemBuilder: (ctx, i) {
                                      final m = members[i];
                                      final user = (m['user'] as Map?) ?? {};
                                      final firstName =
                                          user['first_name']
                                              ?.toString()
                                              .trim() ??
                                          '';
                                      final lastName =
                                          user['last_name']
                                              ?.toString()
                                              .trim() ??
                                          '';
                                      final fullName = '$firstName $lastName'
                                          .trim();
                                      final image =
                                          user['profile_image_url']
                                              ?.toString() ??
                                          '';
                                      final active = m['is_active'] == true
                                          ? 'เข้าร่วมแล้ว'
                                          : 'หยุดพัก';
                                      final memberUserId =
                                          user['id']?.toString() ??
                                          m['user_id']?.toString() ??
                                          '';
                                      final role = memberUserId == groupOwnerId
                                          ? 'เจ้าของก๊วน'
                                          : (m['role']?.toString() == 'admin')
                                          ? 'ผู้ดูแล'
                                          : 'สมาชิก';
                                      final isSelf =
                                          memberUserId == currentUserId;
                                      final mentionTargetName =
                                          isSelf || firstName.isEmpty
                                          ? null
                                          : lastName.isEmpty
                                          ? firstName
                                          : '$firstName ${String.fromCharCode(lastName.runes.first)}.';
                                      final isMemberAdmin =
                                          m['role']?.toString() == 'admin';
                                      // Build swipe actions
                                      final actions = <Widget>[];
                                      // Chat button: available for self, or for admin swiping others
                                      if (isSelf || (isAdmin && !isSelf)) {
                                        actions.add(
                                          _buildResponsiveSlidableAction(
                                            onPressed: (_) {
                                              showGroupChatPopup(
                                                context,
                                                groupId: groupId,
                                                groupName:
                                                    group['name']?.toString() ??
                                                    'ก๊วน',
                                                memberCount: members.length,
                                                mentionTargetName:
                                                    mentionTargetName,
                                              );
                                            },
                                            backgroundColor: AppColors.primary,
                                            foregroundColor: Colors.white,
                                            icon: Icons.chat_bubble_outline,
                                            label: 'แชท',
                                          ),
                                        );
                                      }
                                      if (isSelf &&
                                          isGroupOwner &&
                                          group['owner_auto_join'] != false &&
                                          memberUserId.isNotEmpty) {
                                        actions.add(
                                          _buildResponsiveSlidableAction(
                                            onPressed: (_) =>
                                                _withdrawOwnerParticipation(
                                                  sheetContext: ctx,
                                                  groupId: groupId,
                                                  userId: memberUserId,
                                                ),
                                            backgroundColor: Colors.red,
                                            foregroundColor: Colors.white,
                                            icon: Icons.person_remove_alt_1,
                                            label: 'ถอน',
                                          ),
                                        );
                                      }
                                      // Block + Remove: admin only, not self, not other admin
                                      if (isAdmin &&
                                          !isSelf &&
                                          !isMemberAdmin) {
                                        actions.add(
                                          _buildResponsiveSlidableAction(
                                            onPressed: (_) => _blockUserDialog(
                                              ctx,
                                              groupId,
                                              memberUserId,
                                              fullName,
                                              setSheetState,
                                            ),
                                            backgroundColor: Colors.grey,
                                            foregroundColor: Colors.white,
                                            icon: Icons.block,
                                            label: 'บล็อก',
                                          ),
                                        );
                                        actions.add(
                                          _buildResponsiveSlidableAction(
                                            onPressed: (_) =>
                                                _removeMemberDialog(
                                                  ctx,
                                                  groupId,
                                                  memberUserId,
                                                  fullName,
                                                  setSheetState,
                                                ),
                                            backgroundColor: Colors.red,
                                            foregroundColor: Colors.white,
                                            icon: Icons.person_remove,
                                            label: 'ถอดทั้งก๊วน',
                                          ),
                                        );
                                      }

                                      final tile = ListTile(
                                        contentPadding: EdgeInsets.zero,
                                        leading: CircleAvatar(
                                          backgroundImage: image.isNotEmpty
                                              ? NetworkImage(image)
                                              : null,
                                          child: image.isEmpty
                                              ? const Icon(Icons.person)
                                              : null,
                                        ),
                                        title: Text(
                                          fullName.isNotEmpty
                                              ? fullName
                                              : 'ไม่ระบุชื่อ',
                                        ),
                                        subtitle: Text('$role · $active'),
                                      );

                                      if (actions.isEmpty) return tile;

                                      return Slidable(
                                        key: ValueKey('member_$memberUserId'),
                                        endActionPane: ActionPane(
                                          motion: const ScrollMotion(),
                                          extentRatio: actions.length * 0.2,
                                          children: actions,
                                        ),
                                        child: tile,
                                      );
                                    },
                                  ),
                              ],
                            ),
                            if (canViewBlockedUsers &&
                                blockedUsers.isNotEmpty) ...[
                              const SizedBox(height: 16),
                              const Divider(),
                              Row(
                                children: [
                                  const Text(
                                    'ถูกบล็อก',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '${blockedUsers.length} คน',
                                    style: TextStyle(color: Colors.grey[600]),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              ListView.separated(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: blockedUsers.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 4),
                                itemBuilder: (ctx, i) {
                                  final blocked = blockedUsers[i];
                                  final blockedUser =
                                      (blocked['blocked_user'] as Map?) ?? {};
                                  final name =
                                      '${blockedUser['first_name'] ?? ''} ${blockedUser['last_name'] ?? ''}'
                                          .trim();
                                  final image =
                                      blockedUser['profile_image_url']
                                          ?.toString() ??
                                      '';
                                  final reason = blocked['reason']?.toString();
                                  final blockedUserId =
                                      blocked['blocked_user_id']?.toString() ??
                                      '';
                                  final tile = ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    leading: CircleAvatar(
                                      backgroundImage: image.isNotEmpty
                                          ? NetworkImage(image)
                                          : null,
                                      child: image.isEmpty
                                          ? const Icon(Icons.person_off)
                                          : null,
                                    ),
                                    title: Text(
                                      name.isNotEmpty ? name : 'ไม่ระบุชื่อ',
                                    ),
                                    subtitle: Text(
                                      reason != null && reason.isNotEmpty
                                          ? 'ถูกบล็อก · เหตุผล: $reason'
                                          : 'ถูกบล็อก',
                                    ),
                                  );
                                  return Slidable(
                                    key: ValueKey('blocked_$blockedUserId'),
                                    endActionPane: ActionPane(
                                      motion: const ScrollMotion(),
                                      extentRatio: 0.24,
                                      children: [
                                        _buildResponsiveSlidableAction(
                                          onPressed: (_) async {
                                            try {
                                              final actorUserId = currentUserId;
                                              if (actorUserId == null) return;
                                              await _repo.unblockUser(
                                                groupId: groupId,
                                                blockedUserId: blockedUserId,
                                                actorUserId: actorUserId,
                                              );
                                              if (!context.mounted) return;
                                              ScaffoldMessenger.of(
                                                context,
                                              ).showSnackBar(
                                                SnackBar(
                                                  content: Text(
                                                    'ปลดบล็อก "$name" แล้ว',
                                                  ),
                                                ),
                                              );
                                              setSheetState(() {});
                                              await _reload();
                                            } catch (e) {
                                              if (!context.mounted) return;
                                              ScaffoldMessenger.of(
                                                context,
                                              ).showSnackBar(
                                                SnackBar(
                                                  content: Text(
                                                    'ปลดบล็อกไม่สำเร็จ: $e',
                                                  ),
                                                ),
                                              );
                                            }
                                          },
                                          backgroundColor: Colors.green,
                                          foregroundColor: Colors.white,
                                          icon: Icons.lock_open,
                                          label: 'ปลด',
                                        ),
                                      ],
                                    ),
                                    child: tile,
                                  );
                                },
                              ),
                            ],
                            const SizedBox(height: 16),
                            // ── Action buttons ──
                            _buildGroupActionButtons(
                              ctx: ctx,
                              setSheetState: setSheetState,
                              groupId: groupId,
                              isAdmin: isAdmin,
                              isMember: _myJoinedGroupIds.contains(groupId),
                              group: group,
                            ),
                            const SizedBox(height: 20),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _withdrawOwnerParticipation({
    required BuildContext sheetContext,
    required String groupId,
    required String userId,
  }) async {
    final confirm = await showDialog<bool>(
      context: sheetContext,
      builder: (dialogContext) => AlertDialog(
        title: const Text('ถอนตัวจากสมาชิก'),
        content: const Text(
          'ต้องการหยุดการเข้าร่วมทุกรอบอัตโนมัติหรือไม่?\n'
          'ระบบจะยกเลิก booking ของ owner ในรอบอนาคต และคุณยังคงเป็นผู้ดูแลก๊วน',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('ยกเลิก'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('ถอน', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      await _repo.updateGroup(
        groupId: groupId,
        userId: userId,
        ownerAutoJoin: false,
        cancelOwnerBookings: true,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('ถอนจากสมาชิกแล้ว และยังคงเป็นผู้ดูแลก๊วน'),
        ),
      );
      Navigator.pop(sheetContext);
      await _reload();
    } catch (e) {
      if (!sheetContext.mounted) return;
      ScaffoldMessenger.of(sheetContext).showSnackBar(
        SnackBar(content: Text('ถอนไม่สำเร็จ: ${_mapManagementError(e)}')),
      );
    }
  }

  Widget _buildGroupActionButtons({
    required BuildContext ctx,
    required StateSetter setSheetState,
    required String groupId,
    required bool isAdmin,
    required bool isMember,
    required Map<String, dynamic> group,
  }) {
    final userId = AuthService.instance.currentUser?.id;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        // Phase 4: Edit group (admin only)
        if (isAdmin)
          OutlinedButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              _showEditGroupSheet(group);
            },
            icon: const Icon(Icons.edit, size: 18),
            label: const Text('แก้ไขก๊วน'),
          ),
        // Phase 4: Leave group (non-admin members only)
        if (isMember && !isAdmin && userId != null)
          OutlinedButton.icon(
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: ctx,
                builder: (c) => AlertDialog(
                  title: const Text('ออกจากก๊วน'),
                  content: const Text(
                    'คุณต้องการออกจากก๊วนนี้ใช่หรือไม่? การจองทั้งหมดของคุณจะถูกยกเลิก',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(c, false),
                      child: const Text('ยกเลิก'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(c, true),
                      child: const Text(
                        'ยืนยัน',
                        style: TextStyle(color: Colors.red),
                      ),
                    ),
                  ],
                ),
              );
              if (confirm != true) return;
              try {
                await _repo.leaveGroup(groupId: groupId, userId: userId);
                if (!context.mounted) return;
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('ออกจากก๊วนแล้ว')));
                Navigator.pop(ctx);
                _init();
              } catch (e) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('ออกจากก๊วนไม่สำเร็จ: $e')),
                );
              }
            },
            icon: const Icon(Icons.exit_to_app, size: 18, color: Colors.red),
            label: const Text(
              'ออกจากก๊วน',
              style: TextStyle(color: Colors.red),
            ),
            style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
          ),
      ],
    );
  }

  // ── Phase 4: Edit group sheet ──
  Future<void> _showEditGroupSheet(Map<String, dynamic> group) async {
    final userId = AuthService.instance.currentUser?.id;
    if (userId == null) return;

    final nameCtrl = TextEditingController(
      text: group['name']?.toString() ?? '',
    );
    final descCtrl = TextEditingController(
      text: group['description']?.toString() ?? '',
    );
    String genderPref = group['gender_preference']?.toString() ?? 'any';
    final originalOwnerAutoJoin = group['owner_auto_join'] != false;
    final isGroupOwner = group['created_by']?.toString() == userId;
    bool requiresApproval = group['requires_owner_approval'] == true;
    bool ownerAutoJoin = originalOwnerAutoJoin;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * 0.8,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.grey[300],
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'แก้ไขก๊วน',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: nameCtrl,
                        decoration: const InputDecoration(
                          labelText: 'ชื่อก๊วน',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: descCtrl,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          labelText: 'คำอธิบาย',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: genderPref,
                        decoration: const InputDecoration(
                          labelText: 'เพศที่ต้องการชวน',
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'any', child: Text('ทุกเพศ')),
                          DropdownMenuItem(value: 'male', child: Text('ชาย')),
                          DropdownMenuItem(
                            value: 'female',
                            child: Text('หญิง'),
                          ),
                        ],
                        onChanged: (v) {
                          if (v != null) {
                            setSheetState(() => genderPref = v);
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('ก๊วนส่วนตัว (ต้องรออนุมัติ)'),
                        value: requiresApproval,
                        onChanged: (v) =>
                            setSheetState(() => requiresApproval = v),
                      ),
                      if (isGroupOwner) ...[
                        const SizedBox(height: 8),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('เข้าร่วมทุกรอบอัตโนมัติ'),
                          subtitle: const Text(
                            'เปิดแล้วจะจองรอบนัดที่กำลังจะถึงให้เจ้าของก๊วนโดยอัตโนมัติ',
                          ),
                          value: ownerAutoJoin,
                          onChanged: (v) =>
                              setSheetState(() => ownerAutoJoin = v),
                        ),
                      ],
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () async {
                            final name = nameCtrl.text.trim();
                            if (name.isEmpty) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                const SnackBar(
                                  content: Text('กรุณากรอกชื่อก๊วน'),
                                ),
                              );
                              return;
                            }
                            var cancelOwnerBookings = false;
                            if (isGroupOwner &&
                                originalOwnerAutoJoin &&
                                !ownerAutoJoin) {
                              final choice = await showDialog<bool?>(
                                context: ctx,
                                builder: (dialogContext) => AlertDialog(
                                  title: const Text('ปิดการเข้าร่วมอัตโนมัติ'),
                                  content: const Text(
                                    'ต้องการจัดการ booking ของ owner ในรอบอนาคตอย่างไร?',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(dialogContext),
                                      child: const Text('ยกเลิก'),
                                    ),
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(dialogContext, false),
                                      child: const Text('คงการจองเดิม'),
                                    ),
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(dialogContext, true),
                                      child: const Text('ยกเลิกการจองอนาคต'),
                                    ),
                                  ],
                                ),
                              );
                              if (!ctx.mounted || choice == null) return;
                              cancelOwnerBookings = choice;
                            }
                            try {
                              await _repo.updateGroup(
                                groupId: group['id'].toString(),
                                userId: userId,
                                name: name,
                                description: descCtrl.text.trim().isEmpty
                                    ? null
                                    : descCtrl.text.trim(),
                                ownerAutoJoin: ownerAutoJoin,
                                cancelOwnerBookings: cancelOwnerBookings,
                                genderPreference: genderPref,
                                requiresOwnerApproval: requiresApproval,
                              );
                              if (!ctx.mounted) return;
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                const SnackBar(content: Text('อัปเดตก๊วนแล้ว')),
                              );
                              Navigator.pop(ctx);
                              _init();
                            } catch (e) {
                              if (!ctx.mounted) return;
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'อัปเดตไม่สำเร็จ: ${_mapManagementError(e)}',
                                  ),
                                ),
                              );
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('บันทึก'),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Phase 4: Edit session sheet ──
  Future<void> _showEditSessionSheet(Map<String, dynamic> session) async {
    final actorUserId = AuthService.instance.currentUser?.id;
    if (actorUserId == null) return;

    final startsAt = DateTime.parse(session['starts_at'].toString()).toLocal();
    final endsAt = DateTime.parse(session['ends_at'].toString()).toLocal();
    DateTime editStart = startsAt;
    DateTime editEnd = endsAt;
    int editCapacity = (session['capacity'] as num?)?.toInt() ?? 5;
    final placeNameCtrl = TextEditingController(
      text: session['place_name']?.toString() ?? '',
    );
    final noteCtrl = TextEditingController(
      text: session['note']?.toString() ?? '',
    );

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey[300],
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'แก้ไขรอบนัด',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 16),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('เวลาเริ่ม'),
                      subtitle: Text(_formatThaiBuddhistDateTime(editStart)),
                      trailing: const Icon(Icons.calendar_today),
                      onTap: () async {
                        final date = await showDatePicker(
                          context: ctx,
                          initialDate: editStart,
                          firstDate: DateTime.now().subtract(
                            const Duration(days: 1),
                          ),
                          lastDate: DateTime.now().add(
                            const Duration(days: 365),
                          ),
                        );
                        if (date != null) {
                          final time = TimeOfDay.fromDateTime(editStart);
                          setSheetState(
                            () => editStart = DateTime(
                              date.year,
                              date.month,
                              date.day,
                              time.hour,
                              time.minute,
                            ),
                          );
                        }
                      },
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('เวลาสิ้นสุด'),
                      subtitle: Text(_formatThaiBuddhistDateTime(editEnd)),
                      trailing: const Icon(Icons.calendar_today),
                      onTap: () async {
                        final date = await showDatePicker(
                          context: ctx,
                          initialDate: editEnd,
                          firstDate: DateTime.now().subtract(
                            const Duration(days: 1),
                          ),
                          lastDate: DateTime.now().add(
                            const Duration(days: 365),
                          ),
                        );
                        if (date != null) {
                          final time = TimeOfDay.fromDateTime(editEnd);
                          setSheetState(
                            () => editEnd = DateTime(
                              date.year,
                              date.month,
                              date.day,
                              time.hour,
                              time.minute,
                            ),
                          );
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('จำนวนผู้เข้าร่วมสูงสุดในรอบนี้'),
                        Text('$editCapacity คน'),
                      ],
                    ),
                    Slider(
                      value: editCapacity.toDouble(),
                      min: 1,
                      max: 30,
                      divisions: 29,
                      label: '$editCapacity',
                      onChanged: (value) =>
                          setSheetState(() => editCapacity = value.toInt()),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: placeNameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'สถานที่',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: noteCtrl,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'หมายเหตุ',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () async {
                          if (editEnd.isBefore(editStart) ||
                              editEnd.isAtSameMomentAs(editStart)) {
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              const SnackBar(
                                content: Text('เวลาสิ้นสุดต้องมาหลังเวลาเริ่ม'),
                              ),
                            );
                            return;
                          }
                          try {
                            await _repo.updateSession(
                              sessionId: session['id'].toString(),
                              actorUserId: actorUserId,
                              capacity: editCapacity,
                              startsAt: editStart,
                              endsAt: editEnd,
                              placeName: placeNameCtrl.text.trim().isEmpty
                                  ? null
                                  : placeNameCtrl.text.trim(),
                              note: noteCtrl.text.trim().isEmpty
                                  ? null
                                  : noteCtrl.text.trim(),
                            );
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('อัปเดตรอบนัดแล้ว')),
                            );
                            Navigator.pop(ctx);
                            _init();
                          } catch (e) {
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'อัปเดตไม่สำเร็จ: ${_mapManagementError(e)}',
                                ),
                              ),
                            );
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('บันทึก'),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPendingBookingTile({
    required BuildContext actionContext,
    required Map<String, dynamic> booking,
    required String sessionId,
    required String groupId,
    required bool canManage,
    required StateSetter setSheetState,
  }) {
    final userData = (booking['user'] as Map?) ?? {};
    final firstName = userData['first_name']?.toString().trim() ?? '';
    final lastName = userData['last_name']?.toString().trim() ?? '';
    final fullName = '$firstName $lastName'.trim();
    final image = userData['profile_image_url']?.toString() ?? '';
    final userId = userData['id']?.toString() ?? '';
    final bookingId = booking['id']?.toString() ?? '';
    final requestedAt = DateTime.tryParse(
      booking['created_at']?.toString() ?? '',
    );
    final requestTimeLabel = requestedAt == null
        ? 'เวลาที่ขอเข้าร่วมไม่พร้อมใช้งาน'
        : 'ขอเข้าร่วมเมื่อ ${_formatThaiBuddhistDateTime(requestedAt.toLocal())}';
    final tile = ListTile(
      dense: true,
      contentPadding: const EdgeInsets.only(left: 16, right: 16),
      leading: CircleAvatar(
        radius: 18,
        backgroundImage: image.isNotEmpty ? NetworkImage(image) : null,
        child: image.isEmpty ? const Icon(Icons.person) : null,
      ),
      title: Text(fullName.isNotEmpty ? fullName : 'ไม่ระบุชื่อ'),
      subtitle: Text('รออนุมัติ\n$requestTimeLabel'),
    );
    if (!canManage) return tile;

    return Slidable(
      key: ValueKey('pending_${sessionId}_$bookingId'),
      endActionPane: ActionPane(
        motion: const ScrollMotion(),
        extentRatio: 0.7,
        children: [
          _buildResponsiveSlidableAction(
            onPressed: (_) => _approveSingleBooking(
              actionContext,
              bookingId,
              fullName,
              setSheetState,
            ),
            backgroundColor: Colors.green,
            foregroundColor: Colors.white,
            icon: Icons.check_circle,
            label: 'อนุมัติ',
          ),
          _buildResponsiveSlidableAction(
            onPressed: (_) => _showRejectAllDialog(
              actionContext,
              [booking],
              fullName,
              setSheetState,
            ),
            backgroundColor: Colors.red,
            foregroundColor: Colors.white,
            icon: Icons.cancel,
            label: 'ปฏิเสธ',
          ),
          _buildResponsiveSlidableAction(
            onPressed: (_) => _blockUserDialog(
              actionContext,
              groupId,
              userId,
              fullName,
              setSheetState,
            ),
            backgroundColor: Colors.grey,
            foregroundColor: Colors.white,
            icon: Icons.block,
            label: 'บล็อก',
          ),
        ],
      ),
      child: tile,
    );
  }

  // ── Phase 8: Approve single booking (direct, no dialog needed) ──
  Future<void> _approveSingleBooking(
    BuildContext sheetCtx,
    String bookingId,
    String userName,
    StateSetter setSheetState,
  ) async {
    final user = AuthService.instance.currentUser;
    if (user == null) return;
    try {
      await _repo.approveBooking(bookingId: bookingId, actorUserId: user.id);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('อนุมัติ "$userName" แล้ว')));
      setSheetState(() {});
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_mapApprovalError(e))));
    }
  }

  // ── Phase 8: Reject all pending bookings for a user ──
  Future<void> _showRejectAllDialog(
    BuildContext sheetCtx,
    List<Map<String, dynamic>> bookings,
    String userName,
    StateSetter setSheetState,
  ) async {
    final currentUser = AuthService.instance.currentUser;
    if (currentUser == null) return;
    final reasonCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: sheetCtx,
      builder: (dctx) => AlertDialog(
        title: const Text('ปฏิเสธคำขอ'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'ต้องการปฏิเสธคำขอทั้งหมดของ "$userName" (${bookings.length} รอบ) ใช่หรือไม่?',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reasonCtrl,
              onTapOutside: (_) =>
                  FocusManager.instance.primaryFocus?.unfocus(),
              decoration: const InputDecoration(
                hintText: 'เหตุผล (ไม่บังคับ)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dctx, false),
            child: const Text('ยกเลิก'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dctx, true),
            child: const Text('ปฏิเสธ', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final reason = reasonCtrl.text.trim().isEmpty
          ? null
          : reasonCtrl.text.trim();
      for (final b in bookings) {
        await _repo.rejectBooking(
          bookingId: b['id'].toString(),
          actorUserId: currentUser.id,
          reason: reason,
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('ปฏิเสธคำขอของ "$userName" แล้ว')));
      setSheetState(() {});
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('ปฏิเสธไม่สำเร็จ: $e')));
    }
  }

  Future<void> _removeParticipantFromSessionDialog(
    BuildContext sheetCtx,
    String bookingId,
    String memberName,
    String sessionLabel,
    StateSetter setSheetState,
  ) async {
    final confirmed = await showDialog<bool>(
      context: sheetCtx,
      builder: (dctx) => AlertDialog(
        title: const Text('ถอดออกจากรอบนี้'),
        content: Text(
          'ต้องการถอด "$memberName" จากรอบ $sessionLabel ใช่หรือไม่?\n'
          'สมาชิกยังอยู่ในก๊วน และการเข้าร่วมรอบอื่นจะไม่เปลี่ยนแปลง',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dctx, false),
            child: const Text('ยกเลิก'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dctx, true),
            child: const Text('ถอด', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final actorUserId = AuthService.instance.currentUser?.id;
    if (actorUserId == null) return;
    try {
      await _repo.removeParticipantFromSession(
        bookingId: bookingId,
        actorUserId: actorUserId,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('ถอด "$memberName" ออกจากรอบนี้แล้ว')),
      );
      setSheetState(() {});
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('ถอดจากรอบไม่สำเร็จ: ${_mapManagementError(e)}'),
        ),
      );
    }
  }

  // ── Phase 8: Remove member from group (admin action) ──
  Future<void> _removeMemberDialog(
    BuildContext sheetCtx,
    String groupId,
    String memberUserId,
    String memberName,
    StateSetter setSheetState,
  ) async {
    final confirmed = await showDialog<bool>(
      context: sheetCtx,
      builder: (dctx) => AlertDialog(
        title: const Text('ถอดออกจากก๊วนทั้งหมด'),
        content: Text(
          'ต้องการถอด "$memberName" ออกจากก๊วนใช่หรือไม่?\n'
          'ระบบจะยกเลิกการเข้าร่วมทุก upcoming session ของสมาชิกนี้',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dctx, false),
            child: const Text('ยกเลิก'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dctx, true),
            child: const Text(
              'ถอดทั้งก๊วน',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final actorUserId = AuthService.instance.currentUser?.id;
    if (actorUserId == null) return;
    try {
      await _repo.leaveGroup(
        groupId: groupId,
        userId: memberUserId,
        actorUserId: actorUserId,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('ถอด "$memberName" ออกจากก๊วนแล้ว')),
      );
      setSheetState(() {});
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('ถอดไม่สำเร็จ: $e')));
    }
  }

  // ── Phase 4: Block user dialog ──
  Future<void> _blockUserDialog(
    BuildContext sheetCtx,
    String groupId,
    String blockedUserId,
    String blockedUserName,
    StateSetter setSheetState,
  ) async {
    final userId = AuthService.instance.currentUser?.id;
    if (userId == null) return;
    final reasonCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: sheetCtx,
      builder: (dctx) => AlertDialog(
        title: const Text('บล็อกผู้ใช้'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'คุณต้องการบล็อก "$blockedUserName" ใช่หรือไม่? ผู้ใช้ที่ถูกบล็อกจะไม่สามารถจองรอบนัดในก๊วนของคุณได้อีก',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reasonCtrl,
              onTapOutside: (_) =>
                  FocusManager.instance.primaryFocus?.unfocus(),
              decoration: const InputDecoration(
                hintText: 'เหตุผล (ไม่บังคับ)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dctx, false),
            child: const Text('ยกเลิก'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dctx, true),
            child: const Text('บล็อก', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _repo.blockUser(
        groupId: groupId,
        blockedUserId: blockedUserId,
        blockedBy: userId,
        reason: reasonCtrl.text.trim().isEmpty ? null : reasonCtrl.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('บล็อก "$blockedUserName" แล้ว')));
      setSheetState(() {});
      await _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('บล็อกไม่สำเร็จ: $e')));
    }
  }

  // ── Phase 4: Blocklist management sheet ──
  Future<void> showBlocklistSheet(
    String groupId, {
    required String? groupOwnerId,
  }) async {
    final user = AuthService.instance.currentUser;
    if (user == null || (user.id != groupOwnerId && !user.isAdmin)) return;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          Future<List<Map<String, dynamic>>> loadBlocked() =>
              _repo.listBlockedUsers(groupId, requesterUserId: user.id);

          return SafeArea(
            top: false,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(ctx).size.height * 0.7,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 20,
                ),
                child: FutureBuilder<List<Map<String, dynamic>>>(
                  future: loadBlocked(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      return Center(
                        child: Text('โหลดไม่สำเร็จ: ${snapshot.error}'),
                      );
                    }
                    final blocked = snapshot.data ?? [];
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Center(
                          child: Container(
                            width: 40,
                            height: 4,
                            decoration: BoxDecoration(
                              color: Colors.grey[300],
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            IconButton(
                              tooltip: 'ย้อนกลับไปยังรายละเอียดก๊วน',
                              onPressed: () => Navigator.pop(ctx),
                              icon: const Icon(Icons.arrow_back),
                            ),
                            const Expanded(
                              child: Text(
                                'จัดการบล็อกลิสต์',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'ผู้ใช้ที่ถูกบล็อกจะไม่สามารถจองรอบนัดในก๊วนของคุณได้',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[600],
                          ),
                        ),
                        const SizedBox(height: 16),
                        if (blocked.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 24),
                            child: Center(
                              child: Text('ยังไม่มีผู้ใช้ที่ถูกบล็อก'),
                            ),
                          )
                        else
                          Expanded(
                            child: ListView.separated(
                              shrinkWrap: true,
                              itemCount: blocked.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 4),
                              itemBuilder: (c, i) {
                                final b = blocked[i];
                                final blockedUser =
                                    (b['blocked_user'] as Map?) ?? {};
                                final name =
                                    '${blockedUser['first_name'] ?? ''} ${blockedUser['last_name'] ?? ''}'
                                        .trim();
                                final image =
                                    blockedUser['profile_image_url']
                                        ?.toString() ??
                                    '';
                                final reason = b['reason']?.toString();
                                final blockedAt = b['created_at']?.toString();
                                final blockedUserId =
                                    b['blocked_user_id']?.toString() ?? '';

                                return ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: CircleAvatar(
                                    backgroundImage: image.isNotEmpty
                                        ? NetworkImage(image)
                                        : null,
                                    child: image.isEmpty
                                        ? const Icon(Icons.person)
                                        : null,
                                  ),
                                  title: Text(
                                    name.isNotEmpty ? name : 'ไม่ระบุชื่อ',
                                  ),
                                  subtitle: Text(
                                    [
                                      if (reason != null && reason.isNotEmpty)
                                        'เหตุผล: $reason',
                                      if (blockedAt != null)
                                        'บล็อกเมื่อ: ${_formatThaiBuddhistDateTime(DateTime.parse(blockedAt).toLocal())}',
                                    ].join('\n'),
                                  ),
                                  trailing: TextButton.icon(
                                    onPressed: () async {
                                      try {
                                        await _repo.unblockUser(
                                          groupId: groupId,
                                          blockedUserId: blockedUserId,
                                          actorUserId: user.id,
                                        );
                                        if (!mounted) return;
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              'ปลดบล็อก "$name" แล้ว',
                                            ),
                                          ),
                                        );
                                        setSheetState(() {});
                                      } catch (e) {
                                        if (!mounted) return;
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              'ปลดบล็อกไม่สำเร็จ: $e',
                                            ),
                                          ),
                                        );
                                      }
                                    },
                                    icon: const Icon(
                                      Icons.lock_open,
                                      size: 16,
                                      color: Colors.green,
                                    ),
                                    label: const Text(
                                      'ปลดบล็อก',
                                      style: TextStyle(
                                        color: Colors.green,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  static const _thaiMonths = [
    'ม.ค.',
    'ก.พ.',
    'มี.ค.',
    'เม.ย.',
    'พ.ค.',
    'มิ.ย.',
    'ก.ค.',
    'ส.ค.',
    'ก.ย.',
    'ต.ค.',
    'พ.ย.',
    'ธ.ค.',
  ];

  String _formatThaiTime(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}.${d.minute.toString().padLeft(2, '0')}';

  String _formatThaiBuddhistDateTime(DateTime d) {
    final beShort = ((d.year + 543) % 100).toString();
    return '${d.day} ${_thaiMonths[d.month - 1]} $beShort ${_formatThaiTime(d)} น.';
  }

  String _formatThaiSessionRange(DateTime start, DateTime end) {
    final beShort = ((start.year + 543) % 100).toString();
    if (start.year == end.year &&
        start.month == end.month &&
        start.day == end.day) {
      return '${start.day} ${_thaiMonths[start.month - 1]} $beShort ${_formatThaiTime(start)}-${_formatThaiTime(end)} น.';
    }
    return '${_formatThaiBuddhistDateTime(start)} - ${_formatThaiBuddhistDateTime(end)}';
  }

  Widget _buildSkeletonCard() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.7),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Colors.white.withOpacity(0.5),
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Shimmer.fromColors(
          baseColor: Colors.grey.shade300,
          highlightColor: Colors.grey.shade100,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(width: 120, height: 14, color: Colors.white.withOpacity(0.5)),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                height: 18,
                color: Colors.white.withOpacity(0.5),
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                height: 12,
                color: Colors.white.withOpacity(0.5),
              ),
              const SizedBox(height: 6),
              Container(width: 180, height: 12, color: Colors.white.withOpacity(0.5)),
            ],
          ),
        ),
      ),
    );
  }

  TextStyle _emojiTextStyle(BuildContext context, {double fontSize = 16}) {
    final platform = Theme.of(context).platform;
    final emojiFontFamily =
        platform == TargetPlatform.iOS || platform == TargetPlatform.macOS
        ? 'Apple Color Emoji'
        : platform == TargetPlatform.android
        ? 'Noto Color Emoji'
        : platform == TargetPlatform.windows
        ? 'Segoe UI Emoji'
        : null;
    return TextStyle(
      fontSize: fontSize,
      fontFamily: emojiFontFamily,
      fontFamilyFallback: const [
        'Apple Color Emoji',
        'Noto Color Emoji',
        'Segoe UI Emoji',
      ],
    );
  }

  Widget _buildSportChipLabel(String? icon, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null && icon.isNotEmpty) ...[
          Text(icon, style: _emojiTextStyle(context)),
          const SizedBox(width: 4),
        ],
        Text(label),
      ],
    );
  }

  Widget _buildAddSportFab() {
    final user = AuthService.instance.currentUser;
    final isAdmin = user?.role == 'admin';
    if (!isAdmin) return const SizedBox.shrink();
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.only(left: 4, right: 8),
      child: InkWell(
        onTap: () {
          Navigator.pushNamed(context, '/community/sport-club/sport/manage');
        },
        customBorder: const CircleBorder(),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.teal,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.teal, width: 1.5),
          ),
          child: const Icon(Icons.add, color: Colors.white, size: 24),
        ),
      ),
    );
  }

  Widget _buildFloatingButtons() {
    return Padding(
      padding: const EdgeInsets.only(right: 4, bottom: 4),
      child: FloatingActionButton.extended(
        heroTag: 'createGroupFab',
        onPressed: () async {
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
            setState(() => _sportId = newSportId);
          }
          final refreshFuture = _reload();
          if (groupId.isNotEmpty) {
            await _showCreateSessionSheet(
              groupId,
              refreshFuture: refreshFuture,
            );
            if (!mounted) return;
            try {
              await refreshFuture;
            } catch (_) {}
            await _reload();
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
        },
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

  double _distanceKm(double lat1, double lng1, double lat2, double lng2) {
    return const Distance().as(
      LengthUnit.Kilometer,
      LatLng(lat1, lng1),
      LatLng(lat2, lng2),
    );
  }

  List<Map<String, dynamic>> _applyLocationFilter(
    List<Map<String, dynamic>> groups,
  ) {
    if (!_locationEnabled ||
        _userLat == null ||
        _userLng == null ||
        _radiusKm == null) {
      return groups;
    }
    return groups.where((g) {
      final lat = g['lat'];
      final lng = g['lng'];
      if (lat == null || lng == null) return false;
      return _distanceKm(
            _userLat!,
            _userLng!,
            (lat as num).toDouble(),
            (lng as num).toDouble(),
          ) <=
          _radiusKm!;
    }).toList();
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

  Widget _buildMapView() {
    final markers = _groups
        .where((g) => g['lat'] != null && g['lng'] != null)
        .where(_canViewFullGroup)
        .map((g) {
          final lat = (g['lat'] as num).toDouble();
          final lng = (g['lng'] as num).toDouble();
          return Marker(
            point: LatLng(lat, lng),
            width: 44,
            height: 44,
            alignment: Alignment.topCenter,
            child: GestureDetector(
              onTap: () => _showMapMarkerSheet(g),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.teal,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow: const [
                    BoxShadow(color: Colors.black26, blurRadius: 4),
                  ],
                ),
                alignment: Alignment.center,
                child: Text(
                  g['sport_icon']?.toString() ?? '🏅',
                  style: _emojiTextStyle(context, fontSize: 18),
                ),
              ),
            ),
          );
        })
        .toList();

    final center = _userLat != null && _userLng != null
        ? LatLng(_userLat!, _userLng!)
        : const LatLng(13.7563, 100.5018); // กรุงเทพฯ (ค่าเริ่มต้น)

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
      child: FlutterMap(
        options: MapOptions(
          initialCenter: center,
          initialZoom: _userLat != null ? 12 : 6,
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.example.treeLawZoo',
          ),
          if (_userLat != null && _userLng != null && _radiusKm != null)
            CircleLayer(
              circles: [
                CircleMarker(
                  point: LatLng(_userLat!, _userLng!),
                  radius: _radiusKm! * 1000,
                  useRadiusInMeter: true,
                  color: Colors.teal.withValues(alpha: 0.08),
                  borderColor: Colors.teal.withValues(alpha: 0.35),
                  borderStrokeWidth: 1,
                ),
              ],
            ),
          MarkerLayer(markers: markers),
          if (markers.isEmpty)
            const Center(
              child: Text(
                'ไม่มีก๊วนในพื้นที่นี้',
                style: TextStyle(color: Colors.grey),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _showMapMarkerSheet(Map<String, dynamic> group) async {
    await showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if ((group['sport_icon']?.toString() ?? '').isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Text(
                        group['sport_icon'].toString(),
                        style: _emojiTextStyle(context, fontSize: 18),
                      ),
                    ),
                  Expanded(
                    child: Text(
                      group['name']?.toString() ?? '',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              if ((group['province']?.toString() ?? '').isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'พื้นที่: ${group['province']}${(group['district']?.toString() ?? '').isNotEmpty ? ' · ${group['district']}' : ''}',
                  ),
                ),
              if (group['member_count'] != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('สมาชิกก๊วน: ${group['member_count']} คน'),
                ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('ปิด'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _showGroupDetailSheet(group);
                    },
                    icon: const Icon(Icons.info_outline),
                    label: const Text('ดูรายละเอียด'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSearchDialog() {
    final qController = TextEditingController(text: _q);
    final provinceController = TextEditingController(text: _province ?? '');
    final districtController = TextEditingController(text: _district ?? '');
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Center(child: Text('ค้นหาก๊วน')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('ค้นหา'),
                TextField(
                  controller: qController,
                  onChanged: (_) => setDialogState(() {}),
                  onTapOutside: (_) =>
                      FocusManager.instance.primaryFocus?.unfocus(),
                  decoration: InputDecoration(
                    hintText: 'ค้นหาก๊วน / สถานที่',
                    suffixIcon: qController.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'ล้างค่า',
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              qController.clear();
                              setDialogState(() {});
                            },
                          ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text('จังหวัด'),
                TextField(
                  controller: provinceController,
                  onTapOutside: (_) =>
                      FocusManager.instance.primaryFocus?.unfocus(),
                  decoration: const InputDecoration(hintText: 'จังหวัด'),
                ),
                const SizedBox(height: 16),
                const Text('อำเภอ'),
                TextField(
                  controller: districtController,
                  onTapOutside: (_) =>
                      FocusManager.instance.primaryFocus?.unfocus(),
                  decoration: const InputDecoration(hintText: 'อำเภอ'),
                ),
                const SizedBox(height: 16),
                CheckboxListTile(
                  title: const Text('เฉพาะก๊วนที่เข้าร่วมได้ทันที'),
                  subtitle: const Text('กรองเอาก๊วนส่วนตัวที่ต้องรออนุมัติออก'),
                  value: _filterOpenOnly,
                  onChanged: (v) =>
                      setDialogState(() => _filterOpenOnly = v ?? false),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  title: const Text('ใช้ตำแหน่งปัจจุบัน'),
                  subtitle: const Text('กรองก๊วนตามระยะทางจากคุณ'),
                  value: _locationEnabled,
                  onChanged: (v) async {
                    if (v) {
                      final ok = await _requestLocation();
                      if (!ok) {
                        if (context.mounted) {
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
                    }
                    setDialogState(() {
                      _locationEnabled = v;
                      if (v) _radiusKm ??= 10;
                    });
                  },
                ),
                if (_locationEnabled) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      children: [
                        const Text('รัศมี'),
                        Expanded(
                          child: Slider(
                            value: (_radiusKm ?? 10).clamp(1, 50).toDouble(),
                            min: 1,
                            max: 50,
                            divisions: 49,
                            label: '${(_radiusKm ?? 10).round()} กม.',
                            onChanged: (v) =>
                                setDialogState(() => _radiusKm = v),
                          ),
                        ),
                        Text('${(_radiusKm ?? 10).round()} กม.'),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('ยกเลิก'),
            ),
            TextButton(
              onPressed: () {
                _q = qController.text;
                _province = provinceController.text.isEmpty
                    ? null
                    : provinceController.text;
                _district = districtController.text.isEmpty
                    ? null
                    : districtController.text;
                Navigator.pop(context);
                _reload();
              },
              child: const Text('ค้นหา'),
            ),
          ],
        ),
      ),
    );
  }
}
