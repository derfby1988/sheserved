import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';
import 'package:shimmer/shimmer.dart';

/// Header Section Widget สำหรับหน้า Home
/// แสดงข้อมูลสถานะสุขภาพ, โปรไฟล์, และข้อมูลทานยา
class HomeHeaderSection extends StatelessWidget {
  final GlobalKey? sectionKey;
  final VoidCallback? onHealthTap;
  final VoidCallback? onProfileTap;
  final String? headerText;
  final bool isLoading;
  final int emergencyCount;
  final String? emergencyMessage;
  final VoidCallback? onEmergencyTap;

  const HomeHeaderSection({
    super.key,
    this.sectionKey,
    this.onHealthTap,
    this.onProfileTap,
    this.headerText,
    this.isLoading = false,
    this.emergencyCount = 0,
    this.emergencyMessage,
    this.onEmergencyTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      key: sectionKey,
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      decoration: BoxDecoration(
        color: AppColors.primary,
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
                  crossAxisAlignment: CrossAxisAlignment.center, // จัดกึ่งกลางสัมพันธ์กันเองระหว่างข้อความและรูปโปรไฟล์
                  mainAxisSize: MainAxisSize.min, // ให้หดตัวตามขนาดเนื้อหาภายใน
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
                                  backgroundColor: Colors.white.withValues(alpha: 0.3),
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
                    // Profile Picture Button - กดเพื่อไปหน้า Login
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
                          ),
                          child: const Icon(
                            Icons.person,
                            color: AppColors.primary,
                            size: 36,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          
          // Right Side: Medicine Reminder & Popular Badge
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.5, // ปรับจาก 75% เหลือ 50%
              maxHeight: 96,
            ),
            child: isLoading 
              ? _buildShimmerNotifications()
              : _ScrollableNotificationContent(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                   Text(
                    'อีก 10 นาที\nทานยา มื้อเย็น\nทานยา มื้อก่อนนอน',
                    textAlign: TextAlign.right,
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.textOnPrimary,
                    ),
                  ),
                  if (emergencyCount > 0) ...[
                    const SizedBox(height: 8),
                    GestureDetector(
                      onTap: onEmergencyTap,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF3B30).withValues(alpha: 0.8), // สีแดงเข้มสำหรับเหตุฉุกเฉิน
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.white24),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.2),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.emergency, color: Colors.white, size: 14),
                            const SizedBox(width: 4),
                            Text(
                              emergencyMessage ?? (emergencyCount == 1 ? 'มีเหตุใกล้คุณ!' : 'มีเหตุ $emergencyCount แห่งใกล้คุณ'),
                              style: AppTextStyles.caption.copyWith(
                                color: AppColors.textOnPrimary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ] else ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.textOnPrimary.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        'สถานะปกติ',
                        style: AppTextStyles.caption.copyWith(
                          color: AppColors.textOnPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShimmerNotifications() {
    return Shimmer.fromColors(
      baseColor: Colors.white.withValues(alpha: 0.2),
      highlightColor: Colors.white.withValues(alpha: 0.4),
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
      // ตรวจสอบว่ามีเนื้อหาให้เลื่อนลงต่อได้หรือไม่
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
          child: RawScrollbar(
            controller: _scrollController,
            thumbColor: AppColors.textOnPrimary.withValues(alpha: 0.5),
            radius: const Radius.circular(4),
            thickness: 3,
            child: SingleChildScrollView(
              controller: _scrollController,
              child: widget.child,
            ),
          ),
        ),
        // เงาไล่ระดับ (Gradient Fade)
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          height: 20, // ความสูงของเงา
          child: IgnorePointer(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    AppColors.primary.withValues(alpha: 0.0),
                    AppColors.primary,
                  ],
                ),
              ),
            ),
          ),
        ),
        // ไอคอนชี้ลง เมื่อไม่สามารถเลื่อนได้แล้ว ไอคอนจะจางหายไป (AnimatedOpacity)
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
                  color: Colors.black.withValues(alpha: 0.2), // วงกลมดำโปร่งแสงเป็นพื้นหลัง
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.keyboard_arrow_down,
                  color: Colors.white,
                  size: 16, // ปรับขนาดไอคอนเล็กลงนิดหน่อยเพื่อให้เข้ากับวงกลมรอบขอบ
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
