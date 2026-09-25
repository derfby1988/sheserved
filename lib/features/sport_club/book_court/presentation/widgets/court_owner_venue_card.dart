import 'package:flutter/material.dart';
import 'package:sheserved/core/constants/app_colors.dart';

import '../../data/book_court_models.dart';

/// Compact card for a managed venue in the owner dashboard.
class CourtOwnerVenueCard extends StatelessWidget {
  final VenueSummary venue;
  final VoidCallback? onManage;
  final VoidCallback? onViewBookings;

  const CourtOwnerVenueCard({
    super.key,
    required this.venue,
    this.onManage,
    this.onViewBookings,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    venue.name,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (venue.memberRole == 'manager')
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Text(
                      'ผู้จัดการ',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ),
                _statusChip(venue.status),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              [venue.district, venue.province].whereType<String>().join(', '),
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  '${venue.courtCount} สนาม',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                ),
                const SizedBox(width: 12),
                if (venue.averageRating != null)
                  Text(
                    '⭐ ${venue.averageRating!.toStringAsFixed(1)} (${venue.reviewCount})',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                  ),
                const Spacer(),
                TextButton(
                  onPressed: onViewBookings,
                  child: const Text('การจอง'),
                ),
                const SizedBox(width: 4),
                FilledButton.tonal(
                  style: FilledButton.styleFrom(
                    foregroundColor: AppColors.primaryDark,
                  ),
                  onPressed: onManage,
                  child: const Text('จัดการ'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static Widget _statusChip(VenueStatus? status) {
    final (label, color) = switch (status) {
      VenueStatus.draft => ('แบบร่าง', Colors.blueGrey),
      VenueStatus.approved => ('อนุมัติแล้ว', Colors.green),
      VenueStatus.pending => ('รอตรวจสอบ', Colors.orange),
      VenueStatus.suspended => ('ถูกระงับ', Colors.red),
      VenueStatus.rejected => ('ไม่ผ่าน', Colors.red),
      _ => ('ไม่ทราบ', Colors.grey),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}
