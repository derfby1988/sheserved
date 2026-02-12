import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../../shared/widgets/widgets.dart';
import '../../../health/data/models/health_article_models.dart';

/// Interesting Section Widget - น่าสนใจ
class HomeInterestingSection extends StatelessWidget {
  final VoidCallback? onMoreTap;
  final Function(HealthArticle article)? onItemTap;
  final Function(HealthArticle article)? onBookmarkTap;
  final List<HealthArticle> articles;

  const HomeInterestingSection({
    super.key,
    this.onMoreTap,
    this.onItemTap,
    this.onBookmarkTap,
    required this.articles,
  });

  @override
  Widget build(BuildContext context) {
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
              for (int i = 0; i < articles.length; i++) ...[
                GestureDetector(
                  onTap: () => onItemTap?.call(articles[i]),
                  child: _buildInterestingCard(articles[i]),
                ),
                if (i < articles.length - 1) const SizedBox(width: 12),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildInterestingCard(HealthArticle article) {
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
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Icon Container
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.background,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.trending_up,
                  color: AppColors.primary,
                  size: 24,
                ),
              ),
              
              const SizedBox(height: 12),
              
              // Title
              Text(
                article.title,
                style: AppTextStyles.bodyMedium.copyWith(
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              
              const SizedBox(height: 4),
              
              // Subtitle (Category)
              Text(
                article.category ?? 'ทั่วไป',
                style: AppTextStyles.caption.copyWith(
                  color: AppColors.textSecondary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              
              const SizedBox(height: 8),
              
              // Values (Likes & Views)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.favorite, size: 14, color: AppColors.primary),
                      const SizedBox(width: 4),
                      Text(
                        '${article.likeCount}',
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      const Icon(Icons.visibility, size: 14, color: Colors.grey),
                      const SizedBox(width: 4),
                      Text(
                        '${article.viewCount}',
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          Positioned(
            top: 0,
            right: 0,
            child: RibbonBookmark(
              isBookmarked: article.isBookmarked,
              inactiveColor: Colors.grey.withOpacity(0.3),
              onTap: () => onBookmarkTap?.call(article),
            ),
          ),
        ],
      ),
    );
  }
}
