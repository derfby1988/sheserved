import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../features/auth/data/repositories/user_repository.dart';
import '../../../../features/admin/models/profession.dart';
import '../../../../core/constants/app_colors.dart';

/// Widget แสดงจำนวนผู้ให้บริการ online แบบ Real-time
/// อัปเดตอัตโนมัติผ่าน Supabase Realtime ทุกครั้งที่ last_seen_at เปลี่ยน
class OnlineProvidersBadge extends StatefulWidget {
  /// แสดงเฉพาะ professionId นี้ (null = แสดงรวมทั้งหมด)
  final String? professionId;

  /// ชื่อกลุ่มที่แสดง เช่น "ผู้เชี่ยวชาญ"
  final String label;

  /// สีหลักของ badge
  final Color? color;

  /// ขนาดเล็ก (compact mode)
  final bool compact;

  /// สีตัวอักษร (ถ้า null จะใช้ตามสถานะ)
  final Color? textColor;

  const OnlineProvidersBadge({
    super.key,
    this.professionId,
    this.label = 'ผู้ให้บริการ',
    this.color,
    this.compact = false,
    this.textColor,
  });

  @override
  State<OnlineProvidersBadge> createState() => _OnlineProvidersBadgeState();
}

class _OnlineProvidersBadgeState extends State<OnlineProvidersBadge>
    with SingleTickerProviderStateMixin {
  final UserRepository _repo = UserRepository(Supabase.instance.client);

  int _onlineCount = 0;
  bool _isLoading = true;
  StreamSubscription? _realtimeSub;
  Timer? _refreshTimer;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _loadInitial();
    _subscribeRealtime();

    // refresh ทุก 30 วินาทีเพื่อความแม่นยำ (2-min window)
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) _fetchCount();
    });
  }

  @override
  void dispose() {
    _realtimeSub?.cancel();
    _refreshTimer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _loadInitial() async {
    await _fetchCount();
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _fetchCount() async {
    try {
      final counts = await _repo.getOnlineProviderCounts();
      if (!mounted) return;
      setState(() {
        if (widget.professionId != null) {
          _onlineCount = counts[widget.professionId] ?? 0;
        } else {
          _onlineCount = counts.values.fold(0, (a, b) => a + b);
        }
      });
    } catch (e) {
      debugPrint('OnlineProvidersBadge: Error fetching count: $e');
    }
  }

  void _subscribeRealtime() {
    // Subscribe ต่อการเปลี่ยนแปลงของตาราง users
    _realtimeSub = _repo
        .watchOnlineProviderCounts()
        .listen((counts) {
      if (!mounted) return;
      setState(() {
        if (widget.professionId != null) {
          _onlineCount = counts[widget.professionId] ?? 0;
        } else {
          _onlineCount = counts.values.fold(0, (a, b) => a + b);
        }
        _isLoading = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? AppColors.success;

    if (widget.compact) {
      return _buildCompact(color);
    }
    return _buildFull(color);
  }

  // ================================================
  // Compact: จุดสีเขียว + ตัวเลข (สำหรับ card/list)
  // ================================================
  Widget _buildCompact(Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedBuilder(
          animation: _pulseAnimation,
          builder: (_, __) => Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _onlineCount > 0
                  ? color.withValues(alpha: _pulseAnimation.value)
                  : Colors.grey.shade400,
              boxShadow: _onlineCount > 0
                  ? [
                      BoxShadow(
                        color: color.withValues(alpha: 0.6 * _pulseAnimation.value),
                        blurRadius: 8,
                        spreadRadius: 2,
                      )
                    ]
                  : null,
            ),
          ),
        ),
        const SizedBox(width: 5),
        if (_isLoading)
          SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              color: color,
            ),
          )
        else
          Text(
            '$_onlineCount online',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: widget.textColor ?? (_onlineCount > 0 ? color : Colors.grey.shade500),
            ),
          ),
      ],
    );
  }

  // ================================================
  // Full Card: แสดงข้อมูลครบถ้วน
  // ================================================
  Widget _buildFull(Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.25), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Pulsing dot
          AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (_, __) => Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _onlineCount > 0
                    ? color.withValues(alpha: _pulseAnimation.value)
                    : Colors.grey.shade400,
                boxShadow: _onlineCount > 0
                    ? [
                        BoxShadow(
                          color: color.withValues(alpha: 0.6 * _pulseAnimation.value),
                          blurRadius: 10,
                          spreadRadius: 3,
                        )
                      ]
                    : null,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_isLoading)
                SizedBox(
                  width: 40,
                  height: 14,
                  child: LinearProgressIndicator(
                    color: color,
                    backgroundColor: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                )
              else
                Text(
                  '$_onlineCount คน',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: _onlineCount > 0 ? color : Colors.grey.shade500,
                  ),
                ),
              Text(
                '${widget.label} ออนไลน์',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ============================================================
// AllGroupsOnlinePanel - แสดงทุกกลุ่มอาชีพพร้อมจำนวน online
// ============================================================
class AllGroupsOnlinePanel extends StatefulWidget {
  final List<Profession> professions;
  final bool isAdminView;

  const AllGroupsOnlinePanel({
    super.key,
    required this.professions,
    this.isAdminView = false,
  });

  @override
  State<AllGroupsOnlinePanel> createState() => _AllGroupsOnlinePanelState();
}

class _AllGroupsOnlinePanelState extends State<AllGroupsOnlinePanel> {
  final UserRepository _repo = UserRepository(Supabase.instance.client);
  final ScrollController _scrollController = ScrollController();

  Map<String, int> _counts = {};
  bool _isLoading = true;
  StreamSubscription? _sub;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _loadData();
    _sub = _repo.watchOnlineProviderCounts().listen((counts) {
      if (mounted) setState(() { _counts = counts; _isLoading = false; });
    });
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) _loadData();
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _refreshTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final counts = await _repo.getOnlineProviderCounts();
    if (mounted) setState(() { _counts = counts; _isLoading = false; });
  }

  int get _totalOnline => _counts.values.fold(0, (a, b) => a + b);

  @override
  Widget build(BuildContext context) {
    final providerProfessions = widget.professions
        .where((p) => p.category == UserCategory.provider)
        .toList();

    // เรียงลำดับตามจำนวนออนไลน์ (มากไปน้อย)
    providerProfessions.sort((a, b) {
      final countA = _counts[a.id] ?? 0;
      final countB = _counts[b.id] ?? 0;
      if (countA != countB) return countB.compareTo(countA);
      return a.name.compareTo(b.name); // ถ้าเท่ากันเรียงตามชื่อ
    });

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header - รวมทั้งหมด
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.primary.withValues(alpha: 0.12),
                  AppColors.primaryLight.withValues(alpha: 0.06),
                ],
              ),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.people_alt_rounded, color: AppColors.primary, size: 20),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ผู้ให้บริการออนไลน์',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      'Real-time · อัปเดตทุก 30 วิ',
                      style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                    ),
                  ],
                ),
                const Spacer(),
                // Badge รวม
                _isLoading
                    ? const SizedBox(
                        width: 20, height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                      )
                    : _TotalOnlineBadge(count: _totalOnline),
              ],
            ),
          ),

          // รายการแต่ละกลุ่ม
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (providerProfessions.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'ไม่พบกลุ่มผู้ให้บริการ',
                style: TextStyle(color: Colors.grey.shade500),
              ),
            )
          else
            _buildProfessionList(providerProfessions),
        ],
      ),
    );
  }

  Widget _buildProfessionList(List<Profession> professions) {
    final list = Column(
      children: professions.asMap().entries.map((entry) {
        final i = entry.key;
        final p = entry.value;
        final count = _counts[p.id] ?? 0;
        final isLast = i == professions.length - 1;
        return _ProfessionOnlineRow(
          profession: p,
          onlineCount: count,
          isLast: isLast,
        );
      }).toList(),
    );

    if (professions.length <= 5) return list;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 310), // ประมาณ 5 รายการ (62px * 5)
      child: Scrollbar(
        controller: _scrollController,
        thumbVisibility: true,
        thickness: 4,
        radius: const Radius.circular(10),
        child: SingleChildScrollView(
          controller: _scrollController,
          child: list,
        ),
      ),
    );
  }
}

