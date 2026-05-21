import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../services/service_locator.dart';
import '../../../../services/auth_service.dart';
import '../../../../features/auth/data/repositories/user_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../chat/data/models/chat_models.dart';
import '../../data/repositories/consultation_repository.dart';
import '../../data/models/consultation_entry.dart';
import '../../../../shared/widgets/widgets.dart';
import 'expert_chat_room_page.dart';
import '../widgets/dashboard/availability_toggle_button.dart';
import '../widgets/dashboard/availability_banner.dart';

class HealthProgramRequestDashboard extends StatefulWidget {
  final String? initialFocusId;
  const HealthProgramRequestDashboard({super.key, this.initialFocusId});

  @override
  State<HealthProgramRequestDashboard> createState() =>
      _HealthProgramRequestDashboardState();
}

class _HealthProgramRequestDashboardState
    extends State<HealthProgramRequestDashboard>
    with SingleTickerProviderStateMixin {
  ConsultationRepository get _repo =>
      ServiceLocator.instance.consultationRepository;
  UserRepository get _userRepo => UserRepository(Supabase.instance.client);

  final _currentUser = AuthService.instance.currentUser;

  List<ConsultationEntry> _all = [];
  List<ConsultationEntry> _filtered = [];
  bool _isLoading = true;
  String _searchQuery = '';
  String _filterStatus = 'all';
  List<String> _myPackageIds = []; // package IDs ที่ตรงกับอาชีพ provider
  bool _isProvider = false;
  String _availabilityStatus = 'online'; // สถานะตัวเอง

  StreamSubscription? _subscription;
  String? _highlightedId;
  final Map<String, GlobalKey> _cardKeys = {};

  static const _tabs = [
    {'value': 'all', 'label': 'ทั้งหมด'},
    {'value': 'pending', 'label': 'รอดำเนินการ'},
    {'value': 'in_progress', 'label': 'กำลังดำเนินการ'},
    {'value': 'completed', 'label': 'เสร็จสิ้น'},
  ];

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  Future<void> _init() async {
    final user = _currentUser;
    if (user == null) return;

    try {
      debugPrint('Dashboard: Initializing for user ${user.id}');

      // ตรวจว่าเป็น provider หรือเปล่า (มี professionId และไม่ใช่ consumer)
      _isProvider =
          user.professionId != null &&
          user.professionId != '00000000-0000-0000-0000-000000000001';

      // โหลดข้อมูลพื้นฐานขนานกันพร้อม timeout
      await Future.wait([
        _userRepo
            .getAvailabilityStatus(user.id)
            .then((s) => _availabilityStatus = s),
        if (_isProvider && user.professionId != null)
          _repo
              .getPackageIdsForProfession(user.professionId!)
              .then((ids) => _myPackageIds = ids),
      ]).timeout(const Duration(seconds: 15));

      // โหลดข้อมูลและ subscribe
      await _loadData();
      _subscribeToChanges();
    } catch (e) {
      debugPrint('Dashboard init error: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          // มั่นใจว่าจะมีการลองโหลดข้อมูลเบื้องต้น
        });
        _loadData();
      }
    }
  }

  void _subscribeToChanges() {
    final stream = (_isProvider && _myPackageIds.isNotEmpty)
        ? _repo.watchRequestsForProfession(_myPackageIds)
        : _repo.watchAllRequestsWithUserInfo();

    _subscription = stream.listen((raw) {
      final entries = raw.map(ConsultationEntry.fromMap).toList();
      if (mounted) {
        setState(() {
          _all = entries;
          _applyFilter();
          _isLoading = false;
        });
      }
    });
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      var raw = (_isProvider && _myPackageIds.isNotEmpty)
          ? await _repo.getRequestsForProfession(_myPackageIds)
          : await _repo.getAllRequestsWithUserInfo();

      // Fallback: หากกรองแล้วไม่เจออะไรเลย ให้ลองโหลดทั้งหมดมาดู (เผื่อกรณี mapping package ตกหล่น)
      if (raw.isEmpty && _isProvider) {
        debugPrint(
          'Dashboard: Filtered list empty, falling back to all requests',
        );
        raw = await _repo.getAllRequestsWithUserInfo();
      }

      final entries = raw.map(ConsultationEntry.fromMap).toList();
      if (mounted) {
        setState(() {
          _all = entries;
          _applyFilter();
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Dashboard error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _applyFilter() {
    _filtered = _all.where((e) {
      final matchStatus = _filterStatus == 'all' || e.status == _filterStatus;
      final q = _searchQuery.toLowerCase();
      final matchSearch =
          q.isEmpty ||
          e.patientName.toLowerCase().contains(q) ||
          e.packageName.toLowerCase().contains(q) ||
          e.bodyArea.toLowerCase().contains(q);
      return matchStatus && matchSearch;
    }).toList();
  }

  int get _total => _all.length;
  int get _pending => _all.where((e) => e.status == 'pending').length;
  int get _inProgress => _all.where((e) => e.status == 'in_progress').length;
  int get _completed => _all.where((e) => e.status == 'completed').length;

  // ─── Provider รับงาน ────────────────────────────────────────────────────────
  Future<void> _joinRequest(ConsultationEntry entry) async {
    final user = _currentUser;
    if (user == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'รับงานนี้?',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('ผู้ป่วย: ${entry.patientName}'),
            const SizedBox(height: 4),
            Text('แพ็คเกจ: ${entry.packageName}'),
            const SizedBox(height: 4),
            Text('ราคา: ${entry.price.toInt()} บาท'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.warning.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.warning.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: AppColors.warning, size: 16),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'สถานะของคุณจะเปลี่ยนเป็น "ไม่ว่าง" หลังจากรับงาน',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'ยกเลิก',
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('รับงาน'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      // 1. พยายาม Assign provider เข้า expert group slot (ระบบใหม่ Phase 1)
      if (entry.packageId != null && user.professionId != null) {
        try {
          await _repo.assignProviderToGroup(
            consultationId: entry.id,
            providerId: user.id,
            packageId: entry.packageId!,
            professionId: user.professionId!,
          );
        } catch (_) {
          // Fallback: ใช้ระบบเดิม (direct assign) ถ้า expert group ไม่ตรง
          debugPrint('Expert group match failed, using direct assign fallback');
          await _repo.assignProvider(
            requestId: entry.id,
            providerId: user.id,
          );
        }
      } else {
        // ไม่มี packageId หรือ professionId → ใช้ระบบ assign ตรง
        await _repo.assignProvider(
          requestId: entry.id,
          providerId: user.id,
        );
      }

      // 1.5 อัปเดตสถานะ request ให้เป็น in_progress
      await _repo.updateStatus(entry.id, 'in_progress');

      // 2. เปลี่ยนสถานะตัวเองเป็น busy
      await _userRepo.setAvailabilityStatus(user.id, 'busy');
      if (mounted) setState(() => _availabilityStatus = 'busy');

      // 3. นำทางเข้าห้องแชท
      if (mounted) {
        _openChat(entry);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('เกิดข้อผิดพลาด: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  // ─── Provider เปลี่ยนสถานะตัวเอง ────────────────────────────────────────────
  Future<void> _toggleAvailability() async {
    final user = _currentUser;
    if (user == null) return;

    final newStatus = _availabilityStatus == 'busy' ? 'online' : 'busy';
    await _userRepo.setAvailabilityStatus(user.id, newStatus);
    if (mounted) setState(() => _availabilityStatus = newStatus);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            newStatus == 'online'
                ? '✅ เปลี่ยนเป็นพร้อมรับงานแล้ว'
                : '🔴 เปลี่ยนเป็นไม่ว่างแล้ว',
          ),
          backgroundColor: newStatus == 'online'
              ? AppColors.success
              : AppColors.warning,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      drawer: const TlzDrawer(),
      body: NestedScrollView(
        headerSliverBuilder: (ctx, _) => [_buildAppBar()],
        body: _isLoading ? _buildLoading() : _buildBody(),
      ),
    );
  }

  // ─── Sliver App Bar ────
  SliverAppBar _buildAppBar() {
    return SliverAppBar(
      expandedHeight: _isProvider ? 300 : 250,
      pinned: true,
      stretch: true,
      backgroundColor: AppColors.primary,
      automaticallyImplyLeading: false,
      // ── Standard Top Bar — ไม่มี actions พิเศษอีกต่อไป ──
      title: TlzAppTopBar.onPrimary(
        searchHintText: 'ค้นหาคำร้องขอ...',
        notificationCount: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: Colors.white,
            size: 20,
          ),
          onPressed: () => Navigator.pop(context),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
        ),
      ),
      flexibleSpace: FlexibleSpaceBar(
        titlePadding: EdgeInsets.zero,
        background: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.primary, Color(0xFF5A9B08), Color(0xFF437A05)],
            ),
          ),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              _isProvider ? 135 : 125,
              16,
              16,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── Provider info row: ข้อความ + ปุ่มสถานะ + ปุ่ม Refresh ──
                if (_isProvider) ...[
                  Row(
                    children: [
                      const Icon(
                        Icons.filter_list_rounded,
                        color: Colors.white70,
                        size: 13,
                      ),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          'แสดงเฉพาะแพ็คเกจกลุ่มอาชีพของคุณ',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.8),
                            fontSize: 11,
                          ),
                        ),
                      ),
                      // ปุ่มสถานะ (ว่าง/ไม่ว่าง)
                      AvailabilityToggleButton(
                        status: _availabilityStatus,
                        onToggle: _toggleAvailability,
                      ),
                      const SizedBox(width: 6),
                      // ปุ่ม Refresh
                      GestureDetector(
                        onTap: _loadData,
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.3),
                            ),
                          ),
                          child: const Icon(
                            Icons.refresh_rounded,
                            color: Colors.white,
                            size: 16,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                ],
                // ── Stat chips ──
                Row(
                  children: [
                    _statChip('ทั้งหมด', _total, Icons.list_alt, Colors.white),
                    const SizedBox(width: 8),
                    _statChip(
                      'รอดำเนินการ',
                      _pending,
                      Icons.pending_outlined,
                      AppColors.warning,
                    ),
                    const SizedBox(width: 8),
                    _statChip(
                      'กำลังดำเนินการ',
                      _inProgress,
                      Icons.forum_outlined,
                      AppColors.info,
                    ),
                    const SizedBox(width: 8),
                    _statChip(
                      'เสร็จสิ้น',
                      _completed,
                      Icons.check_circle_outline,
                      AppColors.success,
                    ),
                  ],
                ),
                if (_isProvider) ...[
                  const SizedBox(height: 8),
                  AvailabilityBanner(status: _availabilityStatus),
                ],
                // ── Refresh สำหรับ non-provider ──
                if (!_isProvider) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: GestureDetector(
                      onTap: _loadData,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.3),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.refresh_rounded,
                              color: Colors.white,
                              size: 14,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'รีเฟรช',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.9),
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _statChip(String label, int count, IconData icon, Color accent) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.15),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withOpacity(0.25)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: accent, size: 16),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                '$count',
                style: TextStyle(
                  color: accent,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.8),
                  fontSize: 9,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoading() => const Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        CircularProgressIndicator(color: AppColors.primary),
        SizedBox(height: 16),
        Text('กำลังโหลดรายการ...', style: TextStyle(color: Colors.grey)),
      ],
    ),
  );

  Widget _buildBody() {
    return Column(
      children: [
        _buildSearchFilter(),
        Expanded(
          child: _filtered.isEmpty
              ? _buildEmpty()
              : RefreshIndicator(
                  onRefresh: _loadData,
                  color: AppColors.primary,
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    itemCount: _filtered.length,
                    itemBuilder: (ctx, i) => _buildCard(_filtered[i], i),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildSearchFilter() {
    return Container(
      color: AppColors.background,
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Column(
        children: [
          // Search bar
          Container(
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: TextField(
              onChanged: (v) {
                setState(() => _searchQuery = v);
                _applyFilter();
              },
              style: const TextStyle(fontSize: 14, color: Colors.black87),
              decoration: InputDecoration(
                hintText: 'ค้นหาผู้ป่วย แพ็คเกจ บริเวณอาการ...',
                hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade400),
                prefixIcon: const Icon(
                  Icons.search,
                  color: AppColors.primary,
                  size: 20,
                ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          const SizedBox(height: 10),
          // Status tabs
          SizedBox(
            height: 32,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _tabs.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (ctx, i) {
                final tab = _tabs[i];
                final active = _filterStatus == tab['value'];
                return GestureDetector(
                  onTap: () {
                    setState(() => _filterStatus = tab['value']!);
                    _applyFilter();
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: active ? AppColors.primary : Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: active
                            ? AppColors.primary
                            : Colors.grey.shade300,
                      ),
                      boxShadow: active
                          ? [
                              BoxShadow(
                                color: AppColors.primary.withOpacity(0.3),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ]
                          : [],
                    ),
                    child: Text(
                      tab['label']!,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: active ? Colors.white : Colors.grey.shade600,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildCard(ConsultationEntry e, int index) {
    final myUserId = _currentUser?.id;
    final isMyJob = e.providerId == myUserId;
    final isBusy = e.isAssigned && !isMyJob; // งานถูก provider อื่นรับแล้ว

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 300 + index * 60),
      curve: Curves.easeOut,
      builder: (ctx, v, child) => Opacity(
        opacity: v,
        child: Transform.translate(
          offset: Offset(0, 20 * (1 - v)),
          child: child,
        ),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: isMyJob
              ? Border.all(
                  color: AppColors.primary.withOpacity(0.5),
                  width: 1.5,
                )
              : null,
          boxShadow: [
            BoxShadow(
              color: isMyJob
                  ? AppColors.primary.withOpacity(0.12)
                  : Colors.black.withOpacity(0.07),
              blurRadius: 12,
              spreadRadius: isMyJob ? 2 : 0,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            // Header row
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: Row(
                children: [
                  _avatar(e),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          e.patientName,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          DateFormat('d MMM yyyy  HH:mm').format(e.requestedAt),
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      _statusBadge(e.status),
                      if (isMyJob) ...[
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            'งานของคุณ',
                            style: TextStyle(
                              fontSize: 9,
                              color: AppColors.primary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 14),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FBF8),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  _infoRow(
                    Icons.spa_outlined,
                    'แพ็คเกจ',
                    e.packageName,
                    AppColors.primary,
                  ),
                  const SizedBox(height: 8),
                  _infoRow(
                    Icons.location_on_outlined,
                    'บริเวณที่พบอาการ',
                    e.bodyArea,
                    AppColors.warning,
                  ),
                  const SizedBox(height: 8),
                  _infoRow(
                    Icons.payments_outlined,
                    'ราคา',
                    '${e.price.toInt()} บาท',
                    AppColors.info,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
              child: _buildActionRow(e, isMyJob: isMyJob, isBusy: isBusy),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionRow(
    ConsultationEntry e, {
    required bool isMyJob,
    required bool isBusy,
  }) {
    String label;
    IconData icon;
    VoidCallback? onTap;
    Color btnColor = const Color(0xFF6ED1A6);

    if (!_isProvider) {
      label = 'เข้าห้องแชทผู้ป่วย';
      icon = Icons.chat_bubble_outline;
      onTap = () => _openChat(e);
    } else if (isMyJob) {
      label = 'เข้าห้องแชทผู้ป่วย';
      icon = Icons.chat_bubble_outline;
      onTap = () => _openChat(e);
    } else if (e.status == 'pending' && !isBusy) {
      final canJoin = _availabilityStatus != 'busy';
      label = canJoin ? 'รับงานนี้' : 'คุณไม่ว่างอยู่';
      icon = canJoin ? Icons.pan_tool_alt_outlined : Icons.do_not_disturb_rounded;
      onTap = canJoin ? () => _joinRequest(e) : null;
      if (!canJoin) btnColor = Colors.grey.shade400;
    } else {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.lock_outline_rounded, size: 16, color: Colors.grey.shade400),
            const SizedBox(width: 8),
            Text(
              isBusy ? 'มีผู้เชี่ยวชาญท่านอื่นรับแล้ว' : 'ไม่สามารถดำเนินการได้',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
            ),
          ],
        ),
      );
    }

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: btnColor,
          foregroundColor: Colors.white,
          disabledBackgroundColor: Colors.grey.shade200,
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _avatar(ConsultationEntry e) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.primary.withOpacity(0.1),
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipOval(
        child: e.patientAvatar != null && e.patientAvatar!.isNotEmpty
            ? CachedNetworkImage(
                imageUrl: e.patientAvatar!,
                fit: BoxFit.cover,
                placeholder: (context, url) => const Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
                errorWidget: (context, url, error) => const Icon(Icons.person, color: Colors.grey),
              )
            : Center(
                child: Text(
                  e.patientName.isNotEmpty ? e.patientName[0].toUpperCase() : 'P',
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                  ),
                ),
              ),
      ),
    );
  }

  Widget _statusBadge(String status) {
    Color color;
    String label;
    switch (status) {
      case 'pending':
        color = const Color(0xFFF2A93B);
        label = 'รอดำเนินการ';
        break;
      case 'in_progress':
        color = const Color(0xFF6ED1A6);
        label = 'กำลังดำเนินการ';
        break;
      case 'completed':
        color = const Color(0xFF4A8B2C);
        label = 'เสร็จสิ้น';
        break;
      default:
        color = Colors.grey;
        label = status;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value, Color color) {
    return Row(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 14, color: color),
        ),
        const SizedBox(width: 12),
        Text(
          '$label: ',
          style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.assignment_outlined,
            size: 64,
            color: Colors.grey.shade300,
          ),
          const SizedBox(height: 16),
          Text(
            _searchQuery.isNotEmpty
                ? 'ไม่พบผลการค้นหา "$_searchQuery"'
                : 'ยังไม่มีคำร้องขอ',
            style: TextStyle(color: Colors.grey.shade500, fontSize: 15),
          ),
          const SizedBox(height: 8),
          Text(
            'รูดหน้าลงเพื่อโหลดข้อมูลใหม่',
            style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
          ),
        ],
      ),
    );
  }

  void _showStatusSheet(ConsultationEntry entry) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'อัปเดตสถานะ: ${entry.patientName}',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            const SizedBox(height: 12),
            ...['pending', 'in_progress', 'completed'].map((s) {
              final cfg = _statusConfig(s);
              final color = cfg['color'] as Color;
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
                title: Text(cfg['label'] as String),
                trailing: entry.status == s
                    ? const Icon(Icons.check, color: AppColors.primary)
                    : null,
                onTap: () async {
                  Navigator.pop(ctx);
                  await _repo.updateStatus(entry.id, s);
                  _loadData();
                },
              );
            }),
          ],
        ),
      ),
    );
  }

  void _openChat(ConsultationEntry entry) {
    Navigator.pushNamed(
      context,
      '/chart-board',
      arguments: entry,
    );
  }

  Map<String, dynamic> _statusConfig(String status) {
    switch (status) {
      case 'in_progress':
        return {'label': 'กำลังดำเนินการ', 'color': const Color(0xFF6ED1A6)};
      case 'completed':
        return {'label': 'เสร็จสิ้น', 'color': const Color(0xFF4A8B2C)};
      default:
        return {'label': 'รอดำเนินการ', 'color': const Color(0xFFF2A93B)};
    }
  }
}

