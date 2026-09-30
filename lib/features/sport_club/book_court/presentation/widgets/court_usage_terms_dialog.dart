import 'package:flutter/material.dart';
import 'package:sheserved/core/constants/app_colors.dart';
import 'package:sheserved/shared/widgets/glass/glass_dialog.dart';
import 'package:sheserved/shared/widgets/glass/glass_primitives.dart';

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
    String acceptLabel = 'ยอมรับและจอง',
  }) {
    return GlassDialog.show<VenueTerms>(
      context: context,
      barrierDismissible: false,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      panelAccentColor: AppColors.primary,
      contentPadding: EdgeInsets.zero,
      builder: (dialogContext) => _CourtUsageTermsDialogBody(
        terms: terms,
        venueName: venueName,
        acceptLabel: acceptLabel,
      ),
    );
  }
}

class _CourtUsageTermsDialogBody extends StatelessWidget {
  final VenueTerms? terms;
  final String venueName;
  final String acceptLabel;

  const _CourtUsageTermsDialogBody({
    required this.terms,
    required this.venueName,
    required this.acceptLabel,
  });

  @override
  Widget build(BuildContext context) {
    final effective = terms;
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: 400,
        maxHeight: MediaQuery.of(context).size.height * 0.82,
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'เงื่อนไขการใช้สนาม',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: LitGlassSurface.frosted(
                borderRadius: 12,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        venueName,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        effective?.termsText ??
                            'สนามนี้ยังไม่ได้ตั้งค่าเงื่อนไขมาตรฐาน จึงยังจองไม่ได้ กรุณากลับมาลองใหม่ภายหลัง',
                        style: const TextStyle(
                          fontSize: 14,
                          height: 1.4,
                          color: Color(0xFF334155),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (effective != null) ...[
              const SizedBox(height: 12),
              LitGlassSurface.frosted(
                borderRadius: 10,
                child: Padding(
                  padding: const EdgeInsets.all(10),
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
              ),
            ],
            const SizedBox(height: 16),
            if (effective == null)
              SizedBox(
                width: double.infinity,
                child: GlassActionButton(
                  label: 'ปิด',
                  isFilled: true,
                  fillColor: AppColors.primaryDark,
                  onTap: () => Navigator.of(context).pop(),
                ),
              )
            else
              Row(
                children: [
                  Expanded(
                    child: GlassActionButton(
                      label: 'ไม่ยอมรับ',
                      onTap: () => Navigator.of(context).pop(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GlassActionButton(
                      label: acceptLabel,
                      isFilled: true,
                      fillColor: AppColors.primaryDark,
                      onTap: () => Navigator.of(context).pop(effective),
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
