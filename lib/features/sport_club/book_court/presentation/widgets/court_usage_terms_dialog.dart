import 'package:flutter/material.dart';
import 'package:sheserved/core/constants/app_colors.dart';

import '../../data/book_court_models.dart';

/// Mandatory venue-terms consent dialog shown before submitting a booking.
///
/// Returns the accepted [VenueTerms] (with its version) when the user
/// accepts, or null when dismissed/declined. The caller must send
/// `terms.version` to `create_sports_venue_booking`; when the RPC answers
/// TERMS_VERSION_CHANGED the dialog must be reopened with the fresh terms.
class CourtUsageTermsDialog {
  static Future<VenueTerms?> show(
    BuildContext context, {
    required VenueTerms? terms,
    required String venueName,
  }) {
    return showDialog<VenueTerms>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => _CourtUsageTermsDialogBody(
        terms: terms,
        venueName: venueName,
      ),
    );
  }
}

class _CourtUsageTermsDialogBody extends StatelessWidget {
  final VenueTerms? terms;
  final String venueName;

  const _CourtUsageTermsDialogBody({required this.terms, required this.venueName});

  @override
  Widget build(BuildContext context) {
    final effective = terms ??
        const VenueTerms(
          id: '',
          venueId: '',
          version: VenueTerms.baseVersion,
          termsText: VenueTerms.baseTermsText,
          cancellationCutoffMinutes: VenueTerms.baseCutoffMinutes,
        );
    return AlertDialog(
      title: const Text('เงื่อนไขการใช้สนาม'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                venueName,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Text(
                effective.termsText,
                style: const TextStyle(fontSize: 14, height: 1.4),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.timer_outlined,
                      size: 18,
                      color: Colors.orange.shade800,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'ยกเลิกได้ฟรีถึง ${effective.cancellationCutoffMinutes} นาทีก่อนเวลาเริ่ม',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: Colors.orange.shade900,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('ไม่ยอมรับ'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primaryDark,
          ),
          onPressed: () => Navigator.pop(context, effective),
          child: const Text('ยอมรับและจอง'),
        ),
      ],
    );
  }
}
