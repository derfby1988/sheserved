import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';
import 'package:shimmer/shimmer.dart';
import '../../../../services/auth_service.dart';

/// Header Section Widget สำหรับหน้า Home
/// แสดงข้อมูลสถานะสุขภาพ, โปรไฟล์, และข้อมูลทานยา
class HomeHeaderSection extends StatelessWidget {
  final GlobalKey? sectionKey;
  final VoidCallback? onHealthTap;
  final VoidCallback? onProfileTap;
  final String? headerText;
  final bool isLoading;
  final List<Map<String, dynamic>> alerts;
  final Function(String videoId)? onAlertDismissed;
  final Function(String videoId)? onAlertTapped;
  final List<Map<String, dynamic>> donationAlerts;
  /// ✅ [Yield Way] รายการแจ้งเตือนให้ทาง (route-based)
  final List<Map<String, dynamic>> yieldWayAlerts;
  /// ✅ [Consultation] คำขอปรึกษาใหม่ที่รอ provider รับงาน
  final List<Map<String, dynamic>> consultationAlerts;
  /// callback เมื่อปัดทิ้งการแจ้งเตือนปรึกษา (dismiss/ปฏิเสธ)
  final Function(String consultationId)? onConsultationAlertDismissed;
  /// callback เมื่อกดดูการแจ้งเตือนปรึกษา → นำทางไป Dashboard
  final Function(String consultationId)? onConsultationAlertTapped;
  /// ✅ [ERP] คำเชิญพนักงาน ERP ที่รอผู้ใช้ตอบรับ/ปฏิเสธ
  final List<Map<String, dynamic>> employeeInvitationAlerts;
  /// callback เมื่อกดการ์ดคำเชิญพนักงาน → เปิด dialog ตอบรับ/ปฏิเสธ
  final Function(String token)? onEmployeeInvitationTapped;