class _TotalOnlineBadge extends StatefulWidget {
  final int count;
  const _TotalOnlineBadge({required this.count});

  @override
  State<_TotalOnlineBadge> createState() => _TotalOnlineBadgeState();
}

class _TotalOnlineBadgeState extends State<_TotalOnlineBadge>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: widget.count > 0
              ? AppColors.success.withValues(alpha: 0.12)
              : Colors.grey.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: widget.count > 0
                ? AppColors.success.withValues(alpha: _anim.value)
                : Colors.grey.shade300,
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.count > 0
                    ? AppColors.success.withValues(alpha: _anim.value)
                    : Colors.grey.shade400,
                boxShadow: widget.count > 0
                    ? [BoxShadow(color: AppColors.success.withValues(alpha: 0.4 * _anim.value), blurRadius: 5, spreadRadius: 1)]
                    : null,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '${widget.count} online',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: widget.count > 0 ? AppColors.success : Colors.grey.shade500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfessionOnlineRow extends StatelessWidget {
  final Profession profession;
  final int onlineCount;
  final bool isLast;

  const _ProfessionOnlineRow({
    required this.profession,
    required this.onlineCount,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    final statusColor = onlineCount > 0 ? AppColors.success : Colors.grey.shade400;
    
    // แปลงสีประจำอาชีพ
    final professionColor = profession.colorHex != null 
        ? Color(int.parse(profession.colorHex!.replaceFirst('#', '0xFF')))
        : AppColors.primary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : Border(bottom: BorderSide(color: Colors.grey.shade100, width: 1)),
      ),
      child: Row(
        children: [
          // Icon กลุ่ม
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: professionColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              _iconFor(profession.iconName),
              size: 18,
              color: professionColor,
            ),
          ),
          const SizedBox(width: 12),

          // ชื่อกลุ่ม
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  profession.name,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: onlineCount > 0 ? AppColors.textPrimary : Colors.grey.shade500,
                  ),
                ),
                if (profession.nameEn != null)
                  Text(
                    profession.nameEn!,
                    style: TextStyle(
                      fontSize: 11, 
                      color: onlineCount > 0 ? Colors.grey.shade500 : Colors.grey.shade400,
                    ),
                  ),
              ],
            ),
          ),

          // จำนวน online
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              onlineCount > 0 ? '$onlineCount คน' : 'ออฟไลน์',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: statusColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  IconData _iconFor(String? name) {
    switch (name) {
      case 'person': return Icons.person;
      case 'store': return Icons.store;
      case 'local_hospital': return Icons.local_hospital;
      case 'medical_services': return Icons.medical_services;
      case 'delivery_dining': return Icons.delivery_dining;
      case 'engineering': return Icons.engineering;
      case 'gavel': return Icons.gavel;
      case 'school': return Icons.school;
      case 'restaurant': return Icons.restaurant;
      case 'spa': return Icons.spa;
      case 'fitness_center': return Icons.fitness_center;
      case 'shopping_cart': return Icons.shopping_cart;
      default: return Icons.work;
    }
  }
}
