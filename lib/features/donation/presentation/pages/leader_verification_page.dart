import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../../services/service_locator.dart';
import '../../../../shared/widgets/neumorphic/neumorphic.dart';
import '../../data/repositories/donation_repository.dart';
import '../../models/donation_models.dart';

/// วิดเจ็ตหน้ายืนยันคำร้องบริจาคสำหรับผู้นำชุมชน
/// ใช้ได้ทั้งแบบฝังใน ProfilePage (as Widget) และแบบเปิดหน้าเต็ม
class LeaderVerificationPage extends StatefulWidget {
  const LeaderVerificationPage({super.key});

  @override
  State<LeaderVerificationPage> createState() => _LeaderVerificationPageState();
}

class _LeaderVerificationPageState extends State<LeaderVerificationPage> {
  late DonationRepository _repository;
  String? _currentUserId;
  List<DonationRequest> _pendingRequests = [];
  List<String> _userProfessionIds = []; // profession IDs ของผู้ใช้ปัจจุบัน
  String _userCategoryNamesStr = 'ผู้นำชุมชน';
  bool _isLoading = true;
  StreamSubscription? _requestsSubscription;

  @override
  void initState() {
    super.initState();
    _repository = DonationRepository(Supabase.instance.client);
    _loadUserAndRequests();
    
    // ตั้งค่า WebSocket Real-time Listener เพื่ออัปเดตคำร้องอัตโนมัติ (Fix UX Issue #4)
    _requestsSubscription = Supabase.instance.client
        .from('donation_requests')
        .stream(primaryKey: ['id'])
        .listen((_) {
      if (_currentUserId != null && mounted) {
        _fetchPendingRequests(_currentUserId!);
      }
    });
  }

