import 'package:flutter/material.dart';
import 'package:sheserved/core/constants/app_colors.dart';
import 'package:sheserved/shared/widgets/neumorphic/neumorphic.dart';

import '../../data/book_court_models.dart';
import 'court_review_tag_picker.dart';

/// Review composer for a completed venue booking.
///
/// Returns a [CourtReviewDraft] on submit, or null when dismissed.
/// Eligibility
/// (completed booking, one review per booking, no self-review) is enforced
/// server-side by `submit_sports_venue_review_v2`; the caller also disables
/// the entry point when the booking is not reviewable. Pass the previous
/// draft as [CourtReviewSheet.show]'s `initial` to retry a failed submit
/// without losing the reviewer's input.
typedef CourtReviewDraft = ({
  int rating10,
  Map<String, int> categoryScores,
  String? comment,
  Set<String> tagIds,
  List<String> customTags,
});

class CourtReviewSheet {
  static Future<CourtReviewDraft?> show(
    BuildContext context, {
    required String venueName,
    required List<VenueReviewTag> tagCatalog,
    required List<VenueReviewCategory> categories,
    CourtReviewDraft? initial,
  }) {
    return showModalBottomSheet<CourtReviewDraft>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: NeumorphicTheme.baseColor,
      builder: (sheetContext) => _CourtReviewSheetBody(
        venueName: venueName,
        tagCatalog: tagCatalog,
        categories: categories,
        initial: initial,
      ),
    );
  }
}

class _CourtReviewSheetBody extends StatefulWidget {
  final String venueName;
  final List<VenueReviewTag> tagCatalog;
  final List<VenueReviewCategory> categories;

  /// Unsubmitted draft restored for a retry after a failed submit.
  final CourtReviewDraft? initial;

  const _CourtReviewSheetBody({
    required this.venueName,
    required this.tagCatalog,
    required this.categories,
    this.initial,
  });

  @override
  State<_CourtReviewSheetBody> createState() => _CourtReviewSheetBodyState();
}

class _CourtReviewSheetBodyState extends State<_CourtReviewSheetBody> {
  late int _rating = widget.initial?.rating10 ?? 0;
  late final Map<String, int> _categoryScores = {
    ...?widget.initial?.categoryScores,
  };
  late final _comment = TextEditingController(
    text: widget.initial?.comment ?? '',
  );
  late Set<String> _tagIds = {...?widget.initial?.tagIds};
  late List<String> _customTags = [...?widget.initial?.customTags];

  bool get _categoriesComplete =>
      widget.categories.every((c) => _categoryScores.containsKey(c.id));

  bool get _canSubmit => _rating > 0 && _categoriesComplete;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Widget _scorePicker({
    required int? selected,
    required ValueChanged<int> onSelected,
    required String valueKeyPrefix,
  }) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 1; i <= 10; i++)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                key: ValueKey('$valueKeyPrefix-$i'),
                label: Text('$i'),
                selected: selected == i,
                onSelected: (sel) {
                  if (sel) onSelected(i);
                },
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'รีวิว ${widget.venueName}',
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'ให้คะแนนจากการจองที่เสร็จสมบูรณ์ของคุณ (เต็ม 10)',
                style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 12),
              const Text(
                'คะแนนรวม',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              ),
              const SizedBox(height: 6),
              _scorePicker(
                selected: _rating == 0 ? null : _rating,
                onSelected: (i) => setState(() => _rating = i),
                valueKeyPrefix: 'overall-score',
              ),
              const SizedBox(height: 16),
              const Text(
                'คะแนนแยกหมวด',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              ),
              const SizedBox(height: 8),
              for (final category in widget.categories) ...[
                Text(
                  category.labelTh,
                  style: TextStyle(
                    fontSize: 13,
                    color: _categoryScores.containsKey(category.id)
                        ? Colors.black87
                        : Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 4),
                _scorePicker(
                  selected: _categoryScores[category.id],
                  onSelected: (i) =>
                      setState(() => _categoryScores[category.id] = i),
                  valueKeyPrefix: 'category-${category.key}',
                ),
                const SizedBox(height: 10),
              ],
              const SizedBox(height: 4),
              TextField(
                controller: _comment,
                maxLength: 500,
                maxLines: 3,
                decoration: const InputDecoration(
                  hintText: 'เล่าประสบการณ์ของคุณ (ไม่บังคับ)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              CourtReviewTagPicker(
                catalog: widget.tagCatalog,
                selectedTagIds: _tagIds,
                customTags: _customTags,
                onChanged: (tagIds, customTags) => setState(() {
                  _tagIds = tagIds;
                  _customTags = customTags;
                }),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primaryDark,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: _canSubmit
                      ? () => Navigator.pop(context, (
                          rating10: _rating,
                          categoryScores: Map<String, int>.unmodifiable(
                            _categoryScores,
                          ),
                          comment: _comment.text.trim().isEmpty
                              ? null
                              : _comment.text.trim(),
                          tagIds: _tagIds,
                          customTags: _customTags,
                        ))
                      : null,
                  child: const Text('ส่งรีวิว'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
