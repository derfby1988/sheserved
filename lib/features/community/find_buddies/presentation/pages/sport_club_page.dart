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
import '../../../../../../shared/widgets/tlz_bottom_navigation_bar.dart';
import '../../../../../../shared/widgets/thai_buddhist_date_picker.dart';
import '../../../find_buddies/presentation/widgets/group_chat_popup.dart';

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
  static const _pageSize = 20;
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
    if (_isLoadingMore || !_hasMore) return;
    if (_listScrollController.position.pixels >=
        _listScrollController.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore) return;
    setState(() => _isLoadingMore = true);
    try {
      final userId = AuthService.instance.currentUser?.id;
      final newOffset = _currentOffset + _pageSize;
      var groups = await _repo.listGroups(
        sportId: _sportId,
        q: _q,
        openOnly: _filterOpenOnly,
        province: _province,
        district: _district,
        limit: _pageSize,
        offset: newOffset,
      );
      groups = _applyLocationFilter(groups);
      final adminIds = userId != null
          ? await _repo.listMyAdminGroupIds(userId)
          : <String>{};
      final joinedGroupIds = userId != null
          ? await _repo.listMyJoinedGroupIds(userId)
          : <String>{};

      final allGroupIds = groups
          .map((g) => g['id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toList();
      final groupIdsWithSessions = await _repo
          .filterGroupIdsWithUpcomingSessions(allGroupIds);
      final filteredGroups = groups.where((g) {
        final gid = g['id']?.toString() ?? '';
        if (adminIds.contains(gid) ||
            joinedGroupIds.contains(gid) ||
            _myBlockedGroupIds.contains(gid)) {
          return true;
        }
        return groupIdsWithSessions.contains(gid);
      }).toList();

      if (!mounted) return;
      setState(() {
        _groups.addAll(filteredGroups);
        _currentOffset = newOffset;
        _hasMore = groups.length >= _pageSize;
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
      final groups = _applyLocationFilter(
        await _repo.listGroups(
          openOnly: _filterOpenOnly,
          limit: _pageSize,
          offset: 0,
        ),
      );
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

      // Filter out groups with no upcoming sessions for non-admin, non-joined users
      final allGroupIds = groups
          .map((g) => g['id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toList();
      final groupIdsWithSessions = await _repo
          .filterGroupIdsWithUpcomingSessions(allGroupIds);
      final filteredGroups = groups.where((g) {
        final gid = g['id']?.toString() ?? '';
        if (adminIds.contains(gid) ||
            joinedGroupIds.contains(gid) ||
            blockedGroupIds.contains(gid)) {
          return true;
        }
        return groupIdsWithSessions.contains(gid);
      }).toList();

      if (!mounted) return;
      setState(() {
        _sports = sports;
        _groups = filteredGroups;
        _loading = false;
        _currentOffset = 0;
        _hasMore = groups.length >= _pageSize;
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
    if (args is Map && args['intent'] == 'join_group') {
      final groupId = args['groupId']?.toString();
      if (groupId != null && groupId.isNotEmpty) {
        _intentHandled = true;
        final group = _groups.cast<Map<String, dynamic>?>().firstWhere(
          (g) => g?['id']?.toString() == groupId,
          orElse: () => null,
        );
        if (group != null) {
          final requiresOwnerApproval =
              group['requires_owner_approval'] == true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _showSessionPickerSheet(
                groupId,
                requiresOwnerApproval: requiresOwnerApproval,
              );
            }
          });
        }
      }
    }
  }

  Future<void> _reload() async {
    setState(() => _reloadingGroups = true);
    final userId = AuthService.instance.currentUser?.id;
    try {
      var groups = await _repo.listGroups(
        sportId: _sportId,
        q: _q,
        openOnly: _filterOpenOnly,
        province: _province,
        district: _district,
        limit: _pageSize,
        offset: 0,
      );
      groups = _applyLocationFilter(groups);
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

      // Filter out groups with no upcoming sessions for non-admin, non-joined users
      final allGroupIds = groups
          .map((g) => g['id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toList();
      final groupIdsWithSessions = await _repo
          .filterGroupIdsWithUpcomingSessions(allGroupIds);
      final filteredGroups = groups.where((g) {
        final gid = g['id']?.toString() ?? '';
        if (adminIds.contains(gid) ||
            joinedGroupIds.contains(gid) ||
            blockedGroupIds.contains(gid)) {
          return true;
        }
        return groupIdsWithSessions.contains(gid);
      }).toList();

      if (!mounted) return;
      setState(() {
        _groups = filteredGroups;
        _currentOffset = 0;
        _hasMore = groups.length >= _pageSize;
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
                      return ListTile(
                        title: Text(_formatThaiSessionRange(startsAt, endsAt)),
                        subtitle: (note != null && note.isNotEmpty)
                            ? Text(
                                note,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              )
                            : null,
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () {
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
      ).showSnackBar(SnackBar(content: Text('จองไม่สำเร็จ: $e')));
    }
  }

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
            padding: const EdgeInsets.fromLTRB(16, 50, 16, 20),
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(32),
                bottomRight: Radius.circular(32),
              ),
            ),
            child: Row(
              children: [
                // Menu button
                Builder(
                  builder: (context) => IconButton(
                    icon: const Icon(Icons.menu, color: Colors.white),
                    onPressed: () => Scaffold.of(context).openDrawer(),
                  ),
                ),
                const SizedBox(width: 8),
                // Title
                Expanded(
                  child: Text(
                    'หาเพื่อนออกกำลังกาย',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                // Action buttons
                IconButton(
                  icon: const Icon(Icons.search, color: Colors.white),
                  onPressed: () => _showSearchDialog(),
                ),
                IconButton(
                  icon: const Icon(Icons.person, color: Colors.white),
                  tooltip: 'ก๊วนของฉัน',
                  onPressed: () => Navigator.pushNamed(
                    context,
                    '/community/sport-club/my-groups',
                  ),
                ),
                IconButton(
                  icon: Icon(
                    _showMapView ? Icons.list : Icons.map,
                    color: Colors.white,
                  ),
                  onPressed: () => setState(() => _showMapView = !_showMapView),
                ),
              ],
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
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _showMapView
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
                          if (_reloadingGroups)
                            for (var i = 0; i < 3; i++) _buildSkeletonCard(),
                          for (final g in _groups)
                            InkWell(
                              onTap: () => _showGroupDetailSheet(g),
                              child: Card(
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      if ((g['venue_photo_url']?.toString() ??
                                              g['cover_image_url']
                                                  ?.toString() ??
                                              '')
                                          .isNotEmpty)
                                        ClipRRect(
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
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
                                      if ((g['venue_photo_url']?.toString() ??
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
                                                    g['sport_icon']?.toString(),
                                                    g['sport_name'].toString(),
                                                  ),
                                                if ((g['sport_name']
                                                            ?.toString() ??
                                                        '')
                                                    .isNotEmpty)
                                                  const SizedBox(width: 6),
                                                Expanded(
                                                  child: Text(
                                                    g['name']?.toString() ?? '',
                                                    style: const TextStyle(
                                                      fontSize: 16,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          if (g['gender_preference'] != null &&
                                              g['gender_preference']
                                                      .toString() !=
                                                  'any')
                                            Chip(
                                              label: Text(
                                                g['gender_preference']
                                                            .toString() ==
                                                        'male'
                                                    ? 'ช.'
                                                    : 'ญ.',
                                              ),
                                              backgroundColor:
                                                  g['gender_preference']
                                                          .toString() ==
                                                      'male'
                                                  ? Colors.blue.shade50
                                                  : Colors.pink.shade50,
                                              visualDensity:
                                                  VisualDensity.compact,
                                            )
                                          else
                                            Chip(
                                              label: const Text('เสรี'),
                                              backgroundColor:
                                                  Colors.green.shade50,
                                              visualDensity:
                                                  VisualDensity.compact,
                                            ),
                                        ],
                                      ),
                                      if ((g['description']?.toString() ?? '')
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
                                                        g['district'].toString()
                                                  : ''),
                                        ),
                                      if (g['member_count'] != null)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            top: 4,
                                          ),
                                          child: Text(
                                            'ว่าง: ${((g['capacity'] as num?)?.toInt() ?? 0) - ((g['member_count'] as num?)?.toInt() ?? 0)} คน',
                                          ),
                                        ),
                                      const SizedBox(height: 8),
                                      FutureBuilder<List<Map<String, dynamic>>>(
                                        future: _repo.listUpcomingSessions(
                                          g['id'].toString(),
                                        ),
                                        builder: (context, snapshot) {
                                          final items =
                                              snapshot.data ?? const [];
                                          if (snapshot.connectionState !=
                                              ConnectionState.done) {
                                            return const Padding(
                                              padding: EdgeInsets.all(8.0),
                                              child: LinearProgressIndicator(
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
                                          final gid = g['id']?.toString() ?? '';
                                          if (items.isEmpty) {
                                            return Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                const Text(
                                                  'รอบล่าสุดสิ้นสุดแล้ว',
                                                ),
                                                if (_myBlockedGroupIds.contains(
                                                  gid,
                                                ))
                                                  Align(
                                                    alignment:
                                                        Alignment.centerRight,
                                                    child: TextButton.icon(
                                                      onPressed: null,
                                                      icon: const Icon(
                                                        Icons.hourglass_empty,
                                                      ),
                                                      label: const Text(
                                                        'รอคิว',
                                                      ),
                                                    ),
                                                  ),
                                                if (_myAdminGroups.contains(
                                                  gid,
                                                ))
                                                  Align(
                                                    alignment:
                                                        Alignment.centerRight,
                                                    child: TextButton.icon(
                                                      onPressed: () =>
                                                          _showCreateSessionSheet(
                                                            g['id'].toString(),
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
                                          final isAdmin = _myAdminGroups
                                              .contains(gid);
                                          final hasJoined = _myJoinedGroupIds
                                              .contains(gid);
                                          final hasPending = _myPendingGroupIds
                                              .contains(gid);
                                          final hasBlocked = _myBlockedGroupIds
                                              .contains(gid);
                                          final requiresOwnerApproval =
                                              g['requires_owner_approval'] ==
                                              true;
                                          final joinButton = hasBlocked
                                              ? TextButton.icon(
                                                  onPressed: null,
                                                  icon: const Icon(
                                                    Icons.hourglass_empty,
                                                  ),
                                                  label: const Text('รอคิว'),
                                                )
                                              : hasJoined
                                              ? TextButton.icon(
                                                  onPressed: null,
                                                  icon: const Icon(
                                                    Icons.check_circle_outline,
                                                  ),
                                                  label: const Text(
                                                    'เข้าร่วมก๊วนแล้ว',
                                                  ),
                                                )
                                              : hasPending
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
                                                    requiresOwnerApproval
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
                                                  child: Row(
                                                    children: [
                                                      const Text(
                                                        'ห้วง: ',
                                                        style: TextStyle(
                                                          fontWeight:
                                                              FontWeight.w500,
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
                                                          overflow: TextOverflow
                                                              .ellipsis,
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
                                                            g['id'].toString(),
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

  Future<void> _showCreateSessionSheet(String groupId) async {
    final now = DateTime.now();
    // ปัดขึ้นครึ่งชั่วโมงถัดไป
    final roundedStart = DateTime(
      now.year,
      now.month,
      now.day,
      now.minute < 30 ? now.hour : now.hour + 1,
      now.minute < 30 ? 30 : 0,
    );
    DateTime selectedDate = DateTime(now.year, now.month, now.day);
    TimeOfDay startTime = TimeOfDay(
      hour: roundedStart.hour,
      minute: roundedStart.minute,
    );
    TimeOfDay endTime = TimeOfDay(
      hour: (roundedStart.add(const Duration(hours: 1))).hour,
      minute: roundedStart.minute,
    );
    final noteCtrl = TextEditingController();
    String? errorText;
    bool submitting = false;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            Future<void> pickStartTime() async {
              final picked = await showTimePicker(
                context: ctx,
                initialTime: startTime,
              );
              if (picked != null) {
                setModalState(() => startTime = picked);
              }
            }

            Future<void> pickEndTime() async {
              final picked = await showTimePicker(
                context: ctx,
                initialTime: endTime,
              );
              if (picked != null) {
                setModalState(() => endTime = picked);
              }
            }

            Future<void> submit() async {
              setModalState(() => errorText = null);
              final startsAt = DateTime(
                selectedDate.year,
                selectedDate.month,
                selectedDate.day,
                startTime.hour,
                startTime.minute,
              );
              final endsAt = DateTime(
                selectedDate.year,
                selectedDate.month,
                selectedDate.day,
                endTime.hour,
                endTime.minute,
              );
              if (startsAt.isBefore(now.add(const Duration(minutes: 15)))) {
                setModalState(
                  () => errorText =
                      'เวลาเริ่มต้องไม่น้อยกว่าอีก 15 นาทีจากตอนนี้',
                );
                return;
              }
              if (!endsAt.isAfter(startsAt)) {
                setModalState(
                  () => errorText = 'เวลาสิ้นสุดต้องมากกว่าเวลาเริ่ม',
                );
                return;
              }
              setModalState(() => submitting = true);
              try {
                await _repo.createSession(
                  groupId: groupId,
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
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text('บันทึกไม่สำเร็จ: $e')));
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
                      onDateSelected: (d) =>
                          setModalState(() => selectedDate = d),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: pickStartTime,
                            icon: const Icon(Icons.schedule),
                            label: Text('เริ่ม ${startTime.format(ctx)}'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: pickEndTime,
                            icon: const Icon(Icons.timer_off_outlined),
                            label: Text('สิ้นสุด ${endTime.format(ctx)}'),
                          ),
                        ),
                      ],
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
                        onPressed: submitting ? null : submit,
                        icon: submitting
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.save),
                        label: const Text('บันทึกรอบนัด'),
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
    final isAdmin = _myAdminGroups.contains(groupId);
    final currentUser = AuthService.instance.currentUser;
    final currentUserId = currentUser?.id;
    final isGroupOwner = group['created_by']?.toString() == currentUserId;
    final canViewBlockedUsers = isGroupOwner || currentUser?.isAdmin == true;
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
                      _repo.listGroupPendingBookings(groupId)
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
                    final pendingBookings = (snapshot.data?.length ?? 0) > 2
                        ? (snapshot.data![2] as List?)
                                  ?.cast<Map<String, dynamic>>() ??
                              []
                        : <Map<String, dynamic>>[];
                    final blockedUsers = (snapshot.data?.length ?? 0) > 3
                        ? (snapshot.data![3] as List?)
                                  ?.cast<Map<String, dynamic>>() ??
                              []
                        : <Map<String, dynamic>>[];

                    // Group pending bookings by user_id
                    final Map<String, List<Map<String, dynamic>>>
                    pendingByUser = {};
                    for (final b in pendingBookings) {
                      final uid = b['user'] is Map
                          ? (b['user'] as Map)['id']?.toString()
                          : null;
                      if (uid == null || uid.isEmpty) continue;
                      pendingByUser.putIfAbsent(uid, () => []).add(b);
                    }
                    return Scrollbar(
                      controller: _detailScrollController,
                      thumbVisibility:
                          (members.length +
                              pendingByUser.length +
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
                            if (group['requires_owner_approval'] == true) ...[
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
                                      'ต้องรออนุมัติ',
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
                            if (isAdmin && sessions.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  'ปัดรอบนัดไปทางซ้ายเพื่อจัดการ',
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
                                  final sessionTile = ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    title: Text(
                                      'ห้วง: ${_formatThaiSessionRange(DateTime.parse(s['starts_at'].toString()).toLocal(), DateTime.parse(s['ends_at'].toString()).toLocal())}',
                                    ),
                                  );
                                  if (!isAdmin) return sessionTile;
                                  return Slidable(
                                    key: ValueKey('session_${s['id']}'),
                                    endActionPane: ActionPane(
                                      motion: const ScrollMotion(),
                                      extentRatio: 0.62,
                                      children: [
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
                                        _buildResponsiveSlidableAction(
                                          onPressed: (_) async {
                                            final confirm = await showDialog<bool>(
                                              context: ctx,
                                              builder: (ctx2) => AlertDialog(
                                                title: const Text(
                                                  'ยกเลิกรอบนัด',
                                                ),
                                                content: const Text(
                                                  'ต้องการลบรอบนัดนี้ใช่หรือไม่?',
                                                ),
                                                actions: [
                                                  TextButton(
                                                    onPressed: () =>
                                                        Navigator.of(
                                                          ctx2,
                                                        ).pop(false),
                                                    child: const Text('ยกเลิก'),
                                                  ),
                                                  TextButton(
                                                    onPressed: () =>
                                                        Navigator.of(
                                                          ctx2,
                                                        ).pop(true),
                                                    child: const Text('ยืนยัน'),
                                                  ),
                                                ],
                                              ),
                                            );
                                            if (confirm != true) return;
                                            try {
                                              await _repo.cancelSession(
                                                s['id'].toString(),
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
                                      ],
                                    ),
                                    child: sessionTile,
                                  );
                                },
                              ),
                            const SizedBox(height: 16),
                            // ── Pending approval section (admin only) ──
                            if (isAdmin && pendingByUser.isNotEmpty) ...[
                              const Text(
                                'คำขอรออนุมัติ',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${pendingByUser.length} คน',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey[600],
                                ),
                              ),
                              const SizedBox(height: 8),
                              ListView.separated(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: pendingByUser.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 4),
                                itemBuilder: (ctx, i) {
                                  final entry = pendingByUser.entries.elementAt(
                                    i,
                                  );
                                  final uid = entry.key;
                                  final bookings = entry.value;
                                  final firstBooking = bookings.first;
                                  final userData =
                                      (firstBooking['user'] as Map?) ?? {};
                                  final fullName =
                                      '${userData['first_name'] ?? ''} ${userData['last_name'] ?? ''}'
                                          .trim();
                                  final image =
                                      userData['profile_image_url']
                                          ?.toString() ??
                                      '';
                                  final bookingCount = bookings.length;
                                  return Slidable(
                                    key: ValueKey('pending_$uid'),
                                    endActionPane: ActionPane(
                                      motion: const ScrollMotion(),
                                      extentRatio: 0.7,
                                      children: [
                                        if (bookingCount == 1)
                                          _buildResponsiveSlidableAction(
                                            onPressed: (_) =>
                                                _approveSingleBooking(
                                                  ctx,
                                                  bookings.first['id']
                                                      .toString(),
                                                  fullName,
                                                  setSheetState,
                                                ),
                                            backgroundColor: Colors.green,
                                            foregroundColor: Colors.white,
                                            icon: Icons.check_circle,
                                            label: 'อนุมัติ',
                                          )
                                        else
                                          _buildResponsiveSlidableAction(
                                            onPressed: (_) =>
                                                _showApproveRejectDialog(
                                                  ctx,
                                                  bookings,
                                                  fullName,
                                                  uid,
                                                  setSheetState,
                                                ),
                                            backgroundColor: Colors.green,
                                            foregroundColor: Colors.white,
                                            icon: Icons.check_circle,
                                            label: 'อนุมัติ',
                                          ),
                                        _buildResponsiveSlidableAction(
                                          onPressed: (_) =>
                                              _showRejectAllDialog(
                                                ctx,
                                                bookings,
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
                                            ctx,
                                            groupId,
                                            uid,
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
                                    child: ListTile(
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
                                      subtitle: Text(
                                        bookingCount == 1
                                            ? 'รออนุมัติ'
                                            : 'รออนุมัติ $bookingCount รอบ',
                                      ),
                                    ),
                                  );
                                },
                              ),
                              const SizedBox(height: 16),
                            ],
                            Row(
                              children: [
                                const Text(
                                  'เข้าร่วมแล้ว',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '${members.length} คน',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'ว่าง: ${((group['capacity'] as num?)?.toInt() ?? 0) - members.length} คน',
                                  style: const TextStyle(fontSize: 16),
                                ),
                                const Spacer(),
                              ],
                            ),
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
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: members.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 4),
                                itemBuilder: (ctx, i) {
                                  final m = members[i];
                                  final user = (m['user'] as Map?) ?? {};
                                  final firstName =
                                      user['first_name']?.toString().trim() ??
                                      '';
                                  final lastName =
                                      user['last_name']?.toString().trim() ??
                                      '';
                                  final fullName = '$firstName $lastName'
                                      .trim();
                                  final image =
                                      user['profile_image_url']?.toString() ??
                                      '';
                                  final role =
                                      (m['role']?.toString() == 'admin')
                                      ? 'ผู้ดูแล'
                                      : 'สมาชิก';
                                  final active = m['is_active'] == true
                                      ? 'เข้าร่วมแล้ว'
                                      : 'หยุดพัก';
                                  final memberUserId =
                                      user['id']?.toString() ??
                                      m['user_id']?.toString() ??
                                      '';
                                  final isSelf = memberUserId == currentUserId;
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
                                  // Block + Remove: admin only, not self, not other admin
                                  if (isAdmin && !isSelf && !isMemberAdmin) {
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
                                        onPressed: (_) => _removeMemberDialog(
                                          ctx,
                                          groupId,
                                          memberUserId,
                                          fullName,
                                          setSheetState,
                                        ),
                                        backgroundColor: Colors.red,
                                        foregroundColor: Colors.white,
                                        icon: Icons.person_remove,
                                        label: 'ถอด',
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
                                              final capacityStatus = await _repo
                                                  .getUnblockCapacityStatus(
                                                    groupId: groupId,
                                                    requesterUserId:
                                                        currentUserId ?? '',
                                                  );
                                              if (!context.mounted) return;
                                              if (capacityStatus == null) {
                                                ScaffoldMessenger.of(
                                                  context,
                                                ).showSnackBar(
                                                  const SnackBar(
                                                    content: Text(
                                                      'ไม่สามารถตรวจสอบสิทธิ์หรือจำนวนสมาชิกของก๊วนได้',
                                                    ),
                                                  ),
                                                );
                                                return;
                                              }
                                              final capacity =
                                                  capacityStatus['capacity'] ??
                                                  0;
                                              final memberCount =
                                                  capacityStatus['member_count'] ??
                                                  0;
                                              if (memberCount + 1 > capacity) {
                                                await showDialog<void>(
                                                  context: context,
                                                  builder: (dialogContext) =>
                                                      AlertDialog(
                                                        title: const Text(
                                                          'ไม่สามารถปลดบล็อกได้',
                                                        ),
                                                        content: Text(
                                                          'ก๊วนมีสมาชิก $memberCount คน จากจำนวนที่เปิดรับ $capacity คน หากปลดบล็อกจะทำให้จำนวนสมาชิกเกินที่กำหนด กรุณาให้เจ้าของก๊วนเข้าไปแก้ไขก๊วนและเพิ่มจำนวนที่เปิดรับให้เรียบร้อยก่อน แล้วจึงลองปลดบล็อกอีกครั้ง',
                                                        ),
                                                        actions: [
                                                          TextButton(
                                                            onPressed: () =>
                                                                Navigator.pop(
                                                                  dialogContext,
                                                                ),
                                                            child: const Text(
                                                              'ตกลง',
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                );
                                                return;
                                              }
                                              await _repo.unblockUser(
                                                groupId: groupId,
                                                blockedUserId: blockedUserId,
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
                              isMember:
                                  _myJoinedGroupIds.contains(groupId) ||
                                  isAdmin,
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
    final capacityCtrl = TextEditingController(
      text: (group['capacity'] as num?)?.toInt().toString() ?? '5',
    );
    String genderPref = group['gender_preference']?.toString() ?? 'any';
    bool requiresApproval = group['requires_owner_approval'] == true;
    String? capacityError;

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
                      TextField(
                        controller: capacityCtrl,
                        keyboardType: TextInputType.number,
                        onChanged: (_) {
                          if (capacityError != null) {
                            setSheetState(() => capacityError = null);
                          }
                        },
                        decoration: InputDecoration(
                          labelText: 'จำนวนสมาชิกเป้าหมาย',
                          border: const OutlineInputBorder(),
                          errorText: capacityError,
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
                            final capacity = int.tryParse(
                              capacityCtrl.text.trim(),
                            );
                            if (capacity == null ||
                                capacity < 2 ||
                                capacity > 30) {
                              setSheetState(
                                () => capacityError =
                                    'จำนวนสมาชิกต้องอยู่ระหว่าง 2–30 คน',
                              );
                              return;
                            }
                            final currentMemberCount =
                                (group['member_count'] as num?)?.toInt() ?? 0;
                            if (capacity < currentMemberCount) {
                              setSheetState(
                                () => capacityError =
                                    'จำนวนสมาชิกเป้าหมายต้องไม่น้อยกว่าสมาชิกปัจจุบัน ($currentMemberCount คน)',
                              );
                              return;
                            }
                            try {
                              await _repo.updateGroup(
                                groupId: group['id'].toString(),
                                userId: userId,
                                name: name,
                                description: descCtrl.text.trim().isEmpty
                                    ? null
                                    : descCtrl.text.trim(),
                                capacity: capacity,
                                genderPreference: genderPref,
                                requiresOwnerApproval: requiresApproval,
                              );
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('อัปเดตก๊วนแล้ว')),
                              );
                              Navigator.pop(ctx);
                              _init();
                            } catch (e) {
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('อัปเดตไม่สำเร็จ: $e')),
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
    final startsAt = DateTime.parse(session['starts_at'].toString()).toLocal();
    final endsAt = DateTime.parse(session['ends_at'].toString()).toLocal();
    DateTime editStart = startsAt;
    DateTime editEnd = endsAt;
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
                              SnackBar(content: Text('อัปเดตไม่สำเร็จ: $e')),
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
      await _repo.approveBooking(bookingId: bookingId, ownerId: user.id);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('อนุมัติ "$userName" แล้ว')));
      setSheetState(() {});
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('อนุมัติไม่สำเร็จ: $e')));
    }
  }

  // ── Phase 8: Approve/reject dialog with session picker ──
  Future<void> _showApproveRejectDialog(
    BuildContext sheetCtx,
    List<Map<String, dynamic>> bookings,
    String userName,
    String userId,
    StateSetter setSheetState,
  ) async {
    final currentUser = AuthService.instance.currentUser;
    if (currentUser == null) return;
    await showDialog(
      context: sheetCtx,
      builder: (dctx) => AlertDialog(
        title: Text('จัดการคำขอของ "$userName"'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 300),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: bookings.map((b) {
                final session = b['session'] is Map
                    ? b['session'] as Map
                    : <String, dynamic>{};
                final startsAt = session['starts_at'] != null
                    ? DateTime.parse(session['starts_at'].toString()).toLocal()
                    : null;
                final endsAt = session['ends_at'] != null
                    ? DateTime.parse(session['ends_at'].toString()).toLocal()
                    : null;
                final label = startsAt != null && endsAt != null
                    ? _formatThaiSessionRange(startsAt, endsAt)
                    : 'รอบนัด (ไม่มีข้อมูลเวลา)';
                return ListTile(
                  title: Text(label),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'อนุมัติ',
                        icon: const Icon(
                          Icons.check_circle,
                          color: Colors.green,
                        ),
                        onPressed: () async {
                          Navigator.pop(dctx);
                          try {
                            await _repo.approveBooking(
                              bookingId: b['id'].toString(),
                              ownerId: currentUser.id,
                            );
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('อนุมัติสำเร็จ')),
                            );
                            setSheetState(() {});
                          } catch (e) {
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('อนุมัติไม่สำเร็จ: $e')),
                            );
                          }
                        },
                      ),
                      IconButton(
                        tooltip: 'ปฏิเสธ',
                        icon: const Icon(Icons.cancel, color: Colors.red),
                        onPressed: () async {
                          Navigator.pop(dctx);
                          try {
                            await _repo.rejectBooking(
                              bookingId: b['id'].toString(),
                              ownerId: currentUser.id,
                            );
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('ปฏิเสธสำเร็จ')),
                            );
                            setSheetState(() {});
                          } catch (e) {
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('ปฏิเสธไม่สำเร็จ: $e')),
                            );
                          }
                        },
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dctx),
            child: const Text('ปิด'),
          ),
        ],
      ),
    );
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
          ownerId: currentUser.id,
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
        title: const Text('ถอดออกจากก๊วน'),
        content: Text(
          'ต้องการถอด "$memberName" ออกจากก๊วนใช่หรือไม่? การจองทั้งหมดของสมาชิกนี้จะถูกยกเลิก',
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
    try {
      await _repo.leaveGroup(groupId: groupId, userId: memberUserId);
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
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Shimmer.fromColors(
          baseColor: Colors.grey.shade300,
          highlightColor: Colors.grey.shade100,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(width: 120, height: 14, color: Colors.white),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                height: 18,
                color: Colors.white,
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                height: 12,
                color: Colors.white,
              ),
              const SizedBox(height: 6),
              Container(width: 180, height: 12, color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }

  TextStyle _emojiTextStyle(BuildContext context, {double fontSize = 16}) {
    return TextStyle(
      fontSize: fontSize,
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
    final user = AuthService.instance.currentUser;
    if (user == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(right: 4, bottom: 4),
      child: FloatingActionButton.extended(
        heroTag: 'createGroupFab',
        onPressed: () async {
          final result = await Navigator.pushNamed(
            context,
            '/community/sport-club/group/create',
            arguments: {'sportId': _sportId},
          );
          if (result is! Map) return;
          final String groupId = result['groupId']?.toString() ?? '';
          final String? newSportId = result['sportId']?.toString();
          if (groupId.isNotEmpty) {
            await _showCreateSessionSheet(groupId);
          }
          if (newSportId != null && _sportId != newSportId) {
            setState(() => _sportId = newSportId);
          }
          await _reload();
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
                  style: const TextStyle(fontSize: 18),
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
                        style: const TextStyle(fontSize: 18),
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
                  child: Text(
                    'ว่าง: ${((group['capacity'] as num?)?.toInt() ?? 0) - ((group['member_count'] as num?)?.toInt() ?? 0)} คน',
                  ),
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
          title: const Text('ค้นหาก๊วน'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('ค้นหา'),
                TextField(
                  controller: qController,
                  decoration: const InputDecoration(
                    hintText: 'ค้นหาก๊วน / สถานที่',
                  ),
                ),
                const SizedBox(height: 16),
                const Text('จังหวัด'),
                TextField(
                  controller: provinceController,
                  decoration: const InputDecoration(hintText: 'จังหวัด'),
                ),
                const SizedBox(height: 16),
                const Text('อำเภอ'),
                TextField(
                  controller: districtController,
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
