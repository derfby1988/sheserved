import 'package:flutter/material.dart';

import 'glass_dialog.dart';
import 'glass_primitives.dart';

/// Single-field glass prompt (title + text input + cancel/confirm) — the
/// shared replacement for raw `AlertDialog` "enter a reason/name" dialogs.
/// Pops with the trimmed text, or null when cancelled/dismissed.
class GlassTextPromptDialog extends StatefulWidget {
  final String title;
  final String hint;
  final String? label;
  final String confirmLabel;
  final String cancelLabel;
  final Color accentColor;
  final int maxLength;
  final int maxLines;
  final int minLines;

  const GlassTextPromptDialog({
    super.key,
    required this.title,
    required this.hint,
    this.label,
    this.confirmLabel = 'ยืนยัน',
    this.cancelLabel = 'ยกเลิก',
    this.accentColor = const Color(0xFFC62828),
    this.maxLength = 300,
    this.maxLines = 3,
    this.minLines = 1,
  });

  static Future<String?> show(
    BuildContext context, {
    required String title,
    required String hint,
    String? label,
    String confirmLabel = 'ยืนยัน',
    String cancelLabel = 'ยกเลิก',
    Color accentColor = const Color(0xFFC62828),
    int maxLength = 300,
    int maxLines = 3,
    int minLines = 1,
  }) {
    return GlassDialog.show<String>(
      context: context,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      panelAccentColor: accentColor,
      contentPadding: EdgeInsets.zero,
      builder: (_) => GlassTextPromptDialog(
        title: title,
        hint: hint,
        label: label,
        confirmLabel: confirmLabel,
        cancelLabel: cancelLabel,
        accentColor: accentColor,
        maxLength: maxLength,
        maxLines: maxLines,
        minLines: minLines,
      ),
    );
  }

  @override
  State<GlassTextPromptDialog> createState() => _GlassTextPromptDialogState();
}

class _GlassTextPromptDialogState extends State<GlassTextPromptDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final valid = _controller.text.trim().isNotEmpty;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 360),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 12),
            LitGlassSurface.frosted(
              borderRadius: 12,
              child: TextField(
                controller: _controller,
                autofocus: true,
                maxLength: widget.maxLength,
                maxLines: widget.maxLines,
                minLines: widget.minLines,
                decoration: InputDecoration(
                  labelText: widget.label,
                  hintText: widget.hint,
                  hintStyle: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade500,
                  ),
                  border: InputBorder.none,
                  counterStyle: TextStyle(
                    fontSize: 10,
                    color: Colors.grey.shade500,
                  ),
                  contentPadding: const EdgeInsets.all(12),
                ),
                style: const TextStyle(
                  fontSize: 13.5,
                  color: Color(0xFF1E293B),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: GlassActionButton(
                    label: widget.cancelLabel,
                    onTap: () => Navigator.of(context).pop(),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GlassActionButton(
                    label: widget.confirmLabel,
                    isFilled: true,
                    fillColor: widget.accentColor,
                    onTap: valid
                        ? () => Navigator.of(
                            context,
                          ).pop(_controller.text.trim())
                        : null,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
