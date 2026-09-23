import 'package:flutter/material.dart';
import 'package:sheserved/core/constants/app_colors.dart';

/// Filter button shared by the quick-filter row and the collapsed-filter
/// overlay, so both states read as the same control.
class SportClubFilterButton extends StatelessWidget {
  final int activeFilterCount;
  final String filterSummary;
  final VoidCallback onTap;

  const SportClubFilterButton({
    super.key,
    required this.activeFilterCount,
    required this.filterSummary,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final hasActiveFilter = activeFilterCount > 0;
    return Semantics(
      button: true,
      label: 'เปิดตัวกรองทั้งหมด $filterSummary',
      child: Tooltip(
        message: filterSummary,
        child: Badge(
          isLabelVisible: hasActiveFilter,
          offset: const Offset(-2, 2),
          backgroundColor: AppColors.primaryDark,
          label: Text(
            '$activeFilterCount',
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(14),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 44,
                height: 38,
                decoration: BoxDecoration(
                  color: hasActiveFilter
                      ? AppColors.primary.withValues(alpha: 0.15)
                      : Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: hasActiveFilter
                        ? AppColors.primaryDark
                        : Colors.grey.shade300,
                    width: hasActiveFilter ? 1.6 : 1.0,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: hasActiveFilter
                          ? AppColors.primary.withValues(alpha: 0.2)
                          : Colors.black.withValues(alpha: 0.04),
                      blurRadius: 4,
                      offset: const Offset(0, 1.5),
                    ),
                  ],
                ),
                child: const Center(
                  child: Icon(
                    Icons.tune_rounded,
                    size: 20,
                    color: AppColors.primaryDark,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
