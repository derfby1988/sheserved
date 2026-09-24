import 'package:flutter/material.dart';

import '../../data/book_court_models.dart';

/// Standard + custom tag picker for the venue review sheet.
///
/// Standard tags come from the server catalog; custom tags are free-text
/// labels attached to this review only (never enter the global catalog).
/// Combined selection is capped at 5.
class CourtReviewTagPicker extends StatefulWidget {
  final List<VenueReviewTag> catalog;
  final Set<String> selectedTagIds;
  final List<String> customTags;
  final void Function(Set<String> tagIds, List<String> customTags) onChanged;

  static const int maxTags = 5;

  const CourtReviewTagPicker({
    super.key,
    required this.catalog,
    required this.selectedTagIds,
    required this.customTags,
    required this.onChanged,
  });

  @override
  State<CourtReviewTagPicker> createState() => _CourtReviewTagPickerState();
}

class _CourtReviewTagPickerState extends State<CourtReviewTagPicker> {
  final _customController = TextEditingController();

  int get _total =>
      widget.selectedTagIds.length + widget.customTags.length;

  bool get _atLimit => _total >= CourtReviewTagPicker.maxTags;

  @override
  void dispose() {
    _customController.dispose();
    super.dispose();
  }

  void _toggle(String tagId, bool selected) {
    final next = {...widget.selectedTagIds};
    if (selected) {
      if (_atLimit) return;
      next.add(tagId);
    } else {
      next.remove(tagId);
    }
    widget.onChanged(next, widget.customTags);
  }

  void _addCustom() {
    final label = _customController.text.trim();
    if (label.isEmpty || label.length > 60 || _atLimit) return;
    if (widget.customTags.contains(label)) return;
    _customController.clear();
    widget.onChanged(widget.selectedTagIds, [...widget.customTags, label]);
  }

  void _removeCustom(String label) {
    widget.onChanged(
      widget.selectedTagIds,
      widget.customTags.where((t) => t != label).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'แท็กรีวิว ($_total/${CourtReviewTagPicker.maxTags})',
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final tag in widget.catalog)
              FilterChip(
                label: Text(tag.labelTh),
                selected: widget.selectedTagIds.contains(tag.id),
                onSelected: (sel) => _toggle(tag.id, sel),
              ),
            for (final label in widget.customTags)
              InputChip(
                label: Text(label),
                onDeleted: () => _removeCustom(label),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _customController,
                maxLength: 60,
                decoration: const InputDecoration(
                  hintText: 'เพิ่มแท็กของคุณเอง',
                  isDense: true,
                  counterText: '',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _addCustom(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: _atLimit ? null : _addCustom,
              icon: const Icon(Icons.add_circle_outline_rounded),
              tooltip: 'เพิ่มแท็ก',
            ),
          ],
        ),
      ],
    );
  }
}
