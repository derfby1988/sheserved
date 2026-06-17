import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:intl/intl.dart';
import 'package:sheserved/shared/widgets/tlz_bottom_navigation_bar.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../services/service_locator.dart';
import '../../../../services/auth_service.dart';
import '../../../../features/auth/data/repositories/user_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../chat/data/models/chat_models.dart';
import '../../data/repositories/consultation_repository.dart';
import '../../data/models/consultation_entry.dart';
import '../../../admin/models/profession.dart';
import '../../../../shared/widgets/widgets.dart';
// NOTE: expert_chat_room_page.dart is deprecated; use ChartBoardPage via /chart-board
import '../widgets/dashboard/availability_toggle_button.dart';
import '../widgets/dashboard/availability_banner.dart';

class HealthProgramRequestDashboard extends StatefulWidget {
  final String? initialFocusId;
  const HealthProgramRequestDashboard({super.key, this.initialFocusId});

  @override
  State<HealthProgramRequestDashboard> createState() =>
      _HealthProgramRequestDashboardState();
}

final RouteObserver<ModalRoute<void>> dashboardRouteObserver =
    RouteObserver<ModalRoute<void>>();

class _HealthProgramRequestDashboardState
    extends State<HealthProgramRequestDashboard>
    with
        SingleTickerProviderStateMixin,
        WidgetsBindingObserver,
        RouteAware {
  ConsultationRepository get _repo =>
      ServiceLocator.instance.consultationRepository;
  UserRepository get _userRepo => UserRepository(Supabase.instance.client);

  final _currentUser = AuthService.instance.currentUser;

  // ── Per-Tab Pagination State ────────────────────────────────────────────────
  final Map<String, List<ConsultationEntry>> _entriesByTab = {};
  final Map<String, int> _pageByTab = {
    'all': 0, 'pending': 0, 'in_progress': 0, 'completed': 0
  };
  final Map<String, bool> _hasMoreByTab = {
    'all': true, 'pending': true, 'in_progress': true, 'completed': true
  };
  Map<String, int> _statusCounts = {
    'all': 0, 'pending': 0, 'in_progress': 0, 'completed': 0
  };
  String _activeTab = 'pending';
  bool _isLoading = false;
  String _searchQuery = '';
  bool _isNavBarVisible = true;

  List<String> _myPackageIds = []; // package IDs ที่ตรงกับอาชีพ provider
  List<Profession> _professions = []; // อาชีพทั้งหมดจาก admin settings
  bool _isProvider = false;
  String _availabilityStatus = 'online'; // สถานะตัวเอง
  int _activeJobCount = 0; // จำนวนงานที่กำลังทำอยู่
  static const int _maxConcurrentJobs = 2; // จำกัดงานพร้อมกันสูงสุด

  Set<String> _finishedConsultationIds = {}; // consultation_ids ที่ผู้ใช้จบงานแล้ว
  Map<String, Map<String, int>> _expertCompletionCounts = {}; // consultation_id → {total, finished}

  StreamSubscription? _subscription;
  String? _highlightedId;
  final Map<String, GlobalKey> _cardKeys = {};
  final ScrollController _scrollController = ScrollController();

  static const _tabs = [
    {'value': 'all', 'label': 'ทั้งหมด'},
    {'value': 'pending', 'label': 'รอดำเนินการ'},
    {'value': 'in_progress', 'label': 'กำลังดำเนินการ'},
    {'value': 'completed', 'label': 'เสร็จสิ้น'},
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    dashboardRouteObserver.subscribe(this, ModalRoute.of(context)!);
  }

  @override
  void dispose() {
    dashboardRouteObserver.unsubscribe(this);
    WidgetsBinding.instance.removeObserver(this);
    _subscription?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final user = _currentUser;
    if (user == null) return;

    try {
      debugPrint('Dashboard: Initializing for user ${user.id}');

      // ตรวจว่าเป็น provider หรือเปล่า
      _isProvider =
          user.professionId != null &&
          user.professionId != '00000000-0000-0000-0000-000000000001';

      // โหลดจำนวนงานที่กำลังทำอยู่ (สำหรับ provider)
      if (_isProvider) {
        _activeJobCount = await _repo.getActiveInProgressConsultationCount(user.id);
      }

      // โหลด consultation_ids ที่ผู้ใช้จบงานแล้ว
      _finishedConsultationIds = await _repo.getFinishedConsultationIds(user.id);
      debugPrint('Dashboard: finishedConsultationIds=${_finishedConsultationIds.length}');

      // โหลดข้อมูลพื้นฐานขนานกัน
      await Future.wait([
        _userRepo
            .getAvailabilityStatus(user.id)
            .then((s) => _availabilityStatus = s),
        if (_isProvider && user.professionId != null)
          _repo
              .getPackageIdsForProfession(user.professionId!)
              .then((ids) => _myPackageIds = ids),
        ServiceLocator.instance.professionRepository
            .getAllProfessions()
            .then((profs) => _professions = profs),
      ]).timeout(const Duration(seconds: 15));

      debugPrint('Dashboard: _init done — _isProvider=$_isProvider, _availabilityStatus=$_availabilityStatus, _myPackageIds=$_myPackageIds');

      // Safety net: ถ้า busy แต่ไม่มีงาน in_progress → reset เป็น online
      await _fixStaleBusyStatusIfNeeded();

      // โหลด counts + หน้าแรกของ active tab
      await _loadCounts();
      await _loadTab(_activeTab);
      _subscribeToChanges();

      // ตั้งค่า scroll listener สำหรับ load more
      _scrollController.addListener(_onScroll);
    } catch (e) {
      debugPrint('Dashboard init error: $e');
    }
  }

  /// โหลดจำนวนรายการต่อ status (สำหรับ stat chips)
  Future<void> _loadCounts() async {
    try {
      final counts = await _repo.getStatusCounts(
        packageIds: (_isProvider && _myPackageIds.isNotEmpty)
            ? _myPackageIds
            : null,
      );
      if (mounted) setState(() => _statusCounts = counts);
    } catch (e) {
      debugPrint('Dashboard _loadCounts error: $e');
    }
  }

  /// โหลดข้อมูลเฉพาะ tab ที่เลือก (pagination)
  Future<void> _loadTab(String tab, {bool refresh = false}) async {
    if (_isLoading) return;

    if (refresh) {
      _pageByTab[tab] = 0;
      _hasMoreByTab[tab] = true;
      _entriesByTab[tab] = [];
    }

    if (!_hasMoreByTab[tab]!) return;

    setState(() => _isLoading = true);

    try {
      final page = _pageByTab[tab]!;
      final raw = await _repo.getRequestsByStatus(
        status: tab == 'all' ? null : tab,
        page: page,
        pageSize: 15,
        packageIds: (_isProvider && _myPackageIds.isNotEmpty)
            ? _myPackageIds
            : null,
      );

      if (raw.length < 15) _hasMoreByTab[tab] = false;

      final entries = raw.map(ConsultationEntry.fromMap).toList();

      // โหลดจำนวน expert ที่จบงานแล้วสำหรับทุก consultation ใน batch นี้
      final entryIds = entries.map((e) => e.id).toList();
      final consultationToPackageIds = {for (var e in entries) e.id: e.packageId ?? ''};
      debugPrint('Dashboard: _loadTab fetching expert counts for ${entryIds.length} entries');
      if (entryIds.isNotEmpty) {
        try {
          final counts = await _repo.getExpertCompletionCounts(entryIds, consultationToPackageIds);
          debugPrint('Dashboard: _loadTab expertCounts=$counts');
          if (mounted) {
            setState(() {
              _expertCompletionCounts.addAll(counts);
            });
          }
        } catch (e) {
          debugPrint('Dashboard: getExpertCompletionCounts error: $e');
        }
      }

      if (mounted) {
        setState(() {
          _entriesByTab[tab] = [...?_entriesByTab[tab], ...entries];
          _pageByTab[tab] = page + 1;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Dashboard _loadTab error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Scroll listener → load more เฉพาะ tab ปัจจุบัน
  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      if (!_isLoading && _hasMoreByTab[_activeTab]!) {
        _loadTab(_activeTab);
      }
    }
  }

  /// เปลี่ยน tab → โหลด tab นั้น (ถ้ายังไม่มีข้อมูล)
  Future<void> _switchTab(String tab) async {
    setState(() => _activeTab = tab);
    if (_entriesByTab[tab]?.isEmpty ?? true) {
      await _loadTab(tab);
    }
  }

  void _subscribeToChanges() {
    final stream = (_isProvider && _myPackageIds.isNotEmpty)
        ? _repo.watchRequestsForProfession(_myPackageIds)
        : _repo.watchAllRequestsWithUserInfo();

    _subscription = stream.listen((_) async {
      // Realtime มา → reload counts + reload active tab
      await _loadCounts();
      await _loadTab(_activeTab, refresh: true);
    });
  }

  // ── App Lifecycle Observer ─────────────────────────────────────────────────
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      debugPrint('[Dashboard] App resumed → refreshing data');
      _loadCounts();
      _loadTab(_activeTab, refresh: true);
    }
  }

  // ── Route Observer (กลับมาจากหน้าอื่น เช่น ห้องแชท) ───────────────────────
  @override
  void didPopNext() {
    debugPrint('[Dashboard] Returned from another page → refreshing data');
    _loadCounts();
    if (_isProvider && _currentUser != null) {
      // โหลด finished IDs ก่อน แล้วค่อย _loadTab เพื่อให้ UI rebuild ด้วยข้อมูลถูกต้อง
      _repo.getFinishedConsultationIds(_currentUser!.id).then((ids) {
        if (mounted) {
          setState(() => _finishedConsultationIds = ids);
          debugPrint('[Dashboard] didPopNext: _finishedConsultationIds=${_finishedConsultationIds.length}');
        }
        _loadTab(_activeTab, refresh: true);
      });
      _repo.getActiveInProgressConsultationCount(_currentUser!.id).then((count) {
        if (mounted) setState(() => _activeJobCount = count);
      });
    } else {
      _loadTab(_activeTab, refresh: true);
    }
  }

  @override
  void didPushNext() {}

  @override
  void didPush() {}

  @override
  void didPop() {}

  /// กรอง search ภายใน tab ปัจจุบัน (client-side)
  /// สำหรับแถบ 'in_progress' เรียงงานของตัวเอง (isMyJob) ขึ้นก่อน
  List<ConsultationEntry> _getFilteredEntries() {
    final entries = _entriesByTab[_activeTab] ?? [];
    final q = _searchQuery.toLowerCase();

    var result = entries;
    if (q.isNotEmpty) {
      result = entries.where((e) {
        return e.patientName.toLowerCase().contains(q) ||
            e.packageName.toLowerCase().contains(q) ||
            e.bodyArea.toLowerCase().contains(q);
      }).toList();
    }

    // แถบ 'in_progress': งานของตัวเอง (มีปุ่มเข้าห้องแชท) ขึ้นก่อน
    if (_activeTab == 'in_progress') {
      final myId = _currentUser?.id;
      result.sort((a, b) {
        final aMine = a.providerId == myId;
        final bMine = b.providerId == myId;
        if (aMine && !bMine) return -1;
        if (!aMine && bMine) return 1;
        return b.requestedAt.compareTo(a.requestedAt); // ใหม่ → เก่า
      });
    }

    // แถบ 'completed': งานที่จบล่าสุดขึ้นก่อน (เรียงตาม updatedAt)
    if (_activeTab == 'completed') {
      result.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    }

    return result;
  }

  int get _total => _statusCounts['all'] ?? 0;
  int get _pending => _statusCounts['pending'] ?? 0;
  int get _inProgress => _statusCounts['in_progress'] ?? 0;
  int get _completed => _statusCounts['completed'] ?? 0;

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

    // ตรวจสอบว่ารับงานเต็มโควต้าหรือไม่
    if (_activeJobCount >= _maxConcurrentJobs) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: AppColors.error),
                const SizedBox(width: 8),
                const Text('ไม่สามารถรับงานเพิ่ม'),
              ],
            ),
            content: Text(
              'คุณกำลังทำงาน $_activeJobCount / $_maxConcurrentJobs งาน\n'
              'กรุณาจบงานปัจจุบันก่อนรับงานใหม่',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('เข้าใจแล้ว'),
              ),
            ],
          ),
        );
      }
      return;
    }

    try {
      debugPrint('Dashboard: _joinRequest starting for entry=${entry.id}');
      // 1. พยายาม Assign provider เข้า expert group slot (ระบบใหม่ Phase 1)
      if (entry.packageId != null && user.professionId != null) {
        try {
          debugPrint('Dashboard: trying assignProviderToGroup');
          await _repo.assignProviderToGroup(
            consultationId: entry.id,
            providerId: user.id,
            packageId: entry.packageId!,
            professionId: user.professionId!,
          );
          debugPrint('Dashboard: assignProviderToGroup success');
        } catch (e) {
          // Fallback: ใช้ระบบเดิม (direct assign) ถ้า expert group ไม่ตรง
          debugPrint('Dashboard: assignProviderToGroup failed ($e), fallback to assignProvider');
          await _repo.assignProvider(
            requestId: entry.id,
            providerId: user.id,
          );
          debugPrint('Dashboard: assignProvider fallback success');
          // Sync provider เข้า consultation_room_experts เพื่อให้ banner แสดง joined
          await _repo.syncProviderToRoomExperts(
            consultationId: entry.id,
            providerId: user.id,
            professionId: user.professionId,
          );
          debugPrint('Dashboard: syncProviderToRoomExperts fallback success');
        }
      } else {
        // ไม่มี packageId หรือ professionId → ใช้ระบบ assign ตรง
        debugPrint('Dashboard: no packageId/professionId, using direct assign');
        await _repo.assignProvider(
          requestId: entry.id,
          providerId: user.id,
        );
        debugPrint('Dashboard: direct assign success');
        // Sync provider เข้า consultation_room_experts เพื่อให้ banner แสดง joined
        await _repo.syncProviderToRoomExperts(
          consultationId: entry.id,
          providerId: user.id,
          professionId: user.professionId,
        );
        debugPrint('Dashboard: syncProviderToRoomExperts direct success');
      }

      // 1.5 อัปเดตสถานะ request ให้เป็น in_progress
      debugPrint('Dashboard: updating status to in_progress');
      await _repo.updateStatus(entry.id, 'in_progress');

      // 2. เปลี่ยนสถานะตัวเองเป็น busy + อัปเดตจำนวนงาน
      debugPrint('Dashboard: setting availability to busy');
      await _userRepo.setAvailabilityStatus(user.id, 'busy');
      if (mounted) setState(() {
        _availabilityStatus = 'busy';
        _activeJobCount++;
      });

      // 3. นำทางเข้าห้องแชท
      debugPrint('Dashboard: navigating to chat');
      if (mounted) {
        _openChat(entry);
      }
    } catch (e, stack) {
      debugPrint('Dashboard: _joinRequest FAILED: $e');
      debugPrint(stack.toString());
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

  // ─── Safety net: ถ้า busy แต่ไม่มีงาน in_progress → reset เป็น online ──────
  Future<void> _fixStaleBusyStatusIfNeeded() async {
    if (_availabilityStatus != 'busy' || !_isProvider) return;

    try {
      final hasActive = await _repo.hasActiveInProgressConsultation(_currentUser!.id);
      if (!hasActive) {
        await _userRepo.setAvailabilityStatus(_currentUser!.id, 'online');
        if (mounted) setState(() {
          _availabilityStatus = 'online';
          _activeJobCount = 0;
        });
        debugPrint('Dashboard: Auto-reset stale busy → online (no active consultation)');
      }
    } catch (e) {
      debugPrint('Dashboard: _fixStaleBusyStatusIfNeeded error: $e');
    }
  }

  // ─── Provider เปลี่ยนสถานะตัวเอง ────────────────────────────────────────────
  Future<void> _toggleAvailability() async {
    final user = _currentUser;
    if (user == null) {
      debugPrint('Dashboard: _toggleAvailability skipped — user null');
      return;
    }

    final newStatus = _availabilityStatus == 'busy' ? 'online' : 'busy';
    debugPrint('Dashboard: _toggleAvailability current=$_availabilityStatus → new=$newStatus');
    try {
      await _userRepo.setAvailabilityStatus(user.id, newStatus);
      debugPrint('Dashboard: setAvailabilityStatus success');
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
    } catch (e) {
      debugPrint('Dashboard: _toggleAvailability FAILED: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('เปลี่ยนสถานะไม่สำเร็จ: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      backgroundColor: AppColors.background,
      drawer: const TlzDrawer(),
      body: Column(
        children: [
          // Fixed top bar (search + back button) — not scrollable
          _buildFixedTopBar(),
          // Scrollable content
          Expanded(
            child: NotificationListener<ScrollNotification>(
              onNotification: (notification) {
                if (notification is UserScrollNotification) {
                  if (notification.direction == ScrollDirection.reverse) {
                    if (_isNavBarVisible) {
                      setState(() => _isNavBarVisible = false);
                    }
                  } else if (notification.direction == ScrollDirection.forward) {
                    if (!_isNavBarVisible) {
                      setState(() => _isNavBarVisible = true);
                    }
                  }
                }
                return false;
              },
              child: _isLoading ? _buildLoading() : _buildBody(),
            ),
          ),
        ],
      ),
      bottomNavigationBar: TlzBottomNavigationBar(
        isVisible: _isNavBarVisible,
        currentIndex: -1, // Dashboard ไม่ใช่ tab หลัก → ไม่ highlight อันไหน ให้ tap ได้ทุกปุ่ม
        onIndexChanged: (index) {
          if (index == 2) return;
          Navigator.pushNamedAndRemoveUntil(
            context,
            '/main-app',
            (route) => route.isFirst,
            arguments: {'index': index},
          );
        },
        onAddPressed: () {
          Navigator.pushNamed(context, '/emergency-live');
        },
      ),
    );
  }

  // ─── Fixed Top Bar (Search + Back) — not part of scrollable ───
  Widget _buildFixedTopBar() {
    return Container(
      color: AppColors.primary,
      child: SafeArea(
        bottom: false,
        child: TlzAppTopBar.onPrimary(
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
      ),
    );
  }

  // ─── Gradient Header (part of scrollable content) ────
  Widget _buildHeaderContent() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primary, Color(0xFF5A9B08), Color(0xFF437A05)],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
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
                  AvailabilityToggleButton(
                    status: _availabilityStatus,
                    onToggle: _toggleAvailability,
                  ),
                  const SizedBox(width: 6),
                  GestureDetector(
                    onTap: () async {
                      await _loadCounts();
                      await _loadTab(_activeTab, refresh: true);
                    },
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
                _statChip(
                  'ทั้งหมด',
                  _total,
                  Icons.list_alt,
                  Colors.white,
                  onTap: () => _switchTab('all'),
                  isActive: _activeTab == 'all',
                ),
                const SizedBox(width: 8),
                _statChip(
                  'รอดำเนินการ',
                  _pending,
                  Icons.pending_outlined,
                  AppColors.warning,
                  onTap: () => _switchTab('pending'),
                  isActive: _activeTab == 'pending',
                ),
                const SizedBox(width: 8),
                _statChip(
                  'กำลังดำเนินการ',
                  _inProgress,
                  Icons.forum_outlined,
                  AppColors.info,
                  onTap: () => _switchTab('in_progress'),
                  isActive: _activeTab == 'in_progress',
                ),
                const SizedBox(width: 8),
                _statChip(
                  'เสร็จสิ้น',
                  _completed,
                  Icons.check_circle_outline,
                  AppColors.success,
                  onTap: () => _switchTab('completed'),
                  isActive: _activeTab == 'completed',
                ),
              ],
            ),
            if (_isProvider) ...[
              const SizedBox(height: 8),
              AvailabilityBanner(status: _availabilityStatus),
            ],
            if (!_isProvider) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: GestureDetector(
                  onTap: () async {
                    await _loadCounts();
                    await _loadTab(_activeTab, refresh: true);
                  },
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
    );
  }

  Widget _statChip(String label, int count, IconData icon, Color accent, {VoidCallback? onTap, bool isActive = false}) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
          decoration: BoxDecoration(
            color: isActive ? Colors.white.withOpacity(0.35) : Colors.white.withOpacity(0.15),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isActive ? Colors.white.withOpacity(0.6) : Colors.white.withOpacity(0.25),
              width: isActive ? 1.5 : 1,
            ),
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
                    color: Colors.white.withOpacity(0.9),
                    fontSize: 9,
                    fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                ),
              ),
            ],
          ),
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
    final entries = _getFilteredEntries();

    return RefreshIndicator(
      onRefresh: () async {
        await _loadCounts();
        await _loadTab(_activeTab, refresh: true);
        if (_isProvider && _currentUser != null) {
          final count = await _repo.getActiveInProgressConsultationCount(_currentUser!.id);
          if (mounted) setState(() => _activeJobCount = count);
        }
      },
      color: AppColors.primary,
      child: CustomScrollView(
        controller: _scrollController,
        slivers: [
          // ── Gradient Header with Stat Chips + Availability Banner (scrolls away) ──
          SliverToBoxAdapter(child: _buildHeaderContent()),

          // ── Active Jobs Banner (scrolls away) ──
          if (_isProvider)
            SliverToBoxAdapter(child: _buildActiveJobsBanner()),

          // ── Search Bar (scrolls away) ──
          SliverToBoxAdapter(
            child: Container(
              color: AppColors.background,
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
              child: _buildSearchBarOnly(),
            ),
          ),

          // ── Status Tabs (sticky when reaching top) ──
          SliverPersistentHeader(
            pinned: true,
            delegate: _StatusTabsHeaderDelegate(
              child: Container(
                color: AppColors.background,
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: _buildStatusTabsOnly(),
              ),
            ),
          ),

          // ── Cards ──
          if (entries.isEmpty && !_isLoading)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _buildEmpty(),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (ctx, i) {
                    if (i == entries.length) {
                      return const Padding(
                        padding: EdgeInsets.all(16),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    return _buildCard(entries[i], i);
                  },
                  childCount: entries.length + (_isLoading ? 1 : 0),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Banner แจ้งเตือนจำนวนงานที่กำลังทำอยู่
  Widget _buildActiveJobsBanner() {
    if (_activeJobCount == 0) return const SizedBox.shrink();

    final isAtLimit = _activeJobCount >= _maxConcurrentJobs;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isAtLimit
            ? const Color(0xFFFFF3E0)
            : const Color(0xFFE8F5E9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isAtLimit
              ? const Color(0xFFFF9800).withOpacity(0.5)
              : const Color(0xFF4CAF50).withOpacity(0.3),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isAtLimit ? Icons.warning_amber_rounded : Icons.work_outline,
            color: isAtLimit ? const Color(0xFFFF9800) : const Color(0xFF4CAF50),
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'งานที่กำลังดำเนินการ: $_activeJobCount / $_maxConcurrentJobs',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: isAtLimit ? const Color(0xFFE65100) : const Color(0xFF2E7D32),
                  ),
                ),
                if (isAtLimit)
                  const Text(
                    'คุณรับงานเต็มโควต้าแล้ว กรุณาจบงานปัจจุบันก่อนรับงานใหม่',
                    style: TextStyle(
                      fontSize: 11,
                      color: Color(0xFFE65100),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBarOnly() {
    return Container(
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
        onChanged: (v) => setState(() => _searchQuery = v),
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
    );
  }

  Widget _buildStatusTabsOnly() {
    return SizedBox(
      height: 32,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _tabs.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (ctx, i) {
          final tab = _tabs[i];
          final active = _activeTab == tab['value'];
          return GestureDetector(
            onTap: () => _switchTab(tab['value']!),
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
    );
  }

  Widget _buildCard(ConsultationEntry e, int index) {
    final myUserId = _currentUser?.id;
    final isMyJob = e.providerId == myUserId;
    final isBusy = e.isAssigned && !isMyJob; // งานถูก provider อื่นรับแล้ว
    final isFinished = e.status == 'completed' || _finishedConsultationIds.contains(e.id);

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
                      // Badge: ตรงกับอาชีพ provider หรือไม่
                      if (_isProvider && e.packageId != null && _myPackageIds.contains(e.packageId)) ...[
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.success.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppColors.success.withOpacity(0.3)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.verified, size: 10, color: AppColors.success),
                              const SizedBox(width: 3),
                              Text(
                                'ตรงกับคุณ',
                                style: TextStyle(
                                  fontSize: 9,
                                  color: AppColors.success,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ] else if (_isProvider && !isMyJob && e.status == 'pending') ...[
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'ไม่ตรงอาชีพ',
                            style: TextStyle(
                              fontSize: 9,
                              color: Colors.grey.shade500,
                            ),
                          ),
                        ),
                      ],
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
                  // แสดงจำนวนผู้เชี่ยวชาญที่ยังไม่จบงาน (เฉพาะการ์ดที่ผู้ใช้จบงานแล้ว)
                  if (isFinished) ...[
                    const SizedBox(height: 8),
                    _buildExpertCountRow(e),
                  ],
                ],
              ),
            ),
            // Chip อาชีพที่ต้องการ
            _buildProfessionChipRow(e),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
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
    // สำหรับ provider ที่ยังไม่ได้รับงาน และงานตรงกับอาชีพ → แสดง 2 ปุ่ม: รับงาน + ดูรายละเอียด
    final bool isMatching = _isProvider &&
        e.packageId != null &&
        _myPackageIds.contains(e.packageId) &&
        !isMyJob &&
        e.status == 'pending' &&
        !isBusy;
    final isFinished = e.status == 'completed' || _finishedConsultationIds.contains(e.id);
    debugPrint('Dashboard: _buildActionRow entry=${e.id}, _finishedIds=$_finishedConsultationIds, contains=${_finishedConsultationIds.contains(e.id)}, status=${e.status}, isFinished=$isFinished, isMyJob=$isMyJob');

    if (isMatching) {
      final canJoin = _availabilityStatus != 'busy' && _activeJobCount < _maxConcurrentJobs;
      final isAtJobLimit = _activeJobCount >= _maxConcurrentJobs;
      return Row(
        children: [
          // ปุ่ม ดูรายละเอียด (เปิดในโหมดดูอย่างเดียว ไม่สามารถดำเนินการได้)
          Expanded(
            flex: 2,
            child: OutlinedButton(
              onPressed: () => _openChat(e, readOnly: true),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: BorderSide(color: AppColors.primary.withOpacity(0.5)),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.visibility_outlined, size: 16),
                  SizedBox(width: 6),
                  Text(
                    'ดูรายละเอียด',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          // ปุ่ม รับงาน
          Expanded(
            flex: 3,
            child: ElevatedButton(
              onPressed: canJoin ? () => _joinRequest(e) : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6ED1A6),
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.grey.shade300,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    canJoin ? Icons.pan_tool_alt_outlined : Icons.do_not_disturb_rounded,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    canJoin
                        ? 'รับงานนี้'
                        : isAtJobLimit
                            ? 'รับงานเต็มแล้ว'
                            : 'คุณไม่ว่าง',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    // กรณีอื่นๆ (single button เหมือนเดิม)
    String label;
    IconData icon;
    VoidCallback? onTap;
    Color btnColor = const Color(0xFF6ED1A6);

    if (!_isProvider) {
      label = 'เข้าห้องแชทผู้ป่วย';
      icon = Icons.chat_bubble_outline;
      onTap = () => _openChat(e);
    } else if (isFinished) {
      // Provider จบงานแล้ว แต่ consultation ยังไม่ปิด → ปุ่มเทา
      label = 'คุณจบงานแล้ว';
      icon = Icons.check_circle_outline;
      onTap = () => _openChat(e);
      btnColor = Colors.grey.shade500;
    } else if (isMyJob) {
      label = 'เข้าห้องแชทผู้ป่วย';
      icon = Icons.chat_bubble_outline;
      onTap = () => _openChat(e);
      btnColor = AppColors.alertGold;
    } else if (e.status == 'pending' && !isBusy) {
      final canJoin = _availabilityStatus != 'busy' && _activeJobCount < _maxConcurrentJobs;
      final isAtJobLimit = _activeJobCount >= _maxConcurrentJobs;
      label = canJoin
          ? 'รับงานนี้'
          : isAtJobLimit
              ? 'รับงานเต็มแล้ว'
              : 'คุณไม่ว่างอยู่';
      icon = canJoin ? Icons.pan_tool_alt_outlined : Icons.do_not_disturb_rounded;
      onTap = canJoin ? () => _joinRequest(e) : null;
      if (!canJoin) btnColor = Colors.grey.shade400;
    } else {
      // กำหนดข้อความตามสาเหตุที่ถูกบล็อก
      String lockMessage;
      IconData lockIcon = Icons.lock_outline_rounded;
      if (isMyJob) {
        lockMessage = 'เข้าห้องแชท'; // ไม่ควรถึงตรงนี้เพราะ isMyJob ถูกจัดการข้างต้น
      } else if (e.status == 'in_progress') {
        lockMessage = 'ดำเนินการโดยผู้เชี่ยวชาญท่านอื่น';
        lockIcon = Icons.person_off_outlined;
      } else if (isBusy) {
        lockMessage = 'มีผู้เชี่ยวชาญท่านอื่นรับแล้ว';
      } else if (e.packageId != null && !_myPackageIds.contains(e.packageId)) {
        lockMessage = 'ไม่ตรงกับอาชีพของคุณ';
      } else {
        lockMessage = 'ไม่สามารถดำเนินการได้';
      }

      return Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(lockIcon, size: 16, color: Colors.grey.shade400),
            const SizedBox(width: 8),
            Text(
              lockMessage,
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
          foregroundColor: btnColor == AppColors.alertGold ? Colors.black87 : Colors.white,
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

  /// หา profession ที่ตรงกับแพ็คเกจ (จาก _professions ที่โหลดมา)
  Profession? _findProfessionForPackage(String? packageId) {
    if (packageId == null || _professions.isEmpty) return null;
    // หา profession ตาม professionId ของ provider (ถ้า packageId อยู่ใน _myPackageIds)
    final user = _currentUser;
    if (user?.professionId != null && _myPackageIds.contains(packageId)) {
      return _professions.firstWhere(
        (p) => p.id == user!.professionId,
        orElse: () => _professions.first,
      );
    }
    return null;
  }

  /// แสดง chip อาชีพที่ต้องการบนการ์ด
  Widget _buildProfessionChipRow(ConsultationEntry e) {
    final prof = _findProfessionForPackage(e.packageId);
    final isMatching = e.packageId != null && _myPackageIds.contains(e.packageId);

    if (!_isProvider) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          if (isMatching && prof != null) ...[
            Chip(
              avatar: Icon(
                _parseIconName(prof.iconName),
                size: 16,
                color: _hexToColor(prof.colorHex) ?? AppColors.primary,
              ),
              label: Text(
                prof.name,
                style: TextStyle(
                  fontSize: 11,
                  color: _hexToColor(prof.colorHex) ?? AppColors.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              backgroundColor: (_hexToColor(prof.colorHex) ?? AppColors.primary).withOpacity(0.1),
              side: BorderSide(
                color: (_hexToColor(prof.colorHex) ?? AppColors.primary).withOpacity(0.3),
              ),
              padding: EdgeInsets.zero,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ] else if (!isMatching && e.status == 'pending') ...[
            Chip(
              avatar: const Icon(Icons.block, size: 14, color: Colors.grey),
              label: Text(
                'ไม่ตรงอาชีพคุณ',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              ),
              backgroundColor: Colors.grey.shade100,
              side: BorderSide(color: Colors.grey.shade300),
              padding: EdgeInsets.zero,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ],
        ],
      ),
    );
  }

  /// แปลง icon name string → IconData
  IconData _parseIconName(String? iconName) {
    switch (iconName?.toLowerCase()) {
      case 'medical_services':
        return Icons.medical_services;
      case 'medication':
      case 'medication_liquid':
        return Icons.medication;
      case 'psychology':
        return Icons.psychology;
      case 'vaccines':
        return Icons.vaccines;
      case 'local_hospital':
        return Icons.local_hospital;
      case 'health_and_safety':
        return Icons.health_and_safety;
      case 'science':
        return Icons.science;
      default:
        return Icons.work_outline;
    }
  }

  /// แปลง hex color string → Flutter Color
  Color? _hexToColor(String? hex) {
    if (hex == null || hex.isEmpty) return null;
    try {
      final clean = hex.replaceAll('#', '');
      if (clean.length == 6) return Color(int.parse('FF$clean', radix: 16));
      if (clean.length == 8) return Color(int.parse(clean, radix: 16));
    } catch (_) {}
    return null;
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

  /// แสดงแถวจำนวนผู้เชี่ยวชาญที่ยังไม่จบงาน
  Widget _buildExpertCountRow(ConsultationEntry e) {
    final counts = _expertCompletionCounts[e.id];

    // แสดงเฉพาะเมื่อมีข้อมูลจริง (จาก consultation_room_experts หรือ package)
    if (counts != null && (counts['total'] ?? 0) > 0) {
      final total = counts['total']!;
      var finished = counts['finished'] ?? 0;

      // ถ้า consultation_room_experts ว่าง แต่ user ปัจจุบันจบงานแล้ว ให้บวกเข้าไป
      // user จบงานแล้วถ้าอยู่ใน _finishedConsultationIds หรือ consultation status เป็น completed
      final currentUserFinished = _finishedConsultationIds.contains(e.id) || e.status == 'completed';
      if (currentUserFinished && finished == 0) {
        finished = 1;
      }

      final remaining = total - finished;

      final value = remaining <= 0
          ? '$finished/$total จบแล้ว'
          : '$finished/$total จบแล้ว (รออีก $remaining คน)';
      final color = remaining <= 0 ? AppColors.success : AppColors.warning;

      return _infoRow(
        Icons.people_outline,
        'ผู้เชี่ยวชาญ',
        value,
        color,
      );
    }

    // ไม่มีข้อมูล → ไม่แสดงอะไร (ป้องกันการแสดงข้อมูลผิด)
    return const SizedBox.shrink();
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
                  await _loadCounts();
                  await _loadTab(_activeTab, refresh: true);
                },
              );
            }),
          ],
        ),
      ),
    );
  }

  void _openChat(ConsultationEntry entry, {bool readOnly = false}) {
    final hasFinished = entry.status == 'completed' || _finishedConsultationIds.contains(entry.id);
    Navigator.pushNamed(
      context,
      '/chart-board',
      arguments: {
        'entry': entry,
        'readOnly': readOnly,
        'hasFinished': hasFinished,
      },
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

// ─── SliverPersistentHeaderDelegate สำหรับ Status Tabs (sticky) ───
class _StatusTabsHeaderDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;

  _StatusTabsHeaderDelegate({required this.child});

  @override
  double get minExtent => 44; // 32 (tab height) + 4 (top padding) + 8 (bottom padding)

  @override
  double get maxExtent => 44;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return child;
  }

  @override
  bool shouldRebuild(covariant _StatusTabsHeaderDelegate oldDelegate) {
    return oldDelegate.child != child;
  }
}
