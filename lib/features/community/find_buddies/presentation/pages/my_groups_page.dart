import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../../../services/auth_service.dart';
import '../../../../../../core/constants/app_colors.dart';
import '../../../find_buddies/data/fitness_buddies_repository.dart';
import '../../../find_buddies/presentation/widgets/group_chat_popup.dart';

class MyGroupsPage extends StatefulWidget {
  const MyGroupsPage({super.key});

  @override
  State<MyGroupsPage> createState() => _MyGroupsPageState();
}

class _MyGroupsPageState extends State<MyGroupsPage> {
  late final FitnessBuddiesRepository _repo;
  bool _loading = true;
  List<Map<String, dynamic>> _myGroups = [];
  List<Map<String, dynamic>> _myBookings = [];

  @override
  void initState() {
    super.initState();
    _repo = FitnessBuddiesRepository(Supabase.instance.client);
    _init();
  }

  Future<void> _init() async {
    try {
      final userId = AuthService.instance.currentUser?.id;
      if (userId == null) {
        if (!mounted) return;
        setState(() => _loading = false);
        return;
      }
      final results = await Future.wait([
        _repo.listMyGroups(userId),
        _repo.listMyBookings(userId),
      ]);
      if (!mounted) return;
      setState(() {
        _myGroups = (results[0] as List?)?.cast<Map<String, dynamic>>() ?? [];
        _myBookings = (results[1] as List?)?.cast<Map<String, dynamic>>() ?? [];
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  static const _thaiMonths = ['ม.ค.', 'ก.พ.', 'มี.ค.', 'เม.ย.', 'พ.ค.', 'มิ.ย.', 'ก.ค.', 'ส.ค.', 'ก.ย.', 'ต.ค.', 'พ.ย.', 'ธ.ค.'];

  String _formatThaiTime(DateTime d) => '${d.hour.toString().padLeft(2, '0')}.${d.minute.toString().padLeft(2, '0')}';

  String _formatThaiBuddhistDateTime(DateTime d) {
    final beShort = ((d.year + 543) % 100).toString();
    return '${d.day} ${_thaiMonths[d.month - 1]} $beShort ${_formatThaiTime(d)} น.';
  }

  String _bookingStatusLabel(String? status) {
    switch (status) {
      case 'pending':
        return 'รออนุมัติ';
      case 'confirmed':
        return 'ยืนยันแล้ว';
      case 'rejected':
        return 'ถูกปฏิเสธ';
      case 'cancelled':
        return 'ยกเลิกแล้ว';
      default:
        return status ?? '-';
    }
  }

  Color _bookingStatusColor(String? status) {
    switch (status) {
      case 'pending':
        return Colors.orange;
      case 'confirmed':
        return Colors.green;
      case 'rejected':
        return Colors.red;
      case 'cancelled':
        return Colors.grey;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ก๊วนของฉัน'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _init,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // ── My Groups ──
                  const Text('ก๊วนที่ฉันสร้าง/เข้าร่วม', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  if (_myGroups.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('ยังไม่มีก๊วน — ไปหาก๊วนที่หน้า "หาเพื่อนออกกำลังกาย"'),
                      ),
                    )
                  else
                    ..._myGroups.map((g) => _buildGroupCard(g)),

                  const SizedBox(height: 24),

                  // ── My Bookings ──
                  const Text('ประวัติการจอง', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  if (_myBookings.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('ยังไม่มีประวัติการจอง'),
                      ),
                    )
                  else
                    ..._myBookings.map((b) => _buildBookingCard(b)),
                ],
              ),
            ),
    );
  }

  Widget _buildGroupCard(Map<String, dynamic> group) {
    final role = group['my_role']?.toString() ?? '';
    final isAdmin = role == 'owner';
    final sport = (group['sport'] as Map?) ?? {};
    final sportName = sport['name_th']?.toString() ?? '';
    final sportIcon = sport['icon']?.toString() ?? '';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: AppColors.primary.withOpacity(0.1),
          child: Text(sportIcon.isNotEmpty ? sportIcon : '🏃', style: const TextStyle(fontSize: 20)),
        ),
        title: Text(group['name']?.toString() ?? 'ไม่ระบุชื่อ'),
        subtitle: Text(sportName.isNotEmpty ? '$sportName${isAdmin ? ' · เจ้าของก๊วน' : ' · สมาชิก'}' : (isAdmin ? 'เจ้าของก๊วน' : 'สมาชิก')),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.chat_bubble_outline),
              tooltip: 'แชทก๊วน',
              onPressed: () {
                final gid = group['id']?.toString() ?? '';
                final gname = group['name']?.toString() ?? 'ก๊วน';
                if (gid.isNotEmpty) {
                  showGroupChatPopup(context, groupId: gid, groupName: gname);
                }
              },
            ),
            const Icon(Icons.chevron_right),
          ],
        ),
        onTap: () {
          Navigator.pushNamed(context, '/community/sport-club', arguments: {'groupId': group['id']?.toString()});
        },
      ),
    );
  }

  Widget _buildBookingCard(Map<String, dynamic> booking) {
    final session = (booking['session'] as Map?) ?? {};
    final group = (session['group'] as Map?) ?? {};
    final sport = (group['sport'] as Map?) ?? {};
    final groupName = group['name']?.toString() ?? 'ไม่ระบุชื่อ';
    final sportName = sport['name_th']?.toString() ?? '';
    final status = booking['status']?.toString();
    final startsAtStr = session['starts_at']?.toString();
    final startsAt = startsAtStr != null ? DateTime.tryParse(startsAtStr)?.toLocal() : null;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: _bookingStatusColor(status),
          child: Icon(
            status == 'confirmed' ? Icons.check : status == 'pending' ? Icons.hourglass_empty : Icons.close,
            color: Colors.white,
            size: 20,
          ),
        ),
        title: Text(groupName),
        subtitle: Text([
          if (sportName.isNotEmpty) sportName,
          if (startsAt != null) _formatThaiBuddhistDateTime(startsAt),
        ].join(' · ')),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: _bookingStatusColor(status).withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            _bookingStatusLabel(status),
            style: TextStyle(fontSize: 12, color: _bookingStatusColor(status), fontWeight: FontWeight.w600),
          ),
        ),
        onTap: () {
          Navigator.pushNamed(context, '/community/sport-club', arguments: {'groupId': group['id']?.toString()});
        },
      ),
    );
  }
}
