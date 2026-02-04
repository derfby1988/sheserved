import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';

/// Interesting Section Widget - น่าสนใจ
class HomeInterestingSection extends StatelessWidget {
  final VoidCallback? onMoreTap;
  final Function(int index)? onItemTap;
  final List<InterestingItem> items;

  const HomeInterestingSection({
    super.key,
    this.onMoreTap,
    this.onItemTap,
    this.items = const [],
  });

  @override
  Widget build(BuildContext context) {
    // Default items if not provided
    final displayItems = items.isEmpty
        ? [
            const InterestingItem(
              title: 'จัดอันดับการบริจาค',
              subtitle: 'สังคม ผู้สูงอายุ',
              value1: '85%',
              value2: '99%',
            ),
            const InterestingItem(
              title: 'จัดอันดับการบริจาค',
              subtitle: 'สังคม ผู้สูงอายุ',
              value1: '85%',
              value2: '99%',
            ),
            const InterestingItem(
              title: 'อาสาสมัคร',
              subtitle: 'ชุมชน สิ่งแวดล้อม',
              value1: '72%',
              value2: '88%',
            ),
          ]
        : items;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section Header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  'น่าสนใจ',
                  style: AppTextStyles.heading5.copyWith(
                    color: AppColors.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              TextButton(
                onPressed: onMoreTap,
                child: Text(
                  'เพิ่มเติม',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
        ),
        
        const SizedBox(height: 12),
        
        // Cards - Fixed width, horizontal scroll
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              for (int i = 0; i < displayItems.length; i++) ...[
                GestureDetector(
                  onTap: () => onItemTap?.call(i),
                  child: _buildInterestingCard(displayItems[i]),
                ),
                if (i < displayItems.length - 1) const SizedBox(width: 12),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildInterestingCard(InterestingItem item) {
    return Container(
      width: 160, // Fixed width
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadow,
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Icon
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.background,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.trending_up,
              color: AppColors.textPrimary,
              size: 24,
            ),
          ),
          
          const SizedBox(height: 12),
          
          // Title
          Text(
            item.title,
            style: AppTextStyles.bodyMedium.copyWith(
              fontWeight: FontWeight.w600,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          
          const SizedBox(height: 4),
          
          // Subtitle
          Text(
            item.subtitle,
            style: AppTextStyles.caption,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          
          const SizedBox(height: 8),
          
          // Values
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                item.value1,
                style: AppTextStyles.bodyLarge.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                item.value2,
                style: AppTextStyles.bodyLarge.copyWith(
                  color: AppColors.success,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Data model for Interesting Item
class InterestingItem {
  final String title;
  final String subtitle;
  final String value1;
  final String value2;

  const InterestingItem({
    required this.title,
    required this.subtitle,
    required this.value1,
    required this.value2,
  });
}
