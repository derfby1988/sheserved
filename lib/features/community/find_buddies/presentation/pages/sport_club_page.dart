import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../../../services/auth_service.dart';
import '../../../../../../core/constants/app_colors.dart';
import '../../../find_buddies/data/fitness_buddies_repository.dart';
import '../../../../../../shared/widgets/tlz_drawer.dart';
import '../../../../../../shared/widgets/tlz_bottom_navigation_bar.dart';
import '../../../../../../shared/widgets/thai_buddhist_date_picker.dart';

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
  Set<String> _myCreatedSportIds = {};
  bool _showMapView = false;
  String? _province;
  String? _district;
  double? _radiusKm;
  DateTime? _filterDate;
  bool _filterOpenOnly = false;

  @override
  void initState() {
    super.initState();
    _repo = FitnessBuddiesRepository(Supabase.instance.client);
    _init();
  }

  Future<void> _showManageSessionSheet(String sessionId) async {
    final now = DateTime.now();
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          Future<List<Map<String, dynamic>>> loadBookings() async {
            return _repo.listSessionBookings(sessionId);
          }

          Future<void> approve(String bookingId) async {
            final user = AuthService.instance.currentUser;
            if (user == null) return;
            try {
              await _repo.approveBooking(bookingId: bookingId, ownerId: user.id);
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('อนุมัติสำเร็จ')));
              setSheetState(() {});
            } catch (e) {
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('อนุมัติไม่สำเร็จ: $e')));
            }
          }

          Future<void> reject(String bookingId) async {
            final user = AuthService.instance.currentUser;
            if (user == null) return;
            final reasonCtrl = TextEditingController();
            final confirmed = await showDialog<bool>(
              context: ctx,
              builder: (dctx) => AlertDialog(
                title: const Text('ปฏิเสธคำขอเข้าร่วม'),
                content: TextField(
                  controller: reasonCtrl,
                  decoration: const InputDecoration(hintText: 'เหตุผล (ไม่บังคับ)'),
                ),
                actions: [
                  TextButton(onPressed: () => Navigator.of(dctx).pop(false), child: const Text('ยกเลิก')),
                  TextButton(onPressed: () => Navigator.of(dctx).pop(true), child: const Text('ยืนยัน')),
                ],
              ),
            );
            if (confirmed != true) return;
            try {
              await _repo.rejectBooking(bookingId: bookingId, ownerId: user.id, reason: reasonCtrl.text.trim());
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ปฏิเสธสำเร็จ')));
              setSheetState(() {});
            } catch (e) {
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('ปฏิเสธไม่สำเร็จ: $e')));
            }
          }

          return SafeArea(
            top: false,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.8),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                child: FutureBuilder<List<Map<String, dynamic>>>(
                  future: loadBookings(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      return Center(child: Text('โหลดคำขอไม่สำเร็จ: ${snapshot.error}'));
                    }
                    final list = snapshot.data ?? const [];
                    final pending = list.where((b) => (b['status']?.toString() ?? '') == 'pending').toList();
                    final confirmed = list.where((b) => (b['status']?.toString() ?? '') == 'confirmed').toList();

                    return SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Center(
                            child: Container(
                              width: 40,
                              height: 4,
                              decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
                            ),
                          ),
                          const SizedBox(height: 12),
                          const Text('จัดการผู้เข้าร่วมรอบนี้', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 12),
                          const Text('คำขอเข้าร่วม (รออนุมัติ)', style: TextStyle(fontWeight: FontWeight.w600)),
                          const SizedBox(height: 6),
                          if (pending.isEmpty)
                            const Text('— ไม่มีคำขอค้างอยู่ —')
                          else
                            ListView.separated(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemBuilder: (c, i) {
                                final b = pending[i];
                                final u = (b['user'] as Map?) ?? {};
                                final fullName = '${u['first_name'] ?? ''} ${u['last_name'] ?? ''}'.trim();
                                final image = u['profile_image_url']?.toString() ?? '';
                                final endsAtStr = b['ends_at']?.toString();
                                final endsAt = endsAtStr != null ? DateTime.tryParse(endsAtStr)?.toLocal() : null;
                                final canAction = endsAt == null || now.isBefore(endsAt);
                                return ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: CircleAvatar(
                                    backgroundImage: image.isNotEmpty ? NetworkImage(image) : null,
                                    child: image.isEmpty ? const Icon(Icons.person) : null,
                                  ),
                                  title: Text(fullName.isNotEmpty ? fullName : 'ไม่ระบุชื่อ'),
                                  subtitle: const Text('รออนุมัติ'),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        tooltip: 'อนุมัติ',
                                        onPressed: canAction ? () => approve(b['id'].toString()) : null,
                                        icon: const Icon(Icons.check_circle, color: Colors.green),
                                      ),
                                      IconButton(
                                        tooltip: 'ปฏิเสธ',
                                        onPressed: canAction ? () => reject(b['id'].toString()) : null,
                                        icon: const Icon(Icons.cancel, color: Colors.redAccent),
                                      ),
                                    ],
                                  ),
                                );
                              },
                              separatorBuilder: (_, _) => const SizedBox(height: 4),
                              itemCount: pending.length,
                            ),
                          const SizedBox(height: 16),
                          const Text('ผู้เข้าร่วมแล้ว', style: TextStyle(fontWeight: FontWeight.w600)),
                          const SizedBox(height: 6),
                          if (confirmed.isEmpty)
                            const Text('— ยังไม่มีผู้เข้าร่วม —')
                          else
                            ListView.separated(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemBuilder: (c, i) {
                                final b = confirmed[i];
                                final u = (b['user'] as Map?) ?? {};
                                final fullName = '${u['first_name'] ?? ''} ${u['last_name'] ?? ''}'.trim();
                                final image = u['profile_image_url']?.toString() ?? '';
                                return ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: CircleAvatar(
                                    backgroundImage: image.isNotEmpty ? NetworkImage(image) : null,
                                    child: image.isEmpty ? const Icon(Icons.person) : null,
                                  ),
                                  title: Text(fullName.isNotEmpty ? fullName : 'ไม่ระบุชื่อ'),
                                  subtitle: const Text('ยืนยันแล้ว'),
                                );
                              },
                              separatorBuilder: (_, _) => const SizedBox(height: 4),
                              itemCount: confirmed.length,
                            ),
                          const SizedBox(height: 12),
                        ],
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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Ensure we reflect latest ordering/data if dependencies change after hot reload.
    if (_sports.isEmpty && !_loading) {
      _init();
    }
  }

  Future<void> _init() async {
    try {
      final userId = AuthService.instance.currentUser?.id;
      final sports = await _repo.getApprovedSports(userId: userId);
      final groups = await _repo.listGroups(currentUserId: userId);
      final adminIds = userId != null ? await _repo.listMyAdminGroupIds(userId) : <String>{};
      final joinedGroupIds = userId != null ? await _repo.listMyJoinedGroupIds(userId) : <String>{};
      final createdSportIds = userId != null ? await _repo.listMyCreatedSportIds(userId) : <String>{};
      if (!mounted) return;
      setState(() {
        _sports = sports;
        _groups = groups;
        _loading = false;
        _myAdminGroups = adminIds;
        _myJoinedGroupIds = joinedGroupIds;
        _myCreatedSportIds = createdSportIds;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _reload() async {
    setState(() => _reloadingGroups = true);
    final userId = AuthService.instance.currentUser?.id;
    try {
      final groups = await _repo.listGroups(
      sportId: _sportId,
      q: _q,
      currentUserId: userId,
      province: _province,
      district: _district,
    );
    final adminIds = userId != null ? await _repo.listMyAdminGroupIds(userId) : <String>{};
    final joinedGroupIds = userId != null ? await _repo.listMyJoinedGroupIds(userId) : <String>{};
    final createdSportIds = userId != null ? await _repo.listMyCreatedSportIds(userId) : <String>{};
      if (!mounted) return;
      setState(() {
        _groups = groups;
        _myAdminGroups = adminIds;
        _myJoinedGroupIds = joinedGroupIds;
        _myCreatedSportIds = createdSportIds;
      });
    } finally {
      if (mounted) setState(() => _reloadingGroups = false);
    }
  }

  Future<void> _book(String sessionId) async {
    final user = AuthService.instance.currentUser;
    if (user == null) {
      if (!mounted) return;
      Navigator.pushNamed(context, '/login', arguments: {'redirect': '/community/sport-club'});
      return;
    }
    try {
      await _repo.bookSession(sessionId, user.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ส่งคำขอจองแล้ว')));
      await _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('จองไม่สำเร็จ: $e')));
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
                  icon: Icon(_showMapView ? Icons.list : Icons.map, color: Colors.white),
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
                  : RefreshIndicator(
                      onRefresh: _reload,
                      child: ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: Row(
                                    children: [
                                      _buildSportChip(null, 'ทั้งหมด', icon: '🏅'),
                                      ..._sports.map((s) => _buildSportChip(s['id']?.toString(), s['name_th']?.toString() ?? 'กีฬา', icon: s['icon']?.toString())),
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
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if ((g['venue_photo_url']?.toString() ?? g['cover_image_url']?.toString() ?? '').isNotEmpty)
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.network(
                                  (g['venue_photo_url']?.toString().isNotEmpty ?? false)
                                      ? g['venue_photo_url'].toString()
                                      : g['cover_image_url'].toString(),
                                  height: 140,
                                  width: double.infinity,
                                  fit: BoxFit.cover,
                                ),
                              ),
                            if ((g['venue_photo_url']?.toString() ?? g['cover_image_url']?.toString() ?? '').isNotEmpty)
                              const SizedBox(height: 8),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.center,
                                    children: [
                                      if ((g['sport_name']?.toString() ?? '').isNotEmpty)
                                        _buildSportChipLabel(
                                          g['sport_icon']?.toString(),
                                          g['sport_name'].toString(),
                                        ),
                                      if ((g['sport_name']?.toString() ?? '').isNotEmpty)
                                        const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          g['name']?.toString() ?? '',
                                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (g['gender_preference'] != null && g['gender_preference'].toString() != 'any')
                                  Chip(
                                    label: Text(g['gender_preference'].toString() == 'male' ? 'ช.' : 'ญ.'),
                                    backgroundColor: g['gender_preference'].toString() == 'male' ? Colors.blue.shade50 : Colors.pink.shade50,
                                    visualDensity: VisualDensity.compact,
                                  )
                                else
                                  Chip(
                                    label: const Text('เสรี'),
                                    backgroundColor: Colors.green.shade50,
                                    visualDensity: VisualDensity.compact,
                                  ),
                              ],
                            ),
                            if ((g['description']?.toString() ?? '').isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(g['description'].toString(), maxLines: 2, overflow: TextOverflow.ellipsis),
                              ),
                            if ((g['province']?.toString() ?? '').isNotEmpty)
                              Text('พื้นที่: '+ g['province'].toString() + (g['district'] != null && g['district'].toString().isNotEmpty ? ' · '+ g['district'].toString() : '')),
                            if (g['member_count'] != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text('สมาชิก: ${g['member_count']} คน'),
                              ),
                            const SizedBox(height: 8),
                            FutureBuilder<List<Map<String, dynamic>>>(
                              future: _repo.listUpcomingSessions(g['id'].toString()),
                              builder: (context, snapshot) {
                                final items = snapshot.data ?? const [];
                                if (snapshot.connectionState != ConnectionState.done) {
                                  return const Padding(
                                    padding: EdgeInsets.all(8.0),
                                    child: LinearProgressIndicator(minHeight: 2),
                                  );
                                }
                                if (snapshot.hasError) {
                                  return Text(
                                    'โหลดรอบนัดไม่สำเร็จ: ${snapshot.error}',
                                    style: const TextStyle(color: Colors.red),
                                  );
                                }
                                if (items.isEmpty) {
                                  return Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text('ยังไม่มีรอบนัด'),
                                      if (_myAdminGroups.contains(g['id']?.toString() ?? ''))
                                        Align(
                                          alignment: Alignment.centerRight,
                                          child: TextButton.icon(
                                            onPressed: () => _showCreateSessionSheet(g['id'].toString()),
                                            icon: const Icon(Icons.add_circle_outline),
                                            label: const Text('เพิ่มรอบนัด'),
                                          ),
                                        ),
                                    ],
                                  );
                                }
                                final isAdmin = _myAdminGroups.contains(g['id']?.toString() ?? '');
                                final hasJoined = _myJoinedGroupIds.contains(g['id']?.toString() ?? '');
                                final joinButton = hasJoined
                                    ? TextButton.icon(
                                        onPressed: null,
                                        icon: const Icon(Icons.check_circle_outline),
                                        label: const Text('เข้าร่วมก๊วนแล้ว'),
                                      )
                                    : TextButton.icon(
                                        onPressed: () async {
                                          final upcoming = await _repo.listUpcomingSessions(g['id'].toString(), limit: 1);
                                          if (upcoming.isEmpty) {
                                            if (!mounted) return;
                                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ยังไม่มีรอบนัดให้เข้าร่วม')));
                                            return;
                                          }
                                          final sid = upcoming.first['id'].toString();
                                          await _book(sid);
                                        },
                                        icon: const Icon(Icons.event_available),
                                        label: const Text('เข้าร่วมก๊วน'),
                                      );
                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    for (final s in items.take(3))
                                      Padding(
                                        padding: const EdgeInsets.only(bottom: 8),
                                        child: Row(
                                          children: [
                                            const Text('ห้วง: ', style: TextStyle(fontWeight: FontWeight.w500)),
                                            Expanded(
                                              child: Text(
                                                _formatThaiSessionRange(
                                                  DateTime.parse(s['starts_at'].toString()).toLocal(),
                                                  DateTime.parse(s['ends_at'].toString()).toLocal(),
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            if (isAdmin)
                                              TextButton.icon(
                                                onPressed: () => _showManageSessionSheet(s['id'].toString()),
                                                icon: const Icon(Icons.groups_2_outlined),
                                                label: const Text('จัดการ'),
                                              ),
                                          ],
                                        ),
                                      ),
                                    if (isAdmin)
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.end,
                                        children: [
                                          joinButton,
                                          TextButton.icon(
                                            onPressed: () => _showCreateSessionSheet(g['id'].toString()),
                                            icon: const Icon(Icons.add_circle_outline),
                                            label: const Text('เพิ่มรอบนัด'),
                                          ),
                                        ],
                                      )
                                    else
                                      Align(
                                        alignment: Alignment.centerRight,
                                        child: joinButton,
                                      ),
                                  ],
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    )
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
    final borderColor = isMyCreated ? Colors.blue.shade100 : Colors.grey.shade300;
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
    TimeOfDay startTime = TimeOfDay(hour: roundedStart.hour, minute: roundedStart.minute);
    TimeOfDay endTime = TimeOfDay(hour: (roundedStart.add(const Duration(hours: 1))).hour, minute: roundedStart.minute);
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
        return StatefulBuilder(builder: (ctx, setModalState) {
          Future<void> pickStartTime() async {
            final picked = await showTimePicker(context: ctx, initialTime: startTime);
            if (picked != null) {
              setModalState(() => startTime = picked);
            }
          }

          Future<void> pickEndTime() async {
            final picked = await showTimePicker(context: ctx, initialTime: endTime);
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
              setModalState(() => errorText = 'เวลาเริ่มต้องไม่น้อยกว่าอีก 15 นาทีจากตอนนี้');
              return;
            }
            if (!endsAt.isAfter(startsAt)) {
              setModalState(() => errorText = 'เวลาสิ้นสุดต้องมากกว่าเวลาเริ่ม');
              return;
            }
            setModalState(() => submitting = true);
            try {
              await _repo.createSession(
                groupId: groupId,
                startsAt: startsAt,
                endsAt: endsAt,
                placeName: null,
                note: noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
              );
              if (!mounted) return;
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('สร้างรอบนัดสำเร็จ')));
              setState(() {}); // trigger refresh of FutureBuilder
            } catch (e) {
              setModalState(() => submitting = false);
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('บันทึกไม่สำเร็จ: $e')));
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
                      decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text('สร้างรอบนัด', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 12),
                  ThaiBuddhistDatePickerField(
                    value: selectedDate,
                    label: 'วันที่',
                    onDateSelected: (d) => setModalState(() => selectedDate = d),
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
                    decoration: const InputDecoration(labelText: 'หมายเหตุ (ไม่บังคับ)'),
                    maxLines: 2,
                  ),
                  if (errorText != null) ...[
                    const SizedBox(height: 8),
                    Text(errorText!, style: const TextStyle(color: Colors.redAccent)),
                  ],
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: submitting ? null : submit,
                      icon: submitting
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
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
        });
      },
    );
  }

  Future<void> _showGroupDetailSheet(Map<String, dynamic> group) async {
    final groupId = group['id'].toString();
    final isAdmin = _myAdminGroups.contains(groupId);
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          return SafeArea(
            top: false,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.75),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                child: FutureBuilder<List<dynamic>>(
                  future: Future.wait([
                    _repo.listSessions(groupId),
                    _repo.listGroupMembers(groupId),
                  ]),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      return Center(child: Text('โหลดข้อมูลไม่สำเร็จ: ${snapshot.error}'));
                    }
                    final sessions = (snapshot.data?[0] as List?)?.cast<Map<String, dynamic>>() ?? [];
                    final members = (snapshot.data?[1] as List?)?.cast<Map<String, dynamic>>() ?? [];
                    return SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            group['name']?.toString() ?? '',
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                          ),
                          if (group['member_count'] != null)
                            Text('สมาชิก: ${group['member_count']} คน'),
                          const SizedBox(height: 12),
                          const Text('รอบนัด', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 8),
                          if (sessions.isEmpty)
                            const Text('ยังไม่มีรอบนัด')
                          else
                            ListView.separated(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: sessions.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 8),
                              itemBuilder: (ctx, i) {
                                final s = sessions[i];
                                return Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        'ห้วง: ${_formatThaiSessionRange(
                                          DateTime.parse(s['starts_at'].toString()).toLocal(),
                                          DateTime.parse(s['ends_at'].toString()).toLocal(),
                                        )}',
                                      ),
                                    ),
                                    if (isAdmin)
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          TextButton.icon(
                                            onPressed: () => _showManageSessionSheet(s['id'].toString()),
                                            icon: const Icon(Icons.groups_2_outlined),
                                            label: const Text('จัดการ'),
                                          ),
                                          TextButton(
                                            onPressed: () async {
                                              final confirm = await showDialog<bool>(
                                                context: ctx,
                                                builder: (ctx2) => AlertDialog(
                                                  title: const Text('ยกเลิกรอบนัด'),
                                                  content: const Text('ต้องการลบรอบนัดนี้ใช่หรือไม่?'),
                                                  actions: [
                                                    TextButton(onPressed: () => Navigator.of(ctx2).pop(false), child: const Text('ยกเลิก')),
                                                    TextButton(onPressed: () => Navigator.of(ctx2).pop(true), child: const Text('ยืนยัน')),
                                                  ],
                                                ),
                                              );
                                              if (confirm != true) return;
                                              try {
                                                await _repo.cancelSession(s['id'].toString());
                                                if (!context.mounted) return;
                                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ยกเลิกรอบนัดแล้ว')));
                                                setSheetState(() {});
                                              } catch (e) {
                                                if (!context.mounted) return;
                                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('ยกเลิกไม่สำเร็จ: $e')));
                                              }
                                            },
                                            child: const Text('ยกเลิก', style: TextStyle(color: Colors.red)),
                                          ),
                                        ],
                                      ),
                                  ],
                                );
                              },
                            ),
                          const SizedBox(height: 16),
                          const Text('รายชื่อผู้เข้าร่วมก๊วน', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 8),
                          if (members.isEmpty)
                            const Text('ยังไม่มีสมาชิก')
                          else
                            ListView.separated(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: members.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 8),
                              itemBuilder: (ctx, i) {
                                final m = members[i];
                                final user = (m['user'] as Map?) ?? {};
                                final fullName = '${user['first_name'] ?? ''} ${user['last_name'] ?? ''}'.trim();
                                final image = user['profile_image_url']?.toString() ?? '';
                                final role = (m['role']?.toString() == 'admin') ? 'ผู้ดูแล' : 'สมาชิก';
                                final active = m['is_active'] == true ? 'กำลังเข้าร่วม' : 'หยุดพัก';
                                return ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: CircleAvatar(
                                    backgroundImage: image.isNotEmpty ? NetworkImage(image) : null,
                                    child: image.isEmpty ? const Icon(Icons.person) : null,
                                  ),
                                  title: Text(fullName.isNotEmpty ? fullName : 'ไม่ระบุชื่อ'),
                                  subtitle: Text('$role · $active'),
                                );
                              },
                            ),
                          const SizedBox(height: 20),
                        ],
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

  static const _thaiMonths = ['ม.ค.', 'ก.พ.', 'มี.ค.', 'เม.ย.', 'พ.ค.', 'มิ.ย.', 'ก.ค.', 'ส.ค.', 'ก.ย.', 'ต.ค.', 'พ.ย.', 'ธ.ค.'];

  String _formatThaiTime(DateTime d) => '${d.hour.toString().padLeft(2, '0')}.${d.minute.toString().padLeft(2, '0')}';

  String _formatThaiBuddhistDateTime(DateTime d) {
    final beShort = ((d.year + 543) % 100).toString();
    return '${d.day} ${_thaiMonths[d.month - 1]} $beShort ${_formatThaiTime(d)} น.';
  }

  String _formatThaiSessionRange(DateTime start, DateTime end) {
    final beShort = ((start.year + 543) % 100).toString();
    if (start.year == end.year && start.month == end.month && start.day == end.day) {
      return '${start.day} ${_thaiMonths[start.month - 1]} $beShort ${_formatThaiTime(start)}-${_formatThaiTime(end)} น.';
    }
    return '${_formatThaiBuddhistDateTime(start)} - ${_formatThaiBuddhistDateTime(end)}';
  }

  TextStyle _emojiTextStyle(BuildContext context) {
    final platform = Theme.of(context).platform;
    if (platform == TargetPlatform.iOS || platform == TargetPlatform.macOS) {
      return const TextStyle(fontFamily: 'Apple Color Emoji');
    }
    if (platform == TargetPlatform.android) {
      return const TextStyle(fontFamily: 'Noto Color Emoji');
    }
    if (platform == TargetPlatform.windows) {
      return const TextStyle(fontFamily: 'Segoe UI Emoji');
    }
    return const TextStyle(
      fontFamilyFallback: ['Apple Color Emoji', 'Noto Color Emoji', 'Segoe UI Emoji'],
    );
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
              Container(width: double.infinity, height: 18, color: Colors.white),
              const SizedBox(height: 8),
              Container(width: double.infinity, height: 12, color: Colors.white),
              const SizedBox(height: 6),
              Container(width: 180, height: 12, color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSportChipLabel(String? icon, String label) {
    return Text.rich(
      TextSpan(
        children: [
          if (icon != null && icon.isNotEmpty)
            TextSpan(
              text: '$icon ',
              style: _emojiTextStyle(context),
            ),
          TextSpan(text: label),
        ],
      ),
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
          final createdId = await Navigator.pushNamed(
            context,
            '/community/sport-club/group/create',
            arguments: {'sportId': _sportId},
          );
          if (createdId != null) {
            final String groupId = createdId.toString();
            await _showCreateSessionSheet(groupId);
            _reload();
          }
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

  void _showSearchDialog() {
    final qController = TextEditingController(text: _q);
    final provinceController = TextEditingController(text: _province ?? '');
    final districtController = TextEditingController(text: _district ?? '');
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ค้นหาก๊วน'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('ค้นหา'),
              TextField(
                controller: qController,
                decoration: const InputDecoration(hintText: 'ค้นหาก๊วน / สถานที่'),
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
                title: const Text('เฉพาะก๊วนเปิดรับ'),
                value: _filterOpenOnly,
                onChanged: (v) => setState(() => _filterOpenOnly = v ?? false),
              ),
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
              _province = provinceController.text.isEmpty ? null : provinceController.text;
              _district = districtController.text.isEmpty ? null : districtController.text;
              Navigator.pop(context);
              _reload();
            },
            child: const Text('ค้นหา'),
          ),
        ],
      ),
    );
  }
}
