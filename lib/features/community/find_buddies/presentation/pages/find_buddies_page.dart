import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../../../services/auth_service.dart';
import '../../../../../../core/constants/app_colors.dart';
import '../../../find_buddies/data/fitness_buddies_repository.dart';
import '../../../../../../shared/widgets/tlz_drawer.dart';

class FindBuddiesPage extends StatefulWidget {
  const FindBuddiesPage({super.key});

  @override
  State<FindBuddiesPage> createState() => _FindBuddiesPageState();
}

class _FindBuddiesPageState extends State<FindBuddiesPage> {
  late final FitnessBuddiesRepository _repo;
  List<Map<String, dynamic>> _groups = [];
  List<Map<String, dynamic>> _sports = [];
  String? _sportId;
  String _q = '';
  bool _loading = true;
  Set<String> _myAdminGroups = {};
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

  Future<void> _init() async {
    try {
      final sports = await _repo.getApprovedSports();
      final userId = AuthService.instance.currentUser?.id;
      final groups = await _repo.listGroups(currentUserId: userId);
      final adminIds = userId != null ? await _repo.listMyAdminGroupIds(userId) : <String>{};
      if (!mounted) return;
      setState(() {
        _sports = sports;
        _groups = groups;
        _loading = false;
        _myAdminGroups = adminIds;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _reload() async {
    setState(() => _loading = true);
    final userId = AuthService.instance.currentUser?.id;
    final groups = await _repo.listGroups(
      sportId: _sportId,
      q: _q,
      currentUserId: userId,
      province: _province,
      district: _district,
    );
    final adminIds = userId != null ? await _repo.listMyAdminGroupIds(userId) : <String>{};
    if (!mounted) return;
    setState(() {
      _groups = groups;
      _loading = false;
      _myAdminGroups = adminIds;
    });
  }

  Future<void> _book(String sessionId) async {
    final user = AuthService.instance.currentUser;
    if (user == null) {
      if (!mounted) return;
      Navigator.pushNamed(context, '/login', arguments: {'redirect': '/community/find-buddies'});
      return;
    }
    try {
      await _repo.bookSession(sessionId, user.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ส่งคำขอจองแล้ว')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('จองไม่สำเร็จ: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primary,
      drawer: TlzDrawer(),
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
                  icon: const Icon(Icons.filter_list, color: Colors.white),
                  onPressed: () => _showFilterDialog(),
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
                          const Text('หมายเหตุ: ก๊วนส่วนตัวจะมองเห็นเฉพาะสมาชิกของก๊วนนั้นเท่านั้น'),
                          const SizedBox(height: 8),
                          SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _buildSportChip(null, 'ทั้งหมด'),
                        ..._sports.map((s) => _buildSportChip(s['id']?.toString(), s['name_th']?.toString() ?? 'กีฬา')),
                        _buildAddSportButton(),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          decoration: const InputDecoration(hintText: 'ค้นหาก๊วน / สถานที่'),
                          onChanged: (v) => _q = v,
                          onSubmitted: (_) => _reload(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (_province != null || _district != null || _filterOpenOnly)
                        Chip(
                          label: const Text('ตัวกรองใช้งาน'),
                          deleteIcon: const Icon(Icons.clear),
                          onDeleted: () {
                            setState(() {
                              _province = null;
                              _district = null;
                              _filterOpenOnly = false;
                            });
                            _reload();
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  for (final g in _groups)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if ((g['cover_image_url']?.toString() ?? '').isNotEmpty)
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.network(
                                  g['cover_image_url'].toString(),
                                  height: 140,
                                  width: double.infinity,
                                  fit: BoxFit.cover,
                                ),
                              ),
                            if ((g['cover_image_url']?.toString() ?? '').isNotEmpty)
                              const SizedBox(height: 8),
                            Text(g['name']?.toString() ?? '', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                            if ((g['description']?.toString() ?? '').isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(g['description'].toString(), maxLines: 2, overflow: TextOverflow.ellipsis),
                              ),
                            Row(
                              children: [
                                if (g['sport_name'] != null)
                                  Chip(
                                    label: Text(g['sport_name'].toString()),
                                    backgroundColor: Colors.blue.shade50,
                                  ),
                                if ((g['province']?.toString() ?? '').isNotEmpty)
                                  Text('พื้นที่: '+ g['province'].toString() + (g['district'] != null && g['district'].toString().isNotEmpty ? ' · '+ g['district'].toString() : '')),
                              ],
                            ),
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
                                if (items.isEmpty) {
                                  return const Text('ยังไม่มีรอบนัด');
                                }
                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('รอบนัดใกล้เคียง:'),
                                    const SizedBox(height: 8),
                                    for (final s in items.take(3))
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Expanded(
                                            child: Text(
                                              '${DateTime.parse(s['starts_at'].toString()).toLocal()} - ${DateTime.parse(s['ends_at'].toString()).toLocal()}',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          TextButton(
                                            onPressed: () => _book(s['id'].toString()),
                                            child: const Text('เข้าร่วม/จอง'),
                                          ),
                                        ],
                                      ),
                                    if (_myAdminGroups.contains(g['id']?.toString() ?? ''))
                                      Align(
                                        alignment: Alignment.centerRight,
                                        child: TextButton.icon(
                                          onPressed: () {
                                            Navigator.pushNamed(
                                              context,
                                              '/community/find-buddies/session/create',
                                              arguments: {'groupId': g['id'].toString()},
                                            );
                                          },
                                          icon: const Icon(Icons.add_circle_outline),
                                          label: const Text('เพิ่มรอบนัด'),
                                        ),
                                      ),
                                  ],
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        ],
      ),
      floatingActionButton: AuthService.instance.currentUser != null
          ? FloatingActionButton.extended(
              onPressed: () async {
                final createdId = await Navigator.pushNamed(context, '/community/find-buddies/group/create');
                if (createdId != null) {
                  _reload();
                }
              },
              icon: const Icon(Icons.add),
              label: const Text('สร้างก๊วน'),
            )
          : null,
    );
  }

  Widget _buildSportChip(String? id, String label) {
    final isSelected = _sportId == id;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        selected: isSelected,
        onSelected: (selected) {
          setState(() => _sportId = selected ? id : null);
          _reload();
        },
        selectedColor: Colors.blue.shade100,
        checkmarkColor: Colors.blue,
      ),
    );
  }

  Widget _buildAddSportButton() {
    final user = AuthService.instance.currentUser;
    final isAdmin = user?.role == 'admin';
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ActionChip(
        avatar: const Icon(Icons.add),
        label: Text(isAdmin ? 'เพิ่มหมวดหมู่' : 'เสนอหมวดหมู่'),
        onPressed: () {
          Navigator.pushNamed(context, isAdmin ? '/community/find-buddies/sport/manage' : '/community/find-buddies/sport/propose');
        },
      ),
    );
  }

  void _showSearchDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ค้นหาก๊วน'),
        content: TextField(
          decoration: const InputDecoration(hintText: 'ค้นหาก๊วน / สถานที่'),
          onChanged: (v) => _q = v,
          onSubmitted: (_) {
            Navigator.pop(context);
            _reload();
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ยกเลิก'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _reload();
            },
            child: const Text('ค้นหา'),
          ),
        ],
      ),
    );
  }

  void _showFilterDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ตัวกรอง'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('จังหวัด'),
              TextField(
                decoration: const InputDecoration(hintText: 'จังหวัด'),
                onChanged: (v) => _province = v.isEmpty ? null : v,
              ),
              const SizedBox(height: 16),
              const Text('อำเภอ'),
              TextField(
                decoration: const InputDecoration(hintText: 'อำเภอ'),
                onChanged: (v) => _district = v.isEmpty ? null : v,
              ),
              const SizedBox(height: 16),
              const Text('รัศมี (กม.)'),
              TextField(
                decoration: const InputDecoration(hintText: 'รัศมี'),
                keyboardType: TextInputType.number,
                onChanged: (v) => _radiusKm = double.tryParse(v),
              ),
              const SizedBox(height: 16),
              const Text('วันที่'),
              TextField(
                decoration: const InputDecoration(hintText: 'วันที่'),
                keyboardType: TextInputType.datetime,
                onTap: () async {
                  final date = await showDatePicker(
                    context: context,
                    initialDate: DateTime.now(),
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (date != null) {
                    _filterDate = date;
                  }
                },
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
              Navigator.pop(context);
              _reload();
            },
            child: const Text('ใช้ตัวกรอง'),
          ),
        ],
      ),
    );
  }
}
