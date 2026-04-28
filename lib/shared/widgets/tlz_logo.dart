import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_text_styles.dart';

/// Logo Widget for Sheserved
class TlzLogo extends StatelessWidget {
  final double size;
  final bool showSubtitle;
  final bool isDark;

  const TlzLogo({
    super.key,
    this.size = 1.0,
    this.showSubtitle = true,
    this.isDark = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Logo Icon (Tree + Animal)
        Container(
          width: 80 * size,
          height: 80 * size,
          decoration: BoxDecoration(
            gradient: AppColors.primaryGradient,
            borderRadius: BorderRadius.circular(20 * size),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withOpacity(0.3),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Tree Icon
              Icon(
                Icons.park,
                size: 48 * size,
                color: AppColors.textOnPrimary,
              ),
              // Small animal icon at bottom right
              Positioned(
                right: 8 * size,
                bottom: 8 * size,
                child: Container(
                  padding: EdgeInsets.all(4 * size),
                  decoration: BoxDecoration(
                    color: AppColors.accent,
                    borderRadius: BorderRadius.circular(8 * size),
                  ),
                  child: Icon(
                    Icons.pets,
                    size: 16 * size,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: 12 * size),
        // Brand Name
        Text(
          'SHESERVED',
          style: AppTextStyles.brand.copyWith(
            fontSize: 24 * size,
            color: isDark ? AppColors.textOnPrimary : AppColors.primary,
          ),
        ),
        if (showSubtitle) ...[
          SizedBox(height: 4 * size),
          Text(
            'valley',
            style: AppTextStyles.brandSubtitle.copyWith(
              fontSize: 14 * size,
              color: isDark
                  ? AppColors.valleyLight
                  : AppColors.valley,
            ),
          ),
        ],
      ],
    );
  }
}

/// Compact Logo for AppBar
class TlzLogoCompact extends StatelessWidget {
  final bool isDark;

  const TlzLogoCompact({
    super.key,
    this.isDark = true,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: isDark ? AppColors.textOnPrimary : AppColors.primary,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            Icons.park,
            size: 24,
            color: isDark ? AppColors.primary : AppColors.textOnPrimary,
          ),
        ),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'SHESERVED',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: isDark ? AppColors.textOnPrimary : AppColors.primary,
                letterSpacing: 0.5,
              ),
            ),
            Text(
              'valley',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w500,
                color: isDark ? AppColors.valleyLight : AppColors.valley,
                letterSpacing: 1,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
