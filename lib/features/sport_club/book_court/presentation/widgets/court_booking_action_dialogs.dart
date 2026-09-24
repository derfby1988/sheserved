import 'package:flutter/material.dart';

/// Confirmation/reason dialogs for the venue booking lifecycle.
class CourtBookingActionDialogs {
  /// Booker cancellation: returns true when confirmed.
  static Future<bool> confirmUserCancel(
    BuildContext context, {
    required String venueName,
    required int cutoffMinutes,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('ยกเลิกการจอง'),
        content: Text(
          'ยืนยันยกเลิกการจองที่ $venueName?\n'
          'ยกเลิกได้ฟรีถึง $cutoffMinutes นาทีก่อนเวลาเริ่ม',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('ไม่ยกเลิก'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('ยืนยันยกเลิก'),
          ),
        ],
      ),
    );
    return ok == true;
  }

  /// Manager cancellation/rejection: returns the reason, or null.
  static Future<String?> askReason(
    BuildContext context, {
    required String title,
    required String hint,
  }) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 300,
          decoration: InputDecoration(
            hintText: hint,
            border: const OutlineInputBorder(),
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
  }

  /// Explains that the booker cancellation cutoff has passed.
  static Future<void> showCutoffPassed(BuildContext context) {
    return showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('เลยเวลายกเลิกแล้ว'),
        content: const Text(
          'การจองนี้เลยกำหนดยกเลิกฟรีแล้ว กรุณาติดต่อสนามโดยตรง',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('รับทราบ'),
          ),
        ],
      ),
    );
  }

  /// Explains that the pending slot was taken; offers change-slot or cancel.
  static Future<String?> showSlotConflict(BuildContext context) {
    return showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('ช่วงเวลานี้ไม่ว่างแล้ว'),
        content: const Text(
          'ช่วงเวลาที่คุณขอถูกจองไปแล้ว คำขอยังคงรออนุมัติอยู่ — '
          'คุณสามารถเปลี่ยนเวลาในสนามเดิมหรือยกเลิกคำขอได้',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, 'cancel'),
            child: const Text('ยกเลิกคำขอ'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, 'change'),
            child: const Text('เปลี่ยนเวลา'),
          ),
        ],
      ),
    );
  }
}
