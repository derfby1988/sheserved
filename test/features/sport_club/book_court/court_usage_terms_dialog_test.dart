import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sheserved/features/sport_club/book_court/data/book_court_models.dart';
import 'package:sheserved/features/sport_club/book_court/presentation/widgets/court_usage_terms_dialog.dart';

void main() {
  testWidgets('missing platform terms cannot be accepted for booking', (
    tester,
  ) async {
    VenueTerms? accepted;
    var dialogClosed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () async {
                accepted = await CourtUsageTermsDialog.show(
                  context,
                  terms: null,
                  venueName: 'สนามทดสอบ',
                );
                dialogClosed = true;
              },
              child: const Text('open terms'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open terms'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'สนามนี้ยังไม่ได้ตั้งค่าเงื่อนไขมาตรฐาน จึงยังจองไม่ได้ กรุณากลับมาลองใหม่ภายหลัง',
      ),
      findsOneWidget,
    );
    expect(find.text('ยอมรับและจอง'), findsNothing);

    await tester.tap(find.text('ปิด'));
    await tester.pumpAndSettle();

    expect(dialogClosed, isTrue);
    expect(accepted, isNull);
  });

  testWidgets('configured platform terms return the accepted version', (
    tester,
  ) async {
    const terms = VenueTerms(
      id: 'platform-terms',
      venueId: 'venue-id',
      version: 4,
      termsText: 'เงื่อนไขเวอร์ชันล่าสุด',
      cancellationCutoffMinutes: 90,
    );
    VenueTerms? accepted;
    var dialogClosed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () async {
                accepted = await CourtUsageTermsDialog.show(
                  context,
                  terms: terms,
                  venueName: 'สนามทดสอบ',
                );
                dialogClosed = true;
              },
              child: const Text('open terms'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open terms'));
    await tester.pumpAndSettle();

    expect(find.text('เงื่อนไขเวอร์ชันล่าสุด'), findsOneWidget);
    expect(find.text('ยกเลิกได้ฟรีถึง 90 นาทีก่อนเวลาเริ่ม'), findsOneWidget);
    await tester.tap(find.text('ยอมรับและจอง'));
    await tester.pumpAndSettle();

    expect(dialogClosed, isTrue);
    expect(accepted?.version, 4);
  });
}
