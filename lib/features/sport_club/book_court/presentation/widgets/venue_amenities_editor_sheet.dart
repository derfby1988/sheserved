import 'package:flutter/material.dart';
import 'package:sheserved/core/constants/app_colors.dart';

import 'book_court_filter_sheet.dart';

/// Owner editor for a venue's amenity set. Keys are restricted to the supply
/// schema whitelist (same catalog as `BookCourtFilterSheet.amenityOptions`).
/// Returns the `p_amenities` list for `set_sports_venue_amenities`.
class VenueAmenitiesEditorSheet {
  static Future<List<String>?> show(
    BuildContext context, {
    required Set<String> selected,
  }) {
    return showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) =>
          _VenueAmenitiesEditorSheetBody(selected: selected),
    );
  }
}

class _VenueAmenitiesEditorSheetBody extends StatefulWidget {
  final Set<String> selected;

  const _VenueAmenitiesEditorSheetBody({required this.selected});

  @override
  State<_VenueAmenitiesEditorSheetBody> createState() =>
      _VenueAmenitiesEditorSheetBodyState();
}

class _VenueAmenitiesEditorSheetBodyState
    extends State<_VenueAmenitiesEditorSheetBody> {
  late final Set<String> _selected = Set.of(widget.selected);

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'สิ่งอำนวยความสะดวก',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              'ถ้าสนามไม่มีสิ่งอำนวยความสะดวก กดบันทึกโดยไม่เลือก — ระบบจะบันทึกว่าคุณยืนยันแล้ว',
              style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final entry in BookCourtFilterSheet.amenityOptions.entries)
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
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primaryDark,
                ),
                onPressed: () => Navigator.pop(context, _selected.toList()),
                child: const Text('บันทึก'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
