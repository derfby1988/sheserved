import 'package:flutter/material.dart';
import 'package:sheserved/shared/widgets/glass/glass_confirm_dialog.dart';

/// Phase 6.14 — confirmation dialog for a drafted answer.
///
/// Separated from persistence: [onConfirm] returns `true` only when the
/// answer was saved server-side. While saving, the dialog shows a spinner;
/// on failure it stays open with an inline error so the patient can retry
/// or pick another option. The question keeps `reading` status — no answer
/// is persisted until the RPC succeeds.
class ClosedEndedConfirmationDialog {
  /// Shows the dialog; resolves `true` when the answer was confirmed and
  /// saved (or confirmed in standalone mode without [onConfirm]).
  static Future<bool?> show(
    BuildContext context, {
    required String questionText,
    required String selectedLabel,
    required int selectedIndex,
    required Color optionColor,
    required bool isQuantitative,
    Future<bool> Function()? onConfirm,
  }) {
    return GlassConfirmDialog.show(
      context,
      icon: Icons.check_circle_outline_rounded,
      title: 'ยืนยันคำตอบ',
      content: _ClosedEndedAnswerPreview(
        questionText: questionText,
        selectedLabel: selectedLabel,
        selectedIndex: selectedIndex,
        optionColor: optionColor,
        isQuantitative: isQuantitative,
      ),
      accentColor: optionColor,
      cancelLabel: 'เปลี่ยน',
      confirmLabel: 'ยืนยัน',
      errorMessage: 'บันทึกคำตอบไม่สำเร็จ กรุณาลองใหม่อีกครั้ง',
      onConfirm: onConfirm,
    );
  }
}

class _ClosedEndedAnswerPreview extends StatelessWidget {
  final String questionText;
  final String selectedLabel;
  final int selectedIndex;
  final Color optionColor;
  final bool isQuantitative;

  const _ClosedEndedAnswerPreview({
    required this.questionText,
    required this.selectedLabel,
    required this.selectedIndex,
    required this.optionColor,
    required this.isQuantitative,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.white.withValues(alpha: 0.14),
                Colors.white.withValues(alpha: 0.05),
              ],
            ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: Color.lerp(
                Colors.white,
                optionColor,
                0.4,
              )!.withValues(alpha: 0.60),
              width: 1.4,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isQuantitative) ...[
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    color: optionColor.withValues(alpha: 0.35),
                    border: Border.all(
                      color: optionColor.withValues(alpha: 0.8),
                      width: 1,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      selectedLabel,
                      style: const TextStyle(
                        fontFamily: 'SukhumvitSet',
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Flexible(
                child: Text(
                  isQuantitative ? 'ระดับ $selectedLabel' : selectedLabel,
                  style: const TextStyle(
                    fontFamily: 'SukhumvitSet',
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          questionText,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontFamily: 'SukhumvitSet',
            fontSize: 12,
            color: Colors.white.withValues(alpha: 0.55),
            height: 1.3,
          ),
        ),
      ],
    );
  }
}
