import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

/// Shown when no groups match the current filters.
class EmptyFilterState extends StatelessWidget {
  final int activeFilterCount;
  final String filterSummary;
  final VoidCallback onClearFilters;

  const EmptyFilterState({
    super.key,
    required this.activeFilterCount,
    required this.filterSummary,
    required this.onClearFilters,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 56, horizontal: 16),
      child: Column(
        children: [
          Icon(
            Icons.filter_alt_off_rounded,
            size: 48,
            color: Colors.grey.shade400,
          ),
          const SizedBox(height: 12),
          const Text(
            'ไม่พบก๊วนตามตัวกรองที่เลือก',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(
            activeFilterCount == 0
                ? 'ลองรีเฟรชหรือเลือกกีฬาอื่น'
                : filterSummary,
          ),
          if (activeFilterCount > 0) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onClearFilters,
              icon: const Icon(Icons.clear_all_rounded),
              label: const Text('ล้างตัวกรอง'),
            ),
          ],
        ],
      ),
    );
  }
}

/// Skeleton placeholder card shown while the feed is loading.
class SkeletonGroupCard extends StatelessWidget {
  const SkeletonGroupCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.5),
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Shimmer.fromColors(
          baseColor: Colors.grey.shade300,
          highlightColor: Colors.grey.shade100,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 120,
                height: 14,
                color: Colors.white.withValues(alpha: 0.5),
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                height: 18,
                color: Colors.white.withValues(alpha: 0.5),
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                height: 12,
                color: Colors.white.withValues(alpha: 0.5),
              ),
              const SizedBox(height: 6),
              Container(
                width: 180,
                height: 12,
                color: Colors.white.withValues(alpha: 0.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
