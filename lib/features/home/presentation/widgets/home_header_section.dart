import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';

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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // กดเพื่อไปหน้า Health
                GestureDetector(
                  onTap: onHealthTap,
                  child: Text(
                    headerText ?? 'สุขภาพ "ดี"',
                    style: AppTextStyles.bodyLarge.copyWith(
                      color: AppColors.textOnPrimary,
                      fontWeight: FontWeight.w600,
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
          
          // Right Side: Medicine Reminder & Popular Badge
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'อีก 10 นาที\nทานยา',
                textAlign: TextAlign.right,
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.textOnPrimary,
                  height: 1.4,
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
        ],
      ),
    );
  }
}
