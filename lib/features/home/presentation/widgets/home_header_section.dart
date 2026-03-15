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
  final List<Map<String, dynamic>> alerts;
  final Function(String videoId)? onAlertDismissed;
  final Function(String videoId)? onAlertTapped;

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
              maxWidth: MediaQuery.of(context).size.width * 0.65, // ปรับเป็น 65%
              maxHeight: 96,
            ),
            child: isLoading 
              ? _buildShimmerNotifications()
              : _ScrollableNotificationContent(
              child: Builder(
                builder: (context) {
                  // สร้าง list รวมระหว่างรายการยา (จำลอง) และเหตุฉุกเฉิน
                  final List<Map<String, dynamic>> combinedItems = [];
                  
                  for (var alert in alerts) {
                    combinedItems.add({
                      'time': alert['createdAt'] as DateTime? ?? DateTime.now(),
                      'type': 'alert',
                      'data': alert,
                    });
                  }

                  // รายการยา (Mock)
                  combinedItems.add({
                    'time': DateTime.now().subtract(const Duration(hours: 1)), // จำลองว่าเกิดก่อน
                    'type': 'medicine',
                  });

                  // เรียงลำดับจากใหม่สุดไปเก่าสุด
                  combinedItems.sort((a, b) => (b['time'] as DateTime).compareTo(a['time'] as DateTime));

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: combinedItems.map((item) {
                      if (item['type'] == 'alert') {
                        final alert = item['data'];
                        final videoId = alert['videoId']?.toString() ?? '';
                        final categoryName = alert['categoryName'] ?? 'ฉุกเฉิน';
                        
                        // กรณีมีหลายเหตุ จะลิสต์แยกกัน หรือรวมกันก็ได้ ในที่นี้แยกกันตามเวลาดังนั้นใช้ "มีเหตุ + ประเภท"
                        final text = alerts.length == 1 ? 'มีเหตุ$categoryName' : 'มีเหตุ$categoryName';

                        return Dismissible(
                          key: Key(videoId),
                          direction: DismissDirection.horizontal,
                          onDismissed: (dir) {
                            if (dir == DismissDirection.endToStart) { // ปัดซ้าย
                              onAlertDismissed?.call(videoId);
                            } else { // ปัดขวา
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
                              child: Text(
                                text,
                                style: AppTextStyles.caption.copyWith(
                                  color: const Color(0xFFFF3B30),
                                  fontWeight: FontWeight.bold,
                                ),
                                textAlign: TextAlign.right,
                              ),
                            ),
                          ),
                        );
                      } else {
                        // Medicine Reminder
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
                    }).toList(),
                  );
                }
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
