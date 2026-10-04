import 'package:flutter/material.dart';
import 'package:sheserved/core/constants/app_colors.dart';
import 'package:sheserved/shared/widgets/glass/glass_dialog.dart';
import 'package:sheserved/shared/widgets/glass/glass_primitives.dart';

import 'venue_cancellation_cutoff_field.dart';

/// Owner editor for venue usage terms. Publishing always creates a new
/// active version (older versions stay for existing booking snapshots), so
/// this dialog only submits a draft — the caller runs `publish_sports_venue_terms`
/// and shows the returned version.
class VenueTermsEditorDialog {
  static Future<({String text, int cutoffMinutes})?> show(
    BuildContext context, {
    String? currentText,
    int? currentCutoffMinutes,
  }) {
    return GlassDialog.show<({String text, int cutoffMinutes})>(
      context: context,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      panelAccentColor: AppColors.primary,
      contentPadding: EdgeInsets.zero,
      builder: (dialogContext) => _VenueTermsEditorDialogBody(
        currentText: currentText,
        currentCutoffMinutes: currentCutoffMinutes,
      ),
    );
  }
}

class _VenueTermsEditorDialogBody extends StatefulWidget {
  final String? currentText;
  final int? currentCutoffMinutes;

  const _VenueTermsEditorDialogBody({
    this.currentText,
    this.currentCutoffMinutes,
  });

  @override
  State<_VenueTermsEditorDialogBody> createState() =>
      _VenueTermsEditorDialogBodyState();
}

class _VenueTermsEditorDialogBodyState
    extends State<_VenueTermsEditorDialogBody> {
  late final _terms = TextEditingController(text: widget.currentText ?? '');
  late final List<int> _cutoffOptions = venueCancellationCutoffOptions(
    widget.currentCutoffMinutes,
  );
  late int _cutoffMinutes = widget.currentCutoffMinutes ?? 60;
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _terms.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  bool get _valid => _terms.text.trim().isNotEmpty;

  void _submit() {
    if (!_valid) return;
    Navigator.pop(context, (
      text: _terms.text.trim(),
      cutoffMinutes: _cutoffMinutes,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: 400,
        maxHeight: MediaQuery.of(context).size.height * 0.8,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'เงื่อนไขการใช้งาน',
                        style: TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'การบันทึกจะเผยแพร่เวอร์ชันใหม่ — ผู้จองต้องยอมรับเวอร์ชันล่าสุดก่อนจอง',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withValues(alpha: 0.65),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                GlassIconButton(
                  icon: Icons.close_rounded,
                  semanticsLabel: 'ปิด',
                  onTap: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Flexible(
              child: LitGlassSurface.frosted(
                borderRadius: 14,
                child: Scrollbar(
                  controller: _scrollController,
                  thumbVisibility: true,
                  interactive: true,
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextField(
                          controller: _terms,
                          minLines: 5,
                          maxLines: 10,
                          decoration: const InputDecoration(
                            labelText: 'เงื่อนไขการใช้งาน',
                            alignLabelWithHint: true,
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                        const SizedBox(height: 12),
                        VenueCancellationCutoffField(
                          key: const ValueKey('venue-terms-cutoff'),
                          value: _cutoffMinutes,
                          options: _cutoffOptions,
                          onChanged: (minutes) =>
                              setState(() => _cutoffMinutes = minutes),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: GlassActionButton(
                    label: 'ยกเลิก',
                    onTap: () => Navigator.of(context).pop(),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: GlassActionButton(
                    label: 'เผยแพร่เวอร์ชันใหม่',
                    isFilled: true,
                    fillColor: AppColors.primaryDark,
                    onTap: _valid ? _submit : null,
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
