import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../../shared/widgets/widgets.dart';
import '../../../../services/service_locator.dart';
import '../../models/profession.dart';
import '../../models/owner_onboarding_tracking.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// หน้าตรวจสอบผู้สมัครลงทะเบียน
class ApplicationReviewPage extends StatefulWidget {
  const ApplicationReviewPage({super.key});

  @override
  State<ApplicationReviewPage> createState() => _ApplicationReviewPageState();
}

class _ApplicationReviewPageState extends State<ApplicationReviewPage>
    with SingleTickerProviderStateMixin {
  static const int _ownerTrackingTabIndex = 4;
  static const List<VerificationStatus> _tabStatusOrder = [
    VerificationStatus.approved,
    VerificationStatus.rejected,
    VerificationStatus.cancelled,
    VerificationStatus.pending,
  ];

  late TabController _tabController;
  final _repo = ServiceLocator.instance.registrationRepository;
  List<RegistrationApplication> _applications = [];
  bool _isLoading = true;
  VerificationStatus _selectedStatus = VerificationStatus.approved;
  Set<String> _usersWithPendingBeneficiary = {};
  bool _showSheservedOnly = false;

  List<OwnerOnboardingTracking> _ownerTracking = [];
  bool _isLoadingOwnerTracking = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        if (_tabController.index == _ownerTrackingTabIndex) {
          _loadOwnerTracking();
        } else {
          setState(() {
            _selectedStatus = _tabStatusOrder[_tabController.index];
            _showSheservedOnly = _selectedStatus == VerificationStatus.pending;
          });
          _loadApplications();
        }
      }
    });
    _loadApplications();
  }

  Future<void> _loadOwnerTracking() async {
    if (!mounted) return;
    setState(() => _isLoadingOwnerTracking = true);
    try {
      final tracking = await _repo.getOwnerOnboardingTracking();
      if (mounted) {
        setState(() {
          _ownerTracking = tracking;
          _isLoadingOwnerTracking = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingOwnerTracking = false);
      debugPrint('Error loading owner onboarding tracking: $e');
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadApplications() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final apps = await _repo.getApplications(_selectedStatus);
      
      // ดึงข้อมูล owner_user_id ที่มีมูลนิธิรอตรวจสอบ (is_verified = false) แบบรวดเร็ว
      Set<String> pendingOrgsUserIds = {};
      try {
        final res = await Supabase.instance.client
            .from('beneficiary_organizations')
            .select('owner_user_id')
            .eq('is_verified', false)
            .not('owner_user_id', 'is', null);
        
        for (var row in res) {
          pendingOrgsUserIds.add(row['owner_user_id'].toString());
        }
      } catch (e) {
        debugPrint('Error loading pending beneficiaries: $e');
      }

      if (mounted) {
        setState(() {
          _applications = apps;
          _usersWithPendingBeneficiary = pendingOrgsUserIds;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
      debugPrint('Error loading applications: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      drawer: const TlzDrawer(),
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight + 48 + 16),
        child: Container(
          color: AppColors.primary,
          child: Column(
            children: [
              SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: TlzAppTopBar.onPrimary(
                    searchHintText: 'ค้นหาผู้สมัคร...',
                  ),
                ),
              ),
              TabBar(
                controller: _tabController,
                isScrollable: true,
                indicatorColor: AppColors.textOnPrimary,
                labelColor: AppColors.textOnPrimary,
                unselectedLabelColor: AppColors.textOnPrimary.withValues(alpha:0.6),
                tabs: [
                  const Tab(text: 'อนุมัติแล้ว'),
                  const Tab(text: 'ถูกปฏิเสธ'),
                  const Tab(text: 'ยกเลิกแล้ว'),
                  Tab(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('คัดกรองชั้น 2'),
                        const SizedBox(width: 4),
                        _buildBadge(_getSheservedQueueCount()),
                      ],
                    ),
                  ),
                  Tab(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.admin_panel_settings_outlined, size: 16),
                        const SizedBox(width: 4),
                        const Text('สถานะการอนุมัติผู้ดูแล ERP'),
                        const SizedBox(width: 4),
                        _buildBadge(_getStuckOwnerCount()),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      body: AnimatedBuilder(
        animation: _tabController,
        builder: (context, _) {
          if (_tabController.index == _ownerTrackingTabIndex) {
            return _isLoadingOwnerTracking
                ? const Center(child: CircularProgressIndicator())
                : _buildOwnerTrackingList();
          }
          return _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _buildApplicationList();
        },
      ),
    );
  }

  int _getStuckOwnerCount() {
    return _ownerTracking.where((t) => t.isStuck).length;
  }

  Widget _buildBadge(int count) {
    if (count == 0) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.error,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        count.toString(),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  int _getSheservedQueueCount() {
    return _applications
        .where((a) =>
            a.status == VerificationStatus.pending &&
            a.profession?.requiresSheservedApproval == true)
        .length;
  }

  Widget _buildApplicationList() {
    var filteredApps =
        _applications.where((a) => a.status == _selectedStatus).toList();

    // Sheserved approval filter (only meaningful in pending tab)
    final isPendingTab = _selectedStatus == VerificationStatus.pending;
    if (isPendingTab && _showSheservedOnly) {
      filteredApps = filteredApps
          .where((a) => a.profession?.requiresSheservedApproval == true)
          .toList();
    }

    // Sheserved approval count for chip badge
    final sheservedCount = _getSheservedQueueCount();

    if (filteredApps.isEmpty) {
      return Column(
        children: [
          if (isPendingTab) _buildSheservedFilterChips(sheservedCount),
          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    _selectedStatus == VerificationStatus.pending
                        ? Icons.inbox_outlined
                        : _selectedStatus == VerificationStatus.approved
                            ? Icons.check_circle_outline
                            : _selectedStatus == VerificationStatus.rejected
                                ? Icons.cancel_outlined
                                : Icons.remove_circle_outline,
                    size: 64,
                    color: AppColors.textHint,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _showSheservedOnly && isPendingTab
                        ? 'ไม่มีผู้สมัครที่ต้องอนุมัติจาก Sheserved'
                        : _selectedStatus == VerificationStatus.pending
                            ? 'ไม่มีผู้สมัครคัดกรองชั้น 2'
                            : _selectedStatus == VerificationStatus.approved
                                ? 'ยังไม่มีผู้สมัครที่อนุมัติ'
                                : _selectedStatus == VerificationStatus.rejected
                                    ? 'ยังไม่มีผู้สมัครที่ถูกปฏิเสธ'
                                    : 'ยังไม่มีใบสมัครที่ถูกยกเลิก',
                    style: AppTextStyles.bodyLarge.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    return Column(
      children: [
        if (isPendingTab) _buildSheservedFilterChips(sheservedCount),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _loadApplications,
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: filteredApps.length,
              itemBuilder: (context, index) {
                return _buildApplicationCard(filteredApps[index]);
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSheservedFilterChips(int sheservedCount) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          FilterChip(
            label: const Text('ทั้งหมด'),
            selected: !_showSheservedOnly,
            onSelected: (_) {
              setState(() => _showSheservedOnly = false);
            },
            selectedColor: AppColors.primary.withValues(alpha:0.15),
            checkmarkColor: AppColors.primary,
            labelStyle: AppTextStyles.bodySmall.copyWith(
              color: !_showSheservedOnly ? AppColors.primary : AppColors.textSecondary,
              fontWeight: !_showSheservedOnly ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
          const SizedBox(width: 8),
          FilterChip(
            label: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.fact_check_outlined, size: 14, color: Colors.deepOrange),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    'คัดกรองและขอรับอนุมัติ(ชั้น 2/sheserved)',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (sheservedCount > 0) ...[
                  const SizedBox(width: 4),
                  _buildBadge(sheservedCount),
                ],
              ],
            ),
            selected: _showSheservedOnly,
            onSelected: (_) {
              setState(() => _showSheservedOnly = true);
            },
            selectedColor: Colors.deepOrange.withValues(alpha:0.15),
            checkmarkColor: Colors.deepOrange,
            labelStyle: AppTextStyles.bodySmall.copyWith(
              color: _showSheservedOnly ? Colors.deepOrange : AppColors.textSecondary,
              fontWeight: _showSheservedOnly ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOwnerTrackingList() {
    if (_ownerTracking.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.admin_panel_settings_outlined,
              size: 64,
              color: AppColors.textHint,
            ),
            const SizedBox(height: 16),
            Text(
              'ยังไม่มีคำขอจดทะเบียน Owner',
              style: AppTextStyles.bodyLarge.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      );
    }

    // เรียงให้เคสที่ค้างอยู่ขึ้นก่อน
    final sorted = List<OwnerOnboardingTracking>.from(_ownerTracking)
      ..sort((a, b) {
        if (a.isStuck != b.isStuck) return a.isStuck ? -1 : 1;
        return b.createdAt.compareTo(a.createdAt);
      });

    return RefreshIndicator(
      onRefresh: _loadOwnerTracking,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: sorted.length,
        itemBuilder: (context, index) => _buildOwnerTrackingCard(sorted[index]),
      ),
    );
  }

  Widget _buildOwnerTrackingCard(OwnerOnboardingTracking tracking) {
    final steps = OwnerOnboardingStep.values;
    final currentStep = tracking.currentStepNumber;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tracking.fullName,
                        style: AppTextStyles.bodyMedium
                            .copyWith(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        '@${tracking.username} • ${tracking.professionName}',
                        style: AppTextStyles.caption
                            .copyWith(color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
                if (tracking.isRejected)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha:0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'ถูกปฏิเสธ',
                      style: AppTextStyles.caption.copyWith(
                        color: AppColors.error,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  )
                else if (tracking.isCancelled)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.grey.withValues(alpha:0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      tracking.cancelledByLabel,
                      style: AppTextStyles.caption.copyWith(
                        color: Colors.grey[700],
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  )
                else if (tracking.isStuck)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha:0.15),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.orange.shade600, width: 0.5),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.warning_amber_rounded,
                            size: 12, color: Colors.orange.shade800),
                        const SizedBox(width: 4),
                        Text(
                          'ค้างขั้นตอนที่ $currentStep',
                          style: AppTextStyles.caption.copyWith(
                            color: Colors.orange.shade800,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  )
                else if (tracking.isFullyCompleted)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.success.withValues(alpha:0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'เสร็จสมบูรณ์',
                      style: AppTextStyles.caption.copyWith(
                        color: AppColors.success,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            if (tracking.isRejected)
              Row(
                children: [
                  Icon(Icons.cancel, size: 16, color: AppColors.error),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      tracking.reviewNote?.isNotEmpty == true
                          ? 'ใบสมัครถูกปฏิเสธ: ${tracking.reviewNote}'
                          : 'ใบสมัครถูกปฏิเสธ',
                      style: AppTextStyles.caption.copyWith(color: AppColors.error),
                    ),
                  ),
                ],
              )
            else if (tracking.isCancelled)
              Row(
                children: [
                  Icon(Icons.remove_circle_outline, size: 16, color: Colors.grey[600]),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      tracking.cancelledAt != null
                          ? '${tracking.cancelledByLabel} (${_formatDate(tracking.cancelledAt!)})'
                          : tracking.cancelledByLabel,
                      style: AppTextStyles.caption.copyWith(color: Colors.grey[600]),
                    ),
                  ),
                ],
              )
            else
              Row(
                children: List.generate(steps.length * 2 - 1, (i) {
                  if (i.isOdd) {
                    final leftStepDone =
                        currentStep != null && steps[i ~/ 2].stepNumber <= currentStep;
                    return Expanded(
                      child: Container(
                        height: 2,
                        color: leftStepDone
                            ? AppColors.success
                            : AppColors.textHint.withValues(alpha:0.3),
                      ),
                    );
                  }
                  final step = steps[i ~/ 2];
                  final isDone =
                      currentStep != null && step.stepNumber <= currentStep;
                  final isCurrent = step.stepNumber == currentStep;
                  return Tooltip(
                    message: step.label,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isDone
                                ? (isCurrent ? AppColors.primary : AppColors.success)
                                : Colors.transparent,
                            border: Border.all(
                              color: isDone
                                  ? (isCurrent ? AppColors.primary : AppColors.success)
                                  : AppColors.textHint,
                              width: 2,
                            ),
                          ),
                          child: Center(
                            child: isDone
                                ? const Icon(Icons.check, size: 16, color: Colors.white)
                                : Text(
                                    '${step.stepNumber}',
                                    style: AppTextStyles.caption.copyWith(
                                      color: AppColors.textHint,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ),
            if (!tracking.isRejected && !tracking.isCancelled) ...[
              const SizedBox(height: 8),
              Row(
                children: steps
                    .map((s) => Expanded(
                          child: Text(
                            s.label,
                            textAlign: TextAlign.center,
                            style: AppTextStyles.caption.copyWith(
                              fontSize: 10,
                              color: currentStep != null && s.stepNumber <= currentStep
                                  ? AppColors.textPrimary
                                  : AppColors.textHint,
                            ),
                          ),
                        ))
                    .toList(),
              ),
            ],
            const SizedBox(height: 8),
            Text(
              'สมัครเมื่อ: ${_formatTimeAgo(tracking.createdAt)}'
              '${tracking.reviewedAt != null ? ' • อนุมัติเมื่อ: ${_formatTimeAgo(tracking.reviewedAt!)}' : ''}',
              style: AppTextStyles.caption.copyWith(color: AppColors.textHint),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildApplicationCard(RegistrationApplication application) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: () => _showApplicationDetail(application),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // Avatar
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha:0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        application.firstName.isNotEmpty
                            ? application.firstName[0].toUpperCase()
                            : '?',
                        style: AppTextStyles.heading4.copyWith(
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          application.fullName,
                          style: AppTextStyles.bodyMedium.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '@${application.username}',
                          style: AppTextStyles.caption.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withValues(alpha:0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                application.profession?.name ?? 'ไม่ระบุ',
                                style: AppTextStyles.caption.copyWith(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            if (application.profession?.requiresSheservedApproval == true)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.deepOrange.withValues(alpha:0.12),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: Colors.deepOrange.shade300, width: 0.5),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.fact_check_outlined, size: 10, color: Colors.deepOrange),
                                    const SizedBox(width: 3),
                                    Flexible(
                                      child: Text(
                                        'คัดกรองชั้น 2/sheserved',
                                        style: TextStyle(
                                          color: Colors.deepOrange.shade700,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            if (application.registrationData['is_owner_request'] == 'true' ||
                                application.registrationData['is_owner_request'] == true)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.amber.withValues(alpha:0.15),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: Colors.amber.shade600, width: 0.5),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.stars, size: 10, color: Colors.orange),
                                    SizedBox(width: 3),
                                    Text(
                                      '👑 ขอจดทะเบียน Owner',
                                      style: TextStyle(
                                        color: Colors.orange,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Status & Action
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      _buildStatusBadge(
                        application.status,
                        cancelledBy: application.status == VerificationStatus.cancelled
                            ? application.cancelledBy
                            : null,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _formatTimeAgo(application.createdAt),
                        style: AppTextStyles.caption.copyWith(
                          color: AppColors.textHint,
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              // Review note if rejected
              if (application.status == VerificationStatus.rejected &&
                  application.reviewNote != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha:0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 16,
                        color: AppColors.error,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          application.reviewNote!,
                          style: AppTextStyles.caption.copyWith(
                            color: AppColors.error,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // ปุ่มพิเศษตรวจสอบบัญชีมูลนิธิถ้าตรวจสอบเจอ
              if (_usersWithPendingBeneficiary.contains(application.oderId)) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange.shade300),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.account_balance, color: Colors.orange),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'ตรวจพบเอกสารตัวแทนมูลนิธิ/MOU รอการอนุมัติอยู่',
                          style: TextStyle(color: Colors.deepOrange, fontSize: 13, fontWeight: FontWeight.bold),
                        ),
                      ),
                      ElevatedButton(
                        onPressed: () {
                           ScaffoldMessenger.of(context).showSnackBar(
                             const SnackBar(content: Text('กรุณาอนุมัติวิชาชีพก่อน แล้วจึงคลิกไปตรวจมูลนิธิ'))
                           );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('รออนุมัติวิชาชีพ'),
                      ),
                    ],
                  ),
                ),
              ],

              // Action buttons for pending
              if (application.status == VerificationStatus.pending) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _showRejectDialog(application),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.error,
                          side: BorderSide(color: AppColors.error),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text('ปฏิเสธ'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => _approveApplication(application),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.success,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text('อนุมัติ'),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBadge(VerificationStatus status, {String? cancelledBy}) {
    Color color;
    String text;
    IconData icon;

    switch (status) {
      case VerificationStatus.pending:
        color = AppColors.warning;
        text = 'รอตรวจสอบ';
        icon = Icons.schedule;
        break;
      case VerificationStatus.approved:
        color = AppColors.success;
        text = 'อนุมัติแล้ว';
        icon = Icons.check_circle;
        break;
      case VerificationStatus.rejected:
        color = AppColors.error;
        text = 'ถูกปฏิเสธ';
        icon = Icons.cancel;
        break;
      case VerificationStatus.cancelled:
        color = Colors.grey;
        text = (cancelledBy == 'auto_profession_change')
            ? 'เปลี่ยนกลุ่มแล้ว'
            : 'ยกเลิกแล้ว';
        icon = Icons.remove_circle_outline;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha:0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            text,
            style: AppTextStyles.caption.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  String _formatTimeAgo(DateTime dateTime) {
    final difference = DateTime.now().difference(dateTime);
    if (difference.inDays > 0) {
      return '${difference.inDays} วันที่แล้ว';
    } else if (difference.inHours > 0) {
      return '${difference.inHours} ชั่วโมงที่แล้ว';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes} นาทีที่แล้ว';
    } else {
      return 'เมื่อสักครู่';
    }
  }

  String _formatDate(DateTime dateTime) {
    return '${dateTime.day}/${dateTime.month}/${dateTime.year + 543}';
  }

  void _showApplicationDetail(RegistrationApplication application) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _ApplicationDetailSheet(
        application: application,
        onApprove: () {
          Navigator.pop(context);
          _approveApplication(application);
        },
        onReject: (note) {
          Navigator.pop(context);
          _rejectApplication(application, note);
        },
      ),
    );
  }

  void _approveApplication(RegistrationApplication application) async {
    try {
      final currentUserId = Supabase.instance.client.auth.currentUser?.id;
      await _repo.approveApplication(application, reviewedBy: currentUserId);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('อนุมัติ ${application.fullName} แล้ว'),
            backgroundColor: AppColors.success,
          ),
        );
        _loadApplications(); // Refresh list

        // Owner Request Check & Success Dialog
        final isOwnerReq = application.registrationData['is_owner_request'] == 'true' ||
            application.registrationData['is_owner_request'] == true;

        if (isOwnerReq) {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.stars, color: Colors.orange),
                  SizedBox(width: 8),
                  Text('อนุมัติ Owner สำเร็จ'),
                ],
              ),
              content: const Text(
                  'อนุมัติผู้ดูแลระบบ/Owner รายแรกขององค์กรสำเร็จ! ระบบได้เปิดใช้งานสิทธิ์จัดการองค์กรและผูกบทบาท \'Owner\' เรียบร้อยแล้ว'
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('ตกลง'),
                ),
              ],
            ),
          );
        } else if (_usersWithPendingBeneficiary.contains(application.oderId)) {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('อนุมัติวิชาชีพสำเร็จ'),
              content: const Text('ผู้ใช้นี้มี "เอกสารมูลนิธิ/MOU" รอตรวจสอบอยู่ ต้องการไปยังหน้าผู้รับมรดกเพื่อตรวจสอบต่อเลยหรือไม่?'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('ไว้ทีหลัง')),
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    Navigator.pushNamed(context, '/admin/donations', arguments: {'initialIndex': 4}); // ไปที่ Beneficiary Tab
                  },
                  child: const Text('ไปตรวจสอบเลย'),
                ),
              ],
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('เกิดข้อผิดพลาดในการอนุมัติ: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  void _showRejectDialog(RegistrationApplication application) {
    final noteController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ปฏิเสธการสมัคร'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('กำลังปฏิเสธ: ${application.fullName}'),
            const SizedBox(height: 16),
            TextField(
              controller: noteController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'เหตุผลที่ปฏิเสธ *',
                hintText: 'เช่น ข้อมูลไม่ครบถ้วน, รูปไม่ชัด',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ยกเลิก'),
          ),
          ElevatedButton(
            onPressed: () {
              if (noteController.text.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('กรุณาระบุเหตุผล')),
                );
                return;
              }
              _rejectApplication(application, noteController.text);
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            child: const Text('ปฏิเสธ'),
          ),
        ],
      ),
    );
  }

  void _rejectApplication(RegistrationApplication application, String note) async {
    try {
      final currentUserId = Supabase.instance.client.auth.currentUser?.id;
      await _repo.rejectApplication(application, note, reviewedBy: currentUserId);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('ปฏิเสธ ${application.fullName} แล้ว'),
            backgroundColor: AppColors.error,
          ),
        );
        _loadApplications(); // Refresh list
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('เกิดข้อผิดพลาดในการปฏิเสธ: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }
}

/// Bottom sheet แสดงรายละเอียดผู้สมัคร
class _ApplicationDetailSheet extends StatefulWidget {
  final RegistrationApplication application;
  final VoidCallback onApprove;
  final Function(String note) onReject;

  const _ApplicationDetailSheet({
    required this.application,
    required this.onApprove,
    required this.onReject,
  });

  @override
  State<_ApplicationDetailSheet> createState() => _ApplicationDetailSheetState();
}

class _ApplicationDetailSheetState extends State<_ApplicationDetailSheet> {
  List<Map<String, dynamic>> _attachments = [];
  bool _isLoadingAttachments = true;

  @override
  void initState() {
    super.initState();
    _loadAttachments();
  }

  Future<void> _loadAttachments() async {
    try {
      final repo = ServiceLocator.instance.registrationRepository;
      final attachments = await repo.getApplicationAttachments(widget.application.id);
      if (mounted) {
        setState(() {
          _attachments = attachments;
          _isLoadingAttachments = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading attachments: $e');
      if (mounted) setState(() => _isLoadingAttachments = false);
    }
  }

  bool get _requiresCredentialCheck {
    final profession = widget.application.profession;
    if (profession == null) return false;
    return profession.requiresTelemedicineLicense == true ||
        profession.approvalRequiredLicenseTypes.isNotEmpty;
  }

  bool _hasAttachmentForRequirement(String requirement) {
    final normalized = requirement.toLowerCase();
    return _attachments.any((attachment) {
      final fieldKey = (attachment['field_key'] as String? ?? '').toLowerCase();
      final groupKey = (attachment['attachment_group_key'] as String? ?? '').toLowerCase();
      return fieldKey.contains(normalized) || groupKey.contains(normalized);
    });
  }

  List<String> _getMissingCredentialRequirements() {
    final profession = widget.application.profession;
    if (profession == null) return [];

    final missing = <String>[];
    if (profession.requiresTelemedicineLicense == true &&
        !_hasAttachmentForRequirement('telemedicine')) {
      missing.add('Telemedicine License');
    }

    for (final requiredType in profession.approvalRequiredLicenseTypes) {
      if (!_hasAttachmentForRequirement(requiredType)) {
        missing.add(requiredType);
      }
    }

    return missing;
  }

  String _buildMissingCredentialReasonText(List<String> missingRequirements) {
    if (missingRequirements.isEmpty) {
      return 'เอกสารครบถ้วนแล้ว';
    }
    return 'ยังขาดเอกสาร/หลักฐานตามข้อกำหนด: ${missingRequirements.join(', ')}';
  }

  Future<void> _copyMissingCredentialReason(List<String> missingRequirements) async {
    final text = _buildMissingCredentialReasonText(missingRequirements);
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('คัดลอกข้อความแจ้งผู้สมัครแล้ว')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.9,
      ),
      decoration: const BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            margin: const EdgeInsets.symmetric(vertical: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.textHint.withValues(alpha:0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Title row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                Text(
                  'รายละเอียดผู้สมัคร',
                  style: AppTextStyles.heading4.copyWith(fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // Scrollable content
          Flexible(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomInset),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
            // Owner Highlight Alert
            if (widget.application.registrationData['is_owner_request'] == 'true' ||
                widget.application.registrationData['is_owner_request'] == true) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.amber.shade300, width: 1),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.stars, color: Colors.orange, size: 28),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'คำขอสิทธิ์ผู้ดูแลระบบ/Owner รายแรก',
                            style: TextStyle(
                              color: Colors.orange,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'ผู้ใช้ท่านนี้ขอจดทะเบียนองค์กรใหม่ในฐานะ Owner คนแรก ระบบจะเปิดใช้งาน Feature Flags และแต่งตั้งสิทธิ์จัดการให้เมื่อทำการอนุมัติ',
                            style: TextStyle(
                              color: Colors.orange.shade800,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
            // Profile Card
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    // Avatar
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha:0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          widget.application.firstName.isNotEmpty
                              ? widget.application.firstName[0].toUpperCase()
                              : '?',
                          style: AppTextStyles.heading2.copyWith(
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      widget.application.fullName,
                      style: AppTextStyles.heading4.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      '@${widget.application.username}',
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha:0.1),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            widget.application.profession?.name ?? 'ไม่ระบุ',
                            style: AppTextStyles.bodySmall.copyWith(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (widget.application.profession?.requiresSheservedApproval == true)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.deepOrange.withValues(alpha:0.12),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: Colors.deepOrange.shade300, width: 0.5),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.fact_check_outlined, size: 12, color: Colors.deepOrange),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    'คัดกรองและขอรับอนุมัติ(ชั้น 2/sheserved) ระบบ Consultation',
                                    style: AppTextStyles.bodySmall.copyWith(
                                      color: Colors.deepOrange.shade700,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 2,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Registration Data
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ข้อมูลลงทะเบียน',
                      style: AppTextStyles.bodyLarge.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Divider(height: 24),
                    if (widget.application.phone != null)
                      _buildInfoRow('เบอร์โทร', widget.application.phone!),
                    ...widget.application.registrationData.entries.map((entry) {
                      if (entry.value == 'uploaded') {
                        return _buildImageRow(entry.key);
                      }
                      return _buildInfoRow(
                        _formatFieldKey(entry.key),
                        entry.value.toString(),
                      );
                    }),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Images Section
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'รูปภาพที่อัพโหลด',
                      style: AppTextStyles.bodyLarge.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Divider(height: 24),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: _attachments.isNotEmpty
                          ? _attachments.map((a) => _buildAttachmentPreview(context, a)).toList()
                          : widget.application.registrationData.entries
                              .where((e) => e.value == 'uploaded')
                              .map((e) => _buildImagePreview(context, e.key))
                              .toList(),
                    ),
                    if (_attachments.isEmpty && widget.application.registrationData.entries
                        .where((e) => e.value == 'uploaded')
                        .isEmpty)
                      Text(
                        'ไม่มีรูปภาพ',
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: AppColors.textHint,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // License Requirement Status Section
            if (_requiresCredentialCheck) ...[
              Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.verified_user, color: AppColors.primary),
                          const SizedBox(width: 8),
                          Text(
                            'สถานะหลักฐานใบอนุญาต',
                            style: AppTextStyles.bodyLarge.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'แสดงหลักฐานที่แนบและสถานะข้อกำหนดสำหรับการตัดสินใจของผู้ตรวจสอบ ระบบยังไม่บล็อกการอนุมัติอัตโนมัติในหน้านี้',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const Divider(height: 24),
                      if (widget.application.profession?.requiresTelemedicineLicense == true)
                        _buildCredentialCheckRow(
                          'Telemedicine License',
                          _attachments.any((a) {
                            final fieldKey = (a['field_key'] as String? ?? '').toLowerCase();
                            final groupKey = (a['attachment_group_key'] as String? ?? '').toLowerCase();
                            return fieldKey.contains('telemedicine') || groupKey.contains('telemedicine');
                          }),
                        ),
                      ...(widget.application.profession?.approvalRequiredLicenseTypes ?? []).map((type) {
                        final hasAttachment = _attachments.any((a) =>
                          (a['field_key'] as String? ?? '').toLowerCase().contains(type.toLowerCase()) ||
                          (a['attachment_group_key'] as String? ?? '').toLowerCase().contains(type.toLowerCase())
                        );
                        return _buildCredentialCheckRow(type, hasAttachment);
                      }),
                      if (_attachments.isEmpty && _isLoadingAttachments)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: LinearProgressIndicator(),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              if (!_isLoadingAttachments && _getMissingCredentialRequirements().isNotEmpty) ...[
                Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  color: Colors.orange.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.warning_amber_rounded, color: Colors.orange.shade700),
                            const SizedBox(width: 8),
                            Text(
                              'รายการที่ยังขาด',
                              style: AppTextStyles.bodyLarge.copyWith(
                                fontWeight: FontWeight.w600,
                                color: Colors.orange.shade800,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _buildMissingCredentialReasonText(_getMissingCredentialRequirements()),
                          style: AppTextStyles.bodyMedium.copyWith(
                            color: Colors.orange.shade900,
                          ),
                        ),
                        const SizedBox(height: 12),
                        ..._getMissingCredentialRequirements().map(
                          (item) => Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: _buildCredentialCheckRow(item, false),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: OutlinedButton.icon(
                            onPressed: () => _copyMissingCredentialReason(
                              _getMissingCredentialRequirements(),
                            ),
                            icon: const Icon(Icons.copy),
                            label: const Text('คัดลอกเหตุผล'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ],

            // Action Buttons
            if (widget.application.status == VerificationStatus.pending) ...[
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 52,
                      child: OutlinedButton(
                        onPressed: () => _showRejectDialog(context),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.error,
                          side: BorderSide(color: AppColors.error, width: 2),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(26),
                          ),
                        ),
                        child: Text(
                          'ปฏิเสธ',
                          style: AppTextStyles.button.copyWith(
                            color: AppColors.error,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: SizedBox(
                      height: 52,
                      child: ElevatedButton(
                        onPressed: widget.onApprove,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.success,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(26),
                          ),
                        ),
                        child: Text(
                          'อนุมัติ',
                          style: AppTextStyles.button.copyWith(
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    ],
  ),
);
  }

  Widget _buildAttachmentPreview(BuildContext context, Map<String, dynamic> attachment) {
    final url = attachment['file_url'] as String?;
    final fieldKey = attachment['field_key'] as String? ?? 'attachment';
    return GestureDetector(
      onTap: () {
        if (url != null && url.isNotEmpty) {
          // TODO: Open full image viewer
        }
      },
      child: Container(
        width: 100,
        height: 100,
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
          image: url != null && url.isNotEmpty
              ? DecorationImage(
                  image: NetworkImage(url),
                  fit: BoxFit.cover,
                )
              : null,
        ),
        child: url == null || url.isEmpty
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.image,
                    color: AppColors.textHint,
                    size: 32,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _formatFieldKey(fieldKey),
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.textHint,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              )
            : null,
      ),
    );
  }

  Widget _buildCredentialCheckRow(String label, bool hasAttachment) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(
            hasAttachment ? Icons.check_circle : Icons.warning,
            color: hasAttachment ? AppColors.success : AppColors.error,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: AppTextStyles.bodyMedium.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: hasAttachment ? AppColors.success.withValues(alpha:0.1) : AppColors.error.withValues(alpha:0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              hasAttachment ? 'แนบแล้ว' : 'ยังไม่แนบ',
              style: AppTextStyles.caption.copyWith(
                color: hasAttachment ? AppColors.success : AppColors.error,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: AppTextStyles.bodyMedium.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImageRow(String key) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          SizedBox(
            width: 140,
            child: Text(
              _formatFieldKey(key),
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Icon(Icons.check_circle, color: AppColors.success, size: 20),
          const SizedBox(width: 4),
          Text(
            'อัพโหลดแล้ว',
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.success,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImagePreview(BuildContext context, String key) {
    return GestureDetector(
      onTap: () {
        // TODO: Show full image
      },
      child: Container(
        width: 100,
        height: 100,
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.image,
              color: AppColors.textHint,
              size: 32,
            ),
            const SizedBox(height: 4),
            Text(
              _formatFieldKey(key),
              style: AppTextStyles.caption.copyWith(
                color: AppColors.textHint,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  String _formatFieldKey(String key) {
    final keyMap = {
      'business_name': 'ชื่อธุรกิจ',
      'clinic_name': 'ชื่อคลินิก',
      'specialty': 'ความเชี่ยวชาญ',
      'business_phone': 'เบอร์โทรธุรกิจ',
      'license_number': 'เลขใบอนุญาต',
      'id_card_image': 'บัตรประชาชน',
      'license_image': 'ใบอนุญาต',
      'profile_image': 'รูปโปรไฟล์',
      'business_image': 'รูปสถานประกอบการ',
    };
    return keyMap[key] ?? key;
  }

  void _showRejectDialog(BuildContext context) {
    final noteController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ปฏิเสธการสมัคร'),
        content: TextField(
          controller: noteController,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'เหตุผลที่ปฏิเสธ *',
            hintText: 'เช่น ข้อมูลไม่ครบถ้วน, รูปไม่ชัด',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('ยกเลิก'),
          ),
          ElevatedButton(
            onPressed: () {
              if (noteController.text.isEmpty) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('กรุณาระบุเหตุผล')),
                );
                return;
              }
              Navigator.pop(ctx);
              widget.onReject(noteController.text);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            child: const Text('ปฏิเสธ'),
          ),
        ],
      ),
    );
  }
}
