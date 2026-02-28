import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../../shared/widgets/online_providers_badge.dart';

/// Header Section Widget สำหรับหน้า Home
/// แสดงข้อมูลสถานะสุขภาพ, โปรไฟล์, และข้อมูลทานยา
class HomeHeaderSection extends StatelessWidget {
  final GlobalKey? sectionKey;
  final VoidCallback? onHealthTap;
  final VoidCallback? onProfileTap;
  final String? headerText;

  const HomeHeaderSection({
    super.key,
    this.sectionKey,
    this.onHealthTap,
    this.onProfileTap,
    this.headerText,
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
                      child: FittedBox(
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
              maxWidth: MediaQuery.of(context).size.width * 0.75, // ไม่เกิน 75% ของความกว้างหน้าจอ
              maxHeight: 96, // จำกัดความสูง (ประมาณ 3 บรรทัด) เพื่อไม่ให้ล้นกระทบ HomeHeaderSection
            ),
            child: _ScrollableNotificationContent(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'อีก 10 นาที\nทา4545646545646514324564651531465451536454561465451325145645215614615นยา\nทานยา\nทานยา\nทานยา',
                    textAlign: TextAlign.right,
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.textOnPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.textOnPrimary.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'เกิดเหตุด่วน 3 แห่ง',
                      style: AppTextStyles.caption.copyWith(
                        color: AppColors.textOnPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScrollableNotificationContent extends StatefulWidget {
  final Widget child;
  const _ScrollableNotificationContent({Key? key, required this.child}) : super(key: key);

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
      alignment: Alignment.centerRight,
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
            thumbColor: AppColors.textOnPrimary.withOpacity(0.5), // ทำสี scrollbar ให้กลืนกับหน้าจอ
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
                    AppColors.primary.withOpacity(0.0),
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
                  color: Colors.black.withOpacity(0.2), // วงกลมดำโปร่งแสงเป็นพื้นหลัง
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
