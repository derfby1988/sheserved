import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_text_styles.dart';

/// HomeErpCard
///
/// Replaces `HomePharmacyCard` when a logged‑in user belongs to an organization
/// (has profession_id). Provides a single entry point to the ERP Dashboard.
/// Matches HomePharmacyCard layout exactly for dynamic card replacement.
class HomeErpCard extends StatelessWidget {
  final VoidCallback? onEnterTap;

  const HomeErpCard({Key? key, this.onEnterTap}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    final screenWidth = MediaQuery.of(context).size.width;

    Widget cardContent = Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadow,
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Icon
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: const Color(0xFFF0F7FF),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.dashboard,
              size: 32,
              color: Color(0xFF0066FF),
            ),
          ),

          const SizedBox(width: 16),

          // Content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'ERP Dashboard',
                    style: AppTextStyles.heading5.copyWith(
                      color: AppColors.textPrimary,
                    ),
                    maxLines: 1,
                  ),
                ),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'จัดการคลินิก / สถานบริการ',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.textSecondary,
                    ),
                    maxLines: 1,
                  ),
                ),
                const SizedBox(height: 8),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'POS / คลังสินค้า / บัญชี / HR',
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.textHint,
                    ),
                    maxLines: 1,
                  ),
                ),
              ],
            ),
          ),

          // Enter Button
          ElevatedButton(
            onPressed: onEnterTap ?? () {
              Navigator.of(context).pushNamed('/erp');
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0066FF),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 0,
            ),
            child: Text(
              'เข้า',
              style: AppTextStyles.buttonSmall.copyWith(
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );

    // Wrap with width constraint for landscape (same as HomePharmacyCard)
    if (isLandscape) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Align(
          alignment: Alignment.center,
          child: SizedBox(
            width: screenWidth * 0.5,
            child: cardContent,
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: cardContent,
    );
  }
}