  @override
  void dispose() {
    _requestsSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadUserAndRequests() async {
    final user = ServiceLocator.instance.currentUser;
    if (user != null) {
      setState(() => _currentUserId = user.id);
      // โหลด profession IDs ของผู้ใช้
      final profIds = await _repository.getUserApproverProfessions(user.id);
      if (mounted) setState(() => _userProfessionIds = profIds);
      
      // Load actual user category names
      try {
        final catIds = await _repository.getUserApproverCategories(user.id);
        if (catIds.isNotEmpty) {
           final catResp = await Supabase.instance.client.from('user_categories').select('name').inFilter('id', catIds);
           if (catResp is List && catResp.isNotEmpty) {
               final names = catResp.map((x) => x['name'].toString()).toList();
               if (mounted) setState(() => _userCategoryNamesStr = names.join(', '));
           }
        }
      } catch (_) {}

      await _fetchPendingRequests(user.id);
    } else {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchPendingRequests(String userId) async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final reqs = await _repository.getPendingRequests(userId);
      if (mounted) {
        setState(() {
          _pendingRequests = reqs;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('LeaderVerificationPage: Error fetching requests: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('เกิดข้อผิดพลาด: $e')),
        );
      }
    }
  }

  Future<void> _approveRequest(DonationRequest req) async {
    if (_currentUserId == null) return;

    // ✅ Bug #3 Fix: หา professionId ที่ตรงกับ category ของ request นั้นจริงๆ
    // ไม่ใช่แค่เลือก first แบบ blind ซึ่งอาจผิด profession
    String? matchedProfId;
    try {
      if (_userProfessionIds.isNotEmpty) {
        // 1. ดึง user_category IDs ที่ category นี้ต้องการ
        final requiredCatIds = await _repository.getCategoryApproverIds(req.categoryId);
        // 2. ดึง map ของ professionId → user_category_id
        final profCatMap = await _repository.getProfessionCategoryMap(_userProfessionIds);
        // 3. หา professionId แรกที่ตรงกับ required category
        for (final pid in _userProfessionIds) {
          final cat = profCatMap[pid];
          if (cat != null && requiredCatIds.contains(cat)) {
            matchedProfId = pid;
            break;
          }
        }
        // Fallback: ใช้ first ถ้าหาไม่เจอ (เช่น admin override)
        matchedProfId ??= _userProfessionIds.first;
      }
    } catch (e) {
      debugPrint('LeaderVerificationPage: Error finding matched profession: $e');
      matchedProfId = _userProfessionIds.isNotEmpty ? _userProfessionIds.first : null;
    }

    try {
      await _repository.approveRequest(
        req.id,
        req.approvalStatus,
        _currentUserId!,
        professionId: matchedProfId,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ ยืนยันคำร้องสำเร็จ รอกลุ่มอื่นอนุมัติให้ครบ'),
            backgroundColor: Colors.green,
          ),
        );
      }
      _fetchPendingRequests(_currentUserId!);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('เกิดข้อผิดพลาด: $e')),
        );
      }
    }
  }

  Future<void> _rejectRequest(DonationRequest req) async {
    // แสดง Confirm Dialog ก่อน
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: NeumorphicTheme.baseColor,
        titleTextStyle: AppTextStyles.heading3.copyWith(
          color: NeumorphicTheme.textPrimary,
        ),
        contentTextStyle: const TextStyle(
          color: NeumorphicTheme.textSecondary,
          fontSize: 14,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('ยืนยันการปฏิเสธ'),
        content: Text('คุณแน่ใจหรือไม่ว่าต้องการปฏิเสธคำร้อง\n"${req.title}"'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('ยกเลิก'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('ปฏิเสธ', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _repository.rejectRequest(req.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ปฏิเสธคำร้องสำเร็จ')),
        );
      }
      if (_currentUserId != null) _fetchPendingRequests(_currentUserId!);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('เกิดข้อผิดพลาด: $e')),
        );
      }
    }
  }

  void _showRequestDetail(DonationRequest req) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: NeumorphicTheme.baseColor,
      clipBehavior: Clip.antiAlias,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        minChildSize: 0.4,
        builder: (_, scrollController) => Container(
          color: NeumorphicTheme.baseColor,
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.all(24),
            children: [
              const Center(child: NeumorphicSheetDragHandle()),
              const SizedBox(height: 16),
              Row(
                children: [
                  NeumorphicContainer(
                    width: 44,
                    height: 44,
                    shape: BoxShape.circle,
                    depth: 3,
                    blur: 6,
                    color: Color.alphaBlend(
                      AppColors.primary.withValues(alpha: 0.10),
                      NeumorphicTheme.baseColor,
                    ),
                    child: const Icon(Icons.assignment, color: AppColors.primary, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(req.title, style: AppTextStyles.heading4.copyWith(fontWeight: FontWeight.bold, color: NeumorphicTheme.textPrimary)),
                        Text(
                          'ส่งคำร้องเมื่อ: ${req.createdAt.toString().split(' ')[0]}',
                          style: AppTextStyles.bodySmall.copyWith(color: NeumorphicTheme.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              NeumorphicContainer(
                borderRadius: 16,
                depth: 4,
                blur: 8,
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _detailRow(Icons.info_outline, 'รายละเอียด', req.description ?? '-'),
                    _detailRow(Icons.location_on_outlined, 'สถานที่ใช้', req.usageLocation ?? '-'),
                    _detailRow(Icons.home_outlined, 'ที่อยู่ผู้ร้อง', req.requesterAddress ?? '-'),
                    if (req.neededDate != null)
                      _detailRow(Icons.event, 'วันที่จำเป็นต้องใช้', req.neededDate!.toString().split(' ')[0]),
                    if (req.targetAmount != null)
                      _detailRow(Icons.monetization_on_outlined, 'ยอดที่ต้องการ', '฿${req.targetAmount!.toInt()}'),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              // ปุ่มตัดสินใจใน Bottom Sheet
              Row(
                children: [
                  Expanded(
                    child: NeumorphicPillButton(
                      text: 'ปฏิเสธ',
                      icon: Icons.close,
                      height: 48,
                      color: Colors.red,
                      onPressed: () {
                        Navigator.pop(ctx);
                        _rejectRequest(req);
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: NeumorphicPillButton(
                      text: 'อนุญาต',
                      icon: Icons.check,
                      height: 48,
                      color: AppColors.primary,
                      onPressed: () {
                        Navigator.pop(ctx);
                        _approveRequest(req);
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppColors.primary.withOpacity(0.7)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: AppTextStyles.bodySmall.copyWith(color: NeumorphicTheme.textSecondary)),
                const SizedBox(height: 2),
                Text(value, style: AppTextStyles.bodyMedium.copyWith(color: NeumorphicTheme.textPrimary)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_currentUserId == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(child: Text('กรุณาเข้าสู่ระบบก่อนใช้งาน')),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header Section
        NeumorphicContainer(
          borderRadius: 20,
          depth: 6,
          blur: 12,
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              NeumorphicContainer(
                width: 44,
                height: 44,
                shape: BoxShape.circle,
                depth: 3,
                blur: 6,
                color: Color.alphaBlend(
                  Colors.teal.withValues(alpha: 0.12),
                  NeumorphicTheme.baseColor,
                ),
                child: const Icon(Icons.how_to_vote, color: Colors.teal, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'อนุมัติคำร้องบริจาค',
                      style: AppTextStyles.heading5.copyWith(color: Colors.teal, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      'รายการต่อไปนี้รอการยืนยันจากคุณ ($_userCategoryNamesStr)',
                      style: AppTextStyles.bodySmall.copyWith(color: NeumorphicTheme.textSecondary),
                    ),
                  ],
                ),
              ),
              // Pull to refresh button
              NeumorphicIconButton(
                icon: Icons.refresh,
                color: Colors.teal,
                onPressed: () => _fetchPendingRequests(_currentUserId!),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        if (_pendingRequests.isEmpty)
          NeumorphicContainer(
            borderRadius: 16,
            depth: 4,
            blur: 8,
            padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 16),
            child: Center(
              child: Column(
                children: [
                  NeumorphicInsetBox(
                    width: 64,
                    height: 64,
                    borderRadius: 32,
                    child: Icon(Icons.check_circle_outline, size: 32, color: Colors.grey[400]),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'ไม่มีคำร้องที่รอการอนุมัติ',
                    style: AppTextStyles.bodyMedium.copyWith(color: NeumorphicTheme.textSecondary),
                  ),
                ],
              ),
            ),
          )
        else
          ...List.generate(_pendingRequests.length, (index) {
            final req = _pendingRequests[index];
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => _showRequestDetail(req),
                  borderRadius: BorderRadius.circular(16),
                  child: NeumorphicContainer(
                    borderRadius: 16,
                    depth: 5,
                    blur: 10,
                    padding: const EdgeInsets.all(16),
                    child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.assignment_turned_in, size: 18, color: AppColors.primary),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              req.title,
                              style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.bold, color: NeumorphicTheme.textPrimary),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.orange.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              'รอยืนยัน',
                              style: TextStyle(color: Colors.orange, fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (req.description != null && req.description!.isNotEmpty)
                        Text(
                          req.description!,
                          style: AppTextStyles.bodySmall.copyWith(color: NeumorphicTheme.textSecondary),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.location_on, size: 14, color: Colors.grey[400]),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              req.usageLocation ?? 'ไม่ระบุสถานที่',
                              style: AppTextStyles.bodySmall.copyWith(color: NeumorphicTheme.textSecondary, fontSize: 11),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: NeumorphicPillButton(
                              text: 'ปฏิเสธ',
                              icon: Icons.close,
                              height: 40,
                              fontSize: 13,
                              iconSize: 16,
                              color: Colors.red,
                              onPressed: () => _rejectRequest(req),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: NeumorphicPillButton(
                              text: 'อนุญาต',
                              icon: Icons.check,
                              height: 40,
                              fontSize: 13,
                              iconSize: 16,
                              color: AppColors.primary,
                              onPressed: () => _approveRequest(req),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  ),
                ),
              ),
            );
          }),
      ],
    );
  }
}
