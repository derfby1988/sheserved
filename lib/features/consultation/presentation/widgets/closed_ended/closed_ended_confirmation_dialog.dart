import 'dart:ui';

import 'package:flutter/material.dart';

import 'closed_ended_glass_primitives.dart';

/// Phase 6.14 — confirmation dialog for a drafted answer.
///
/// Separated from persistence: [onConfirm] returns `true` only when the
/// answer was saved server-side. While saving, the dialog shows a spinner;
/// on failure it stays open with an inline error so the patient can retry
/// or pick another option. The question keeps `reading` status — no answer
/// is persisted until the RPC succeeds.
class ClosedEndedConfirmationDialog extends StatefulWidget {
  final String questionText;
  final String selectedLabel;
  final int selectedIndex;
  final Color optionColor;
  final bool isQuantitative;

  /// Persist the draft. Return true when saved; false to keep the dialog
  /// open with an error so the patient can retry.
  final Future<bool> Function()? onConfirm;

  const ClosedEndedConfirmationDialog({
    super.key,
    required this.questionText,
    required this.selectedLabel,
    required this.selectedIndex,
    required this.optionColor,
    required this.isQuantitative,
    this.onConfirm,
  });

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
    return showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.3),
      builder: (ctx) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
        child: Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          child: ClosedEndedConfirmationDialog(
            questionText: questionText,
            selectedLabel: selectedLabel,
            selectedIndex: selectedIndex,
            optionColor: optionColor,
            isQuantitative: isQuantitative,
            onConfirm: onConfirm,
          ),
        ),
      ),
    );
  }

  @override
  State<ClosedEndedConfirmationDialog> createState() =>
      _ClosedEndedConfirmationDialogState();
}

class _ClosedEndedConfirmationDialogState
    extends State<ClosedEndedConfirmationDialog> {
  bool _submitting = false;
  String? _errorText;

  Future<void> _confirm() async {
    if (_submitting) return;
    final persist = widget.onConfirm;
    if (persist == null) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _submitting = true;
      _errorText = null;
    });
    bool saved = false;
    try {
      saved = await persist();
    } catch (_) {
      saved = false;
    }
    if (!mounted) return;
    if (saved) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _submitting = false;
        _errorText = 'บันทึกคำตอบไม่สำเร็จ กรุณาลองใหม่อีกครั้ง';
      });
    }
  }

  void _cancel() {
    if (_submitting) return;
    Navigator.of(context).pop(false);
  }

  @override
  Widget build(BuildContext context) {
    final optionColor = widget.optionColor;
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: const EdgeInsets.all(24),
          constraints: BoxConstraints(
            maxWidth: 320,
            maxHeight: MediaQuery.of(context).size.height * 0.8,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withValues(alpha: 0.10),
                Colors.white.withValues(alpha: 0.07),
                Colors.white.withValues(alpha: 0.04),
              ],
              stops: const [0.0, 0.5, 1.0],
            ),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.18),
              width: 0.8,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 30,
                spreadRadius: 2,
                offset: const Offset(0, 8),
              ),
              BoxShadow(
                color: optionColor.withValues(alpha: 0.10),
                blurRadius: 40,
                spreadRadius: 4,
              ),
            ],
          ),
          child: Stack(
            children: [
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: 60,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(24),
                      topRight: Radius.circular(24),
                    ),
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.white.withValues(alpha: 0.10),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
              SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.check_circle_outline_rounded,
                      size: 36,
                      color: optionColor.withValues(alpha: 0.9),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'ยืนยันคำตอบ',
                      style: TextStyle(
                        fontFamily: 'SukhumvitSet',
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: optionColor.withValues(alpha: 0.20),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: optionColor.withValues(alpha: 0.40),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (widget.isQuantitative) ...[
                            Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: optionColor.withValues(alpha: 0.3),
                              ),
                              child: Center(
                                child: Text(
                                  widget.selectedLabel,
                                  style: const TextStyle(
                                    fontFamily: 'SukhumvitSet',
                                    fontSize: 14,
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
                              widget.isQuantitative
                                  ? 'ระดับ ${widget.selectedLabel}'
                                  : widget.selectedLabel,
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
                      widget.questionText,
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
                    if (_errorText != null) ...[
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.error_outline_rounded,
                            size: 16,
                            color: Colors.red.shade300,
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              _errorText!,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontFamily: 'SukhumvitSet',
                                fontSize: 12,
                                color: Colors.red.shade300,
                                height: 1.3,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: GlassActionButton(
                            label: 'เปลี่ยน',
                            onTap: _submitting ? null : _cancel,
                            isFilled: false,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: GlassActionButton(
                            label: 'ยืนยัน',
                            onTap: _submitting ? null : _confirm,
                            isFilled: true,
                            fillColor: optionColor,
                            child: _submitting
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : null,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
