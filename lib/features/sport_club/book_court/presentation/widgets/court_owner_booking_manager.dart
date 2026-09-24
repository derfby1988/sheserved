import 'package:flutter/material.dart';
import 'package:sheserved/core/constants/app_colors.dart';

import '../../data/book_court_models.dart';

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
              '${b.courtName ?? ''} • ${_fmtRange(b.startsAt, b.endsAt)}',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
            ),
            Text(
              'ผู้จอง: ${b.bookerName ?? 'ผู้ใช้'}',
              style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
            ),
            if (b.priceAmount != null)
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
      ),
    );
  }

  Future<void> _askReason(
    BuildContext context,
    Future<void> Function(String) action,
  ) async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('ระบุเหตุผล'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 300,
          decoration: const InputDecoration(
            hintText: 'เช่น สนามซ่อมบำรุง / ตารางเต็ม',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            onPressed: () {
              final text = controller.text.trim();
              if (text.isEmpty) return;
              Navigator.pop(c, text);
            },
            child: const Text('ยืนยัน'),
          ),
        ],
      ),
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

  static String _fmtRange(DateTime start, DateTime end) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${start.day}/${start.month} ${two(start.hour)}:${two(start.minute)}'
        '–${two(end.hour)}:${two(end.minute)}';
  }
}
