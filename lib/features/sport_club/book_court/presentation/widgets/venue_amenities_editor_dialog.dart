import 'package:flutter/material.dart';
import 'package:sheserved/core/constants/app_colors.dart';
import 'package:sheserved/shared/widgets/glass/glass_dialog.dart';
import 'package:sheserved/shared/widgets/glass/glass_primitives.dart';

import 'book_court_filter_sheet.dart';

/// Owner editor for a venue's amenity set. Keys are restricted to the supply
/// schema whitelist (same catalog as `BookCourtFilterSheet.amenityOptions`).
/// Returns the `p_amenities` list for `set_sports_venue_amenities`.
class VenueAmenitiesEditorDialog {
  static Future<List<String>?> show(
    BuildContext context, {
    required Set<String> selected,
  }) {
    return GlassDialog.show<List<String>>(
      context: context,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      panelAccentColor: AppColors.primary,
      contentPadding: EdgeInsets.zero,
      builder: (dialogContext) =>
          _VenueAmenitiesEditorDialogBody(selected: selected),
    );
  }
}

class _VenueAmenitiesEditorDialogBody extends StatefulWidget {
  final Set<String> selected;

  const _VenueAmenitiesEditorDialogBody({required this.selected});

  @override
  State<_VenueAmenitiesEditorDialogBody> createState() =>
      _VenueAmenitiesEditorDialogBodyState();
}

class _VenueAmenitiesEditorDialogBodyState
    extends State<_VenueAmenitiesEditorDialogBody> {
  late final Set<String> _selected = Set.of(widget.selected);
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
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
                        'สิ่งอำนวยความสะดวก',
                        style: TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'ถ้าสถานที่ไม่มีสิ่งอำนวยความสะดวก กดบันทึกโดยไม่เลือก — ระบบจะบันทึกว่าคุณยืนยันแล้ว',
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
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final entry
                            in BookCourtFilterSheet.amenityOptions.entries)
                          FilterChip(
                            label: Text(entry.value),
                            selected: _selected.contains(entry.key),
                            onSelected: (value) => setState(() {
                              if (value) {
                                _selected.add(entry.key);
                              } else {
                                _selected.remove(entry.key);
                              }
                            }),
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
                    label: 'บันทึก',
                    isFilled: true,
                    fillColor: AppColors.primaryDark,
                    onTap: () => Navigator.of(context).pop(_selected.toList()),
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
