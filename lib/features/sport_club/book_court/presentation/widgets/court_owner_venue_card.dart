import 'package:flutter/material.dart';
import 'package:sheserved/shared/widgets/neumorphic/neumorphic.dart';

import '../../data/book_court_models.dart';

/// Compact card for a managed venue in the owner dashboard.
class CourtOwnerVenueCard extends StatelessWidget {
  final VenueSummary venue;
  final int pendingCount;
  final VoidCallback? onManage;
  final VoidCallback? onViewBookings;

  const CourtOwnerVenueCard({
    super.key,
    required this.venue,
    this.pendingCount = 0,
    this.onManage,
    this.onViewBookings,
  });

  @override
  Widget build(BuildContext context) {
    return NeumorphicContainer(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.all(14),
      borderRadius: 14,
      depth: 4,
      blur: 8,
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
                    color: NeumorphicTheme.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (venue.memberRole == 'manager')
                const Padding(
                  padding: EdgeInsets.only(right: 6),
                  child: Text(
                    'ผู้จัดการ',
                    style: TextStyle(
                      fontSize: 11,
                      color: NeumorphicTheme.textSecondary,
                    ),
                  ),
                ),
              _statusChip(venue.status),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            [venue.district, venue.province].whereType<String>().join(', '),
            style: const TextStyle(
              fontSize: 12,
              color: NeumorphicTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                '${venue.courtCount} สนาม',
                style: const TextStyle(
                  fontSize: 12,
                  color: NeumorphicTheme.textSecondary,
                ),
              ),
              const SizedBox(width: 12),
              if (venue.averageRating != null)
                Text(
                  '⭐ ${venue.averageRating!.toStringAsFixed(1)} (${venue.reviewCount})',
                  style: const TextStyle(
                    fontSize: 12,
                    color: NeumorphicTheme.textSecondary,
                  ),
                ),
              const Spacer(),
              Badge(
                isLabelVisible: pendingCount > 0,
                label: Text('$pendingCount'),
                child: NeumorphicPillButton(
                  onPressed: onViewBookings,
                  icon: Icons.calendar_month_rounded,
                  text: 'การจอง',
                  height: 34,
                  fontSize: 12.5,
                  iconSize: 15,
                  depth: 3,
                  blur: 6,
                ),
              ),
              const SizedBox(width: 8),
              NeumorphicPillButton(
                onPressed: onManage,
                icon: Icons.tune_rounded,
                text: 'จัดการ',
                color: NeumorphicTheme.primaryBlue,
                height: 34,
                fontSize: 12.5,
                iconSize: 15,
                depth: 3,
                blur: 6,
              ),
            ],
          ),
        ],
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