  const HomeHeaderSection({
    super.key,
    this.sectionKey,
    this.onHealthTap,
    this.onProfileTap,
    this.headerText,
    this.isLoading = false,
    this.alerts = const [],
    this.onAlertDismissed,
    this.onAlertTapped,
    this.donationAlerts = const [],
    this.yieldWayAlerts = const [],
    this.consultationAlerts = const [],
    this.onConsultationAlertDismissed,
    this.onConsultationAlertTapped,
    this.employeeInvitationAlerts = const [],
    this.onEmployeeInvitationTapped,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      key: sectionKey,
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(32),
          bottomRight: Radius.circular(32),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Left Side: Status Text & Profile Picture
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.25,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // กดเพื่อไปหน้า Health
                    GestureDetector(
                      onTap: onHealthTap,
                      child: isLoading
                          ? Container(
                              alignment: Alignment.center,
                              width: 80,
                              height: 6,
                              margin: const EdgeInsets.symmetric(vertical: 8),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(3),
                                child: LinearProgressIndicator(
                                  backgroundColor: Colors.white.withOpacity(0.3),
                                  valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                                ),
                              ),
                            )
                          : FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.center,
                              child: Text(
                                headerText ?? 'สุขภาพ "ดี"',
                                style: AppTextStyles.bodyLarge.copyWith(
                                  color: AppColors.textOnPrimary,
                                  fontWeight: FontWeight.w600,
                                ),
                                maxLines: 1,
                              ),
                            ),
                    ),
                    const SizedBox(height: 12),
                    // Profile Picture Button
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: onProfileTap,
                        borderRadius: BorderRadius.circular(30),
                        child: Container(
                          width: 60,
                          height: 60,
                          decoration: BoxDecoration(
                            color: AppColors.textOnPrimary,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: AppColors.textOnPrimary,
                              width: 2,
                            ),
                            image: AuthService.instance.currentUser?.profileImageUrl != null &&
                                   AuthService.instance.currentUser!.profileImageUrl!.isNotEmpty
                                ? DecorationImage(
                                    image: NetworkImage(AuthService.instance.currentUser!.profileImageUrl!),
                                    fit: BoxFit.cover,
                                  )
                                : null,
                          ),
                          child: (AuthService.instance.currentUser?.profileImageUrl == null ||
                                  AuthService.instance.currentUser!.profileImageUrl!.isEmpty)
                              ? const Icon(
                                  Icons.person,
                                  color: AppColors.primary,
                                  size: 36,
                                )
                              : null,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Right Side: Notification Panel
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.65,
              maxHeight: 96,
            ),
            child: isLoading
                ? _buildShimmerNotifications()
                : _ScrollableNotificationContent(
                    child: Builder(
                      builder: (context) {
                        // รวม notification ทุกประเภทเข้า list เดียว
                        final List<Map<String, dynamic>> combinedItems = [];

                        // 0. Employee invitation alerts (สำคัญสุด — อยู่บนสุด)
                        for (var inv in employeeInvitationAlerts) {
                          combinedItems.add({
                            'time': inv['created_at'] is DateTime
                                ? inv['created_at'] as DateTime
                                : (inv['created_at'] != null
                                    ? DateTime.tryParse(inv['created_at'].toString()) ?? DateTime.now()
                                    : DateTime.now()),
                            'type': 'employee_invitation',
                            'data': inv,
                          });
                        }

                        debugPrint('HomeHeader: employeeInvitationAlerts.length=${employeeInvitationAlerts.length}');

                        // 1. Consultation alerts (สำคัญรองลงมา)
                        debugPrint('HomeHeader: consultationAlerts.length=${consultationAlerts.length}');
                        for (var c in consultationAlerts) {
                          combinedItems.add({
                            'time': c['requestedAt'] as DateTime? ?? DateTime.now(),
                            'type': 'consultation',
                            'data': c,
                          });
                        }

                        // 2. Donation alerts
                        for (var d in donationAlerts) {
                          combinedItems.add({
                            'time': d['updatedAt'] as DateTime? ?? DateTime.now(),
                            'type': 'donation_update',
                            'data': d,
                          });
                        }

                        // 3. Emergency / Thai Mhung alerts
                        for (var alert in alerts) {
                          combinedItems.add({
                            'time': alert['createdAt'] as DateTime? ?? DateTime.now(),
                            'type': 'alert',
                            'data': alert,
                          });
                        }

                        // 4. Yield Way alerts
                        for (var y in yieldWayAlerts) {
                          combinedItems.add({
                            'time': DateTime.now(),
                            'type': 'yield_way',
                            'data': y,
                          });
                        }

                        // เรียงลำดับ: employee_invitation และ consultation อยู่บนสุด (pinned), ที่เหลือใหม่ล่าสุดก่อน
                        combinedItems.sort((a, b) {
                          final aPinned = a['type'] == 'employee_invitation' || a['type'] == 'consultation';
                          final bPinned = b['type'] == 'employee_invitation' || b['type'] == 'consultation';
                          if (aPinned && !bPinned) return -1;
                          if (!aPinned && bPinned) return 1;
                          return (b['time'] as DateTime).compareTo(a['time'] as DateTime);
                        });

                        // Medicine reminder อยู่ล่างสุดเสมอ
                        combinedItems.add({
                          'time': DateTime(2000),
                          'type': 'medicine',
                        });

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: combinedItems.map((item) {
                            // ── Donation Update ──────────────────────────────
                            if (item['type'] == 'donation_update') {
                              final d = item['data'] as Map<String, dynamic>;
                              final title = (d['title']?.toString() ?? 'คำร้องบริจาค');
                              final isActive = d['isActive'] == true;
                              final textColor = isActive ? const Color(0xFF2EA04B) : const Color(0xFFF5A623);
                              final icon = isActive ? Icons.favorite : Icons.access_time_rounded;
                              final statusText = isActive
                                  ? '\u2018$title\u2019 ได้รับการอนุมัติแล้ว!'
                                  : '\u2018$title\u2019 รออนุมัติเพิ่มเติม';
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 4),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    Icon(icon, color: textColor, size: 9),
                                    const SizedBox(width: 4),
                                    Flexible(
                                      child: Text(
                                        statusText,
                                        style: AppTextStyles.caption.copyWith(
                                          color: textColor,
                                          fontWeight: FontWeight.w600,
                                        ),
                                        textAlign: TextAlign.right,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              );

                            // ── Yield Way ────────────────────────────────────
                            } else if (item['type'] == 'yield_way') {
                              final y = item['data'] as Map<String, dynamic>;
                              final categoryName = y['categoryName'] ?? 'เหตุฉุกเฉิน';
                              final videoId = y['videoId']?.toString() ?? '';
                              return GestureDetector(
                                onTap: () => onAlertTapped?.call(videoId),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 4),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      const Icon(Icons.airport_shuttle, color: Color(0xFFFF3B30), size: 10),
                                      const SizedBox(width: 4),
                                      Flexible(
                                        child: Text(
                                          'รถฉุกเฉินกำลังมา: $categoryName',
                                          style: AppTextStyles.caption.copyWith(
                                            color: const Color(0xFFFF3B30),
                                            fontWeight: FontWeight.bold,
                                          ),
                                          textAlign: TextAlign.right,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );

                            // ── Employee Invitation Alert (ERP) ────────────────
                            } else if (item['type'] == 'employee_invitation') {
                              final inv = item['data'] as Map<String, dynamic>;
                              final token = inv['token']?.toString() ?? '';
                              final professionName = inv['profession_name']?.toString() ?? '';
                              final organizationName = inv['organization_name']?.toString() ?? '';
                              final displayOrganizationName = organizationName.isNotEmpty && organizationName != professionName;
                              final jobTitle = inv['job_title']?.toString() ?? '';
                              return GestureDetector(
                                onTap: () => onEmployeeInvitationTapped?.call(token),
                                child: Container(
                                  margin: const EdgeInsets.symmetric(vertical: 3),
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF1565C0).withOpacity(0.18),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: const Color(0xFF42A5F5).withOpacity(0.55),
                                      width: 1,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      const Icon(Icons.badge, color: Color(0xFF42A5F5), size: 10),
                                      const SizedBox(width: 5),
                                      Flexible(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.end,
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              'คำเชิญพนักงาน',
                                              style: AppTextStyles.caption.copyWith(
                                                color: const Color(0xFF42A5F5),
                                                fontWeight: FontWeight.bold,
                                                fontSize: 9,
                                              ),
                                              maxLines: 1,
                                            ),
                                            if (displayOrganizationName || jobTitle.isNotEmpty)
                                              Text(
                                                displayOrganizationName && jobTitle.isNotEmpty
                                                    ? '$organizationName • $jobTitle'
                                                    : (displayOrganizationName
                                                        ? organizationName
                                                        : jobTitle),
                                                style: AppTextStyles.caption.copyWith(
                                                  color: Colors.white.withOpacity(0.8),
                                                  fontSize: 8.5,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );

                            // ── Consultation Alert (NEW - Phase 5) ───────────
                            } else if (item['type'] == 'consultation') {
                              final c = item['data'] as Map<String, dynamic>;
                              final consultId = c['id']?.toString() ?? '';
                              final packageName = c['packageName']?.toString() ?? 'คำร้องขอปรึกษา';
                              final bodyArea = c['bodyArea']?.toString() ?? 'ไม่ระบุบริเวณ';
                              return Dismissible(
                                key: Key('consult_alert_$consultId'),
                                direction: DismissDirection.horizontal,
                                onDismissed: (_) =>
                                    onConsultationAlertDismissed?.call(consultId),
                                background: Container(
                                  alignment: Alignment.centerRight,
                                  padding: const EdgeInsets.only(right: 10),
                                  child: const Icon(Icons.close, color: Colors.white70, size: 18),
                                ),
                                secondaryBackground: Container(
                                  alignment: Alignment.centerLeft,
                                  padding: const EdgeInsets.only(left: 10),
                                  child: const Icon(Icons.close, color: Colors.white70, size: 18),
                                ),
                                child: GestureDetector(
                                  onTap: () => onConsultationAlertTapped?.call(consultId),
                                  child: Container(
                                    margin: const EdgeInsets.symmetric(vertical: 3),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 5),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF1A6B1A).withOpacity(0.18),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: const Color(0xFF4CAF50).withOpacity(0.55),
                                        width: 1,
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        const Icon(
                                          Icons.medical_services_rounded,
                                          color: Color(0xFF4CAF50),
                                          size: 10,
                                        ),
                                        const SizedBox(width: 5),
                                        Flexible(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.end,
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(
                                                'คำขอปรึกษาใหม่',
                                                style: AppTextStyles.caption.copyWith(
                                                  color: const Color(0xFF4CAF50),
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 9,
                                                ),
                                                maxLines: 1,
                                              ),
                                              Text(
                                                '$packageName \u2022 $bodyArea',
                                                style: AppTextStyles.caption.copyWith(
                                                  color: Colors.white.withOpacity(0.8),
                                                  fontSize: 8.5,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );

                            // ── Emergency / Thai Mhung Alert ─────────────────
                            } else if (item['type'] == 'alert') {
                              final alert = item['data'];
                              final videoId = alert['videoId']?.toString() ?? '';
                              final categoryName = alert['categoryName'] ?? 'แจ้งเหตุ';
                              final isVolunteer = alert['isVolunteer'] == true;

                              final distanceVal = alert['distance'] as double? ?? 0.0;
                              String distanceText = '';
                              if (distanceVal > 0) {
                                if (distanceVal < 1000) {
                                  distanceText = ' ${distanceVal.toStringAsFixed(0)} ม.';
                                } else {
                                  distanceText = ' ${(distanceVal / 1000).toStringAsFixed(1)} กม.';
                                }
                              }

                              final text = (isVolunteer ? 'ขอจิตอาสาช่วย$categoryName' : 'เกิด$categoryName') + distanceText;
                              final textColor = isVolunteer ? const Color(0xFFF5A623) : const Color(0xFFFF3B30);
                              final icon = isVolunteer ? Icons.volunteer_activism : Icons.emergency;

                              return Dismissible(
                                key: Key(videoId),
                                direction: DismissDirection.horizontal,
                                onDismissed: (dir) {
                                  if (dir == DismissDirection.endToStart) {
                                    onAlertDismissed?.call(videoId);
                                  } else {
                                    onAlertTapped?.call(videoId);
                                  }
                                },
                                background: Container(
                                  alignment: Alignment.centerLeft,
                                  padding: const EdgeInsets.only(left: 10),
                                  child: const Icon(Icons.arrow_forward, color: Colors.white70, size: 20),
                                ),
                                secondaryBackground: Container(
                                  alignment: Alignment.centerRight,
                                  padding: const EdgeInsets.only(right: 10),
                                  child: const Icon(Icons.close, color: Colors.white70, size: 20),
                                ),
                                child: GestureDetector(
                                  onTap: () => onAlertTapped?.call(videoId),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 4),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        Icon(icon, color: textColor, size: 9),
                                        const SizedBox(width: 4),
                                        Flexible(
                                          child: Text(
                                            text,
                                            style: AppTextStyles.caption.copyWith(
                                              color: textColor,
                                              fontWeight: FontWeight.w500,
                                            ),
                                            textAlign: TextAlign.right,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );

                            // ── Medicine Reminder ─────────────────────────────
                            } else {
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 4),
                                child: Text(
                                  'อีก 10 นาที\nทานยา มื้อเย็น\nทานยา มื้อก่อนนอน',
                                  textAlign: TextAlign.right,
                                  style: AppTextStyles.bodySmall.copyWith(
                                    color: AppColors.textOnPrimary,
                                  ),
                                ),
                              );
                            }
                          }).whereType<Widget>().toList(),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildShimmerNotifications() {
    return Shimmer.fromColors(
      baseColor: Colors.white.withOpacity(0.2),
      highlightColor: Colors.white.withOpacity(0.4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Container(
            width: 120,
            height: 12,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 8),
          Container(
            width: 150,
            height: 12,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            width: 100,
            height: 24,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScrollableNotificationContent extends StatefulWidget {
  final Widget child;
  const _ScrollableNotificationContent({required this.child});

  @override
  State<_ScrollableNotificationContent> createState() => _ScrollableNotificationContentState();
}

class _ScrollableNotificationContentState extends State<_ScrollableNotificationContent> {
  late ScrollController _scrollController;
  bool _showIndicator = false;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkScrollability();
    });
  }

  void _checkScrollability() {
    if (_scrollController.hasClients) {
      final isScrollable = _scrollController.position.maxScrollExtent > 0;
      final isAtBottom = _scrollController.offset >= _scrollController.position.maxScrollExtent - 5;
      final shouldShow = isScrollable && !isAtBottom;
      if (_showIndicator != shouldShow) {
        setState(() {
          _showIndicator = shouldShow;
        });
      }
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            if (notification is ScrollUpdateNotification) {
              _checkScrollability();
            }
            return false;
          },
          child: Scrollbar(
            controller: _scrollController,
            thumbVisibility: true,
            thickness: 4,
            radius: const Radius.circular(4),
            child: SingleChildScrollView(
              controller: _scrollController,
              physics: const AlwaysScrollableScrollPhysics(),
              child: widget.child,
            ),
          ),
        ),
        Positioned(
          bottom: 0,
          right: 16,
          child: IgnorePointer(
            child: AnimatedOpacity(
              opacity: _showIndicator ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 300),
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.keyboard_arrow_down,
                  color: Colors.white,
                  size: 16,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
