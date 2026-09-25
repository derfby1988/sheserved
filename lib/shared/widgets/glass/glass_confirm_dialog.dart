import 'package:flutter/material.dart';

import 'glass_dialog.dart';
import 'glass_primitives.dart';

class GlassConfirmDialog extends StatefulWidget {
  final IconData? icon;
  final String title;
  final Widget content;
  final Color accentColor;
  final String cancelLabel;
  final String confirmLabel;
  final String errorMessage;
  final Future<bool> Function()? onConfirm;
  final double maxWidth;
  final double maxHeightFactor;

  const GlassConfirmDialog({
    super.key,
    this.icon,
    required this.title,
    required this.content,
    required this.accentColor,
    required this.cancelLabel,
    required this.confirmLabel,
    this.errorMessage = 'บันทึกไม่สำเร็จ กรุณาลองใหม่อีกครั้ง',
    this.onConfirm,
    this.maxWidth = 320,
    this.maxHeightFactor = 0.8,
  });

  static Future<bool?> show(
    BuildContext context, {
    IconData? icon,
    required String title,
    required Widget content,
    required Color accentColor,
    required String cancelLabel,
    required String confirmLabel,
    String errorMessage = 'บันทึกไม่สำเร็จ กรุณาลองใหม่อีกครั้ง',
    Future<bool> Function()? onConfirm,
    double maxWidth = 320,
    double maxHeightFactor = 0.8,
  }) {
    return GlassDialog.show<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.3),
      backdropBlur: 6,
      panelBorderRadius: 24,
      panelBlurSigma: 18,
      panelFillOpacity: 0.10,
      panelAccentColor: accentColor,
      panelAccentStrength: 0.12,
      panelGlowOpacity: 0.14,
      panelRimWidth: 2.4,
      panelShadowOpacity: 0.30,
      contentPadding: EdgeInsets.zero,
      builder: (_) => GlassConfirmDialog(
        icon: icon,
        title: title,
        content: content,
        accentColor: accentColor,
        cancelLabel: cancelLabel,
        confirmLabel: confirmLabel,
        errorMessage: errorMessage,
        onConfirm: onConfirm,
        maxWidth: maxWidth,
        maxHeightFactor: maxHeightFactor,
      ),
    );
  }

  @override
  State<GlassConfirmDialog> createState() => _GlassConfirmDialogState();
}

class _GlassConfirmDialogState extends State<GlassConfirmDialog> {
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
        _errorText = widget.errorMessage;
      });
    }
  }

  void _cancel() {
    if (_submitting) return;
    Navigator.of(context).pop(false);
  }

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: widget.maxWidth,
        maxHeight: MediaQuery.of(context).size.height * widget.maxHeightFactor,
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.icon != null) ...[
                Icon(
                  widget.icon,
                  size: 36,
                  color: widget.accentColor.withValues(alpha: 0.9),
                ),
                const SizedBox(height: 12),
              ],
              Text(
                widget.title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: 'SukhumvitSet',
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 16),
              widget.content,
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
                      label: widget.cancelLabel,
                      onTap: _submitting ? null : _cancel,
                      isFilled: false,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GlassActionButton(
                      label: widget.confirmLabel,
                      onTap: _submitting ? null : _confirm,
                      isFilled: true,
                      fillColor: widget.accentColor,
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
      ),
    );
  }
}
