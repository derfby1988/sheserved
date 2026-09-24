import 'package:flutter/material.dart';
import 'package:sheserved/core/constants/app_colors.dart';

import '../../data/book_court_models.dart';
import 'court_review_tag_picker.dart';

/// Review composer for a completed venue booking.
///
/// Returns a [CourtReviewDraft] on submit, or null when dismissed.
/// Eligibility
/// (completed booking, one review per booking, no self-review) is enforced
/// server-side by `submit_sports_venue_review`; the caller also disables
/// the entry point when the booking is not reviewable.
typedef CourtReviewDraft =
    ({
      int rating,
      String? comment,
      Set<String> tagIds,
      List<String> customTags,
    });

class CourtReviewSheet {
  static Future<CourtReviewDraft?> show(
    BuildContext context, {
    required String venueName,
    required List<VenueReviewTag> tagCatalog,
  }) {
    return showModalBottomSheet<CourtReviewDraft>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => _CourtReviewSheetBody(
        venueName: venueName,
        tagCatalog: tagCatalog,
      ),
    );
  }
}

class _CourtReviewSheetBody extends StatefulWidget {
  final String venueName;
  final List<VenueReviewTag> tagCatalog;

  const _CourtReviewSheetBody({
    required this.venueName,
    required this.tagCatalog,
  });

  @override
  State<_CourtReviewSheetBody> createState() => _CourtReviewSheetBodyState();
}

class _CourtReviewSheetBodyState extends State<_CourtReviewSheetBody> {
  int _rating = 0;
  final _comment = TextEditingController();
  Set<String> _tagIds = {};
  List<String> _customTags = [];

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
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
              const SizedBox(height: 12),
              Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 1; i <= 5; i++)
                      IconButton(
                        tooltip: '$i ดาว',
                        icon: Icon(
                          i <= _rating
                              ? Icons.star_rounded
                              : Icons.star_outline_rounded,
                          size: 32,
                          color: AppColors.alertGold,
                        ),
                        onPressed: () => setState(() => _rating = i),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
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
                  onPressed: _rating == 0
                      ? null
                      : () => Navigator.pop(context, (
                          rating: _rating,
                          comment: _comment.text.trim().isEmpty
                              ? null
                              : _comment.text.trim(),
                          tagIds: _tagIds,
                          customTags: _customTags,
                        )),
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
