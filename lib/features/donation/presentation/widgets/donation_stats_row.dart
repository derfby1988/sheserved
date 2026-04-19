import 'package:flutter/material.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../models/donation_models.dart';

/// แถวแสดงสถานะการรับบริจาค (ร้องขอ, ยอดที่ได้, ยังขาด)
class DonationStatsRow extends StatelessWidget {
  final DonationStats stats;

  const DonationStatsRow({
    super.key,
    required this.stats,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: _buildStatCard(
              title: 'ร้องขอ',
              value: stats.requested,
              color: const Color(0xFFF8B619), // Orange
              accentColor: const Color(0xFF76A5A5),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _buildStatCard(
              title: 'ยอดที่ได้',
              value: stats.received,
              color: const Color(0xFF58910F), // Green
              accentColor: const Color(0xFF76A5A5),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _buildStatCard(
              title: 'ยังขาด',
              value: stats.remaining,
              color: const Color(0xFFFF0000), // Red
              accentColor: const Color(0xFF76A5A5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard({
    required String title,
    required double value,
    required Color color,
    required Color accentColor,
  }) {
    return Container(
      height: 82,
      decoration: BoxDecoration(
        color: accentColor,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Stack(
        children: [
          // Circle indicator
          Positioned(
            left: 8,
            top: 7,
            child: Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
              ),
            ),
          ),
          // Title
          Positioned(
            left: 30, // หลบไอคอนวงกลม
            right: 4,
            top: 4,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.center,
              child: Text(
                title,
                textAlign: TextAlign.center,
                style: AppTextStyles.bodyMedium.copyWith(
                  color: Colors.black,
                  fontWeight: FontWeight.w600,
                  fontSize: 14, // ลดขนาดเริ่มต้นนิดหน่อย
                ),
              ),
            ),
          ),
          // Value
          Positioned(
            left: 4,
            right: 4,
            top: 27,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.center,
              child: Text(
                value.toInt().toString(),
                textAlign: TextAlign.center,
                style: AppTextStyles.heading2.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
