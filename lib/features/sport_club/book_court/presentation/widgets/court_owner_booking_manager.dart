import 'package:flutter/material.dart';
import 'package:sheserved/core/constants/app_colors.dart';
import 'package:sheserved/shared/widgets/glass/glass_text_prompt_dialog.dart';
import 'package:sheserved/shared/widgets/neumorphic/neumorphic.dart';

import '../../data/book_court_models.dart';
import '../../domain/venue_local_time.dart';

/// A booking row in the owner queue with approve/reject/cancel actions.
class CourtOwnerBookingManager extends StatelessWidget {
  final VenueBooking booking;
  final Future<void> Function()? onApprove;
  final Future<void> Function(String reason)? onReject;
  final Future<void> Function(String reason)? onCancel;

  const CourtOwnerBookingManager({
    super.key,
    required this.booking,
    this.onApprove,
    this.onReject,
    this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final b = booking;
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
                  b.venueName ?? b.courtName ?? 'การจอง',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ),
              _statusChip(b.status),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${b.courtName ?? ''} • ${_fmtRange(b)}',
            style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
          ),
          Text(
            'ผู้จอง: ${b.bookerName ?? 'ผู้ใช้'}',
            style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
          ),
          if (b.priceTotal != null)
            Text(
              'ราคารวม ${b.priceTotal!.toStringAsFixed(2)} บาท',
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            )
          else if (b.priceAmount != null)
            Text(
              '${b.priceAmount!.toStringAsFixed(0)} บาท/${b.pricingUnit}',
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          if (b.isPending || b.isConfirmed) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                if (b.isPending) ...[
                  if (onReject != null)
                    TextButton(
                      onPressed: () => _askReason(context, onReject!),
                      child: const Text(
                        'ปฏิเสธ',
                        style: TextStyle(color: Colors.red),
                      ),
                    ),
                  const SizedBox(width: 8),
                  if (onApprove != null)
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.green.shade700,
                      ),
                      onPressed: onApprove,
                      child: const Text('อนุมัติ'),
                    ),
                ] else if (onCancel != null)
                  TextButton(
                    onPressed: () => _askReason(context, onCancel!),
                    child: const Text(
                      'ยกเลิกการจอง',
                      style: TextStyle(color: Colors.red),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _askReason(
    BuildContext context,
    Future<void> Function(String) action,
  ) async {
    final reason = await GlassTextPromptDialog.show(
      context,
      title: 'ระบุเหตุผล',
      hint: 'เช่น ปิดซ่อมบำรุง / ตารางเต็ม',
    );
    if (reason != null) await action(reason);
  }

  static Widget _statusChip(VenueBookingStatus status) {
    final (label, color) = switch (status) {
      VenueBookingStatus.pending => ('รออนุมัติ', Colors.orange),
      VenueBookingStatus.confirmed => ('ยืนยันแล้ว', Colors.green),
      VenueBookingStatus.cancelled => ('ยกเลิก', Colors.red),
      VenueBookingStatus.rejected => ('ปฏิเสธ', Colors.red),
      VenueBookingStatus.expired => ('หมดอายุ', Colors.grey),
      VenueBookingStatus.awaitingEvidence => ('รอหลักฐาน', Colors.amber),
      VenueBookingStatus.forfeited => ('หมดเวลาหลักฐาน', Colors.red),
      VenueBookingStatus.completed => ('เสร็จสิ้น', AppColors.primaryDark),
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

  /// Booking instants are stored UTC — render them in the venue's timezone.
  static String _fmtRange(VenueBooking booking) {
    String two(int n) => n.toString().padLeft(2, '0');
    final start = VenueLocalTime.wallTimeOfInstant(
      booking.startsAt,
      booking.timezone,
    );
    final end = VenueLocalTime.wallTimeOfInstant(
      booking.endsAt,
      booking.timezone,
    );
    return '${start.day}/${start.month} ${two(start.hour)}:${two(start.minute)}'
        '–${two(end.hour)}:${two(end.minute)}';
  }
}
