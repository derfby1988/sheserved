import 'package:flutter/material.dart';
import 'package:sheserved/shared/widgets/glass/glass_confirm_dialog.dart';
import 'package:sheserved/shared/widgets/glass/glass_dialog.dart';
import 'package:sheserved/shared/widgets/glass/glass_primitives.dart';
import 'package:sheserved/shared/widgets/glass/glass_text_prompt_dialog.dart';

/// Confirmation/reason dialogs for the venue booking lifecycle.
class CourtBookingActionDialogs {
  /// Booker cancellation: returns true when confirmed.
  static Future<bool> confirmUserCancel(
    BuildContext context, {
    required String venueName,
    required int cutoffMinutes,
  }) async {
    final ok = await GlassConfirmDialog.show(
      context,
      icon: Icons.cancel_outlined,
      title: 'ยกเลิกการจอง',
      accentColor: const Color(0xFFC62828),
      cancelLabel: 'ไม่ยกเลิก',
      confirmLabel: 'ยืนยันยกเลิก',
      maxWidth: 340,
      content: Text(
        'ยืนยันยกเลิกการจองที่ $venueName?\n'
        'ยกเลิกได้ฟรีถึง $cutoffMinutes นาทีก่อนเวลาเริ่ม',
        style: TextStyle(
          fontSize: 12.5,
          color: Colors.white.withValues(alpha: 0.75),
          height: 1.4,
        ),
      ),
      onConfirm: () async => true,
    );
    return ok == true;
  }

  /// Manager cancellation/rejection: returns the reason, or null.
  static Future<String?> askReason(
    BuildContext context, {
    required String title,
    required String hint,
  }) {
    return GlassTextPromptDialog.show(
      context,
      title: title,
      hint: hint,
      confirmLabel: 'ยืนยัน',
    );
  }

  /// Explains that the booker cancellation cutoff has passed.
  static Future<void> showCutoffPassed(BuildContext context) {
    return GlassDialog.show<void>(
      context: context,
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      contentPadding: EdgeInsets.zero,
      builder: (dialogContext) => ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 340),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'เลยเวลายกเลิกแล้ว',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'การจองนี้เลยกำหนดยกเลิกฟรีแล้ว กรุณาติดต่อสนามโดยตรง',
                style: TextStyle(
                  fontSize: 12.5,
                  color: Colors.white.withValues(alpha: 0.75),
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 16),
              GlassActionButton(
                label: 'รับทราบ',
                isFilled: true,
                fillColor: const Color(0xFF2563EB),
                onTap: () => Navigator.of(dialogContext).pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Explains that the pending slot was taken; offers change-slot or cancel.
  static Future<String?> showSlotConflict(BuildContext context) {
    return GlassDialog.show<String>(
      context: context,
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      panelAccentColor: const Color(0xFF2563EB),
      contentPadding: EdgeInsets.zero,
      builder: (dialogContext) => ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 340),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'ช่วงเวลานี้ไม่ว่างแล้ว',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'ช่วงเวลาที่คุณขอถูกจองไปแล้ว คำขอยังคงรออนุมัติอยู่ — '
                'คุณสามารถเปลี่ยนเวลาในสนามเดิมหรือยกเลิกคำขอได้',
                style: TextStyle(
                  fontSize: 12.5,
                  color: Colors.white.withValues(alpha: 0.75),
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: GlassActionButton(
                      label: 'ยกเลิกคำขอ',
                      onTap: () =>
                          Navigator.of(dialogContext).pop('cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GlassActionButton(
                      label: 'เปลี่ยนเวลา',
                      isFilled: true,
                      fillColor: const Color(0xFF2563EB),
                      onTap: () =>
                          Navigator.of(dialogContext).pop('change'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
