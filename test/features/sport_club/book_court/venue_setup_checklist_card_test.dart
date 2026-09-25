import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sheserved/features/sport_club/book_court/data/book_court_models.dart';
import 'package:sheserved/features/sport_club/book_court/domain/venue_setup_progress.dart';
import 'package:sheserved/features/sport_club/book_court/presentation/widgets/venue_setup_checklist_card.dart';

Widget _wrap(Widget child) => MaterialApp(
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

List<VenueSetupStep> _steps({
  bool ownerApproved = true,
  bool venueCreated = true,
  bool hasSports = false,
  bool hoursComplete = false,
  bool amenitiesDone = false,
  bool termsDone = false,
  bool hasActiveCourts = false,
  VenueStatus? venueStatus = VenueStatus.draft,
}) => computeVenueSetupSteps(
  ownerApproved: ownerApproved,
  venueCreated: venueCreated,
  hasSports: hasSports,
  hoursComplete: hoursComplete,
  amenitiesDone: amenitiesDone,
  termsDone: termsDone,
  hasActiveCourts: hasActiveCourts,
  venueStatus: venueStatus,
);

void main() {
  testWidgets('renders 8 steps with progress count', (tester) async {
    await tester.pumpWidget(
      _wrap(
        VenueSetupChecklistCard(
          steps: _steps(),
          venueStatus: VenueStatus.draft,
          onRun: (_) {},
        ),
      ),
    );
    expect(find.text('ขั้นตอนการเปิดสนาม'), findsOneWidget);
    expect(find.text('2/8'), findsOneWidget);
    expect(find.byType(InkWell), findsNWidgets(8));
  });

  testWidgets('tapping an actionable step fires onRun', (tester) async {
    VenueSetupStepId? ran;
    await tester.pumpWidget(
      _wrap(
        VenueSetupChecklistCard(
          steps: _steps(),
          venueStatus: VenueStatus.draft,
          onRun: (s) => ran = s,
        ),
      ),
    );
    await tester.tap(find.text('ตั้งค่ากีฬาของสนาม'));
    expect(ran, VenueSetupStepId.sports);
  });

  testWidgets('read-only steps 1-2 and step 8 never fire onRun', (
    tester,
  ) async {
    VenueSetupStepId? ran;
    await tester.pumpWidget(
      _wrap(
        VenueSetupChecklistCard(
          steps: _steps(ownerApproved: false, venueCreated: false),
          venueStatus: VenueStatus.pending,
          onRun: (s) => ran = s,
        ),
      ),
    );
    await tester.tap(find.text('เจ้าของสนามได้รับอนุมัติ'));
    await tester.tap(find.text('สร้างสนาม'));
    await tester.tap(find.text('ทีมงานอนุมัติสนาม → เปิดรับการจอง'));
    expect(ran, isNull);
  });

  testWidgets('done editable step fires onRun for re-editing', (tester) async {
    VenueSetupStepId? ran;
    await tester.pumpWidget(
      _wrap(
        VenueSetupChecklistCard(
          steps: _steps(termsDone: true),
          venueStatus: VenueStatus.draft,
          onRun: (s) => ran = s,
        ),
      ),
    );
    await tester.tap(find.text('ใช้เงื่อนไขมาตรฐานหรือเผยแพร่เงื่อนไขของสนาม'));
    expect(ran, VenueSetupStepId.terms);
  });

  group('step 8 trailing icon per review status', () {
    Future<void> pump(WidgetTester tester, VenueStatus status) {
      return tester.pumpWidget(
        _wrap(
          VenueSetupChecklistCard(
            steps: _steps(venueStatus: status),
            venueStatus: status,
            onRun: (_) {},
          ),
        ),
      );
    }

    testWidgets('draft shows send icon', (tester) async {
      await pump(tester, VenueStatus.draft);
      expect(find.byIcon(Icons.send_rounded), findsOneWidget);
    });
    testWidgets('pending shows hourglass', (tester) async {
      await pump(tester, VenueStatus.pending);
      expect(find.byIcon(Icons.hourglass_top_rounded), findsOneWidget);
    });
    testWidgets('rejected shows error icon', (tester) async {
      await pump(tester, VenueStatus.rejected);
      expect(find.byIcon(Icons.error_rounded), findsOneWidget);
    });
    testWidgets('suspended shows block icon', (tester) async {
      await pump(tester, VenueStatus.suspended);
      expect(find.byIcon(Icons.block_rounded), findsOneWidget);
    });
    testWidgets('approved shows check icons (steps 1-2 + step 8)', (
      tester,
    ) async {
      await pump(tester, VenueStatus.approved);
      // ownerApproved + venueCreated + venueApproved checks
      expect(find.byIcon(Icons.check_circle_rounded), findsNWidgets(3));
    });
  });

  testWidgets('saving disables step taps', (tester) async {
    VenueSetupStepId? ran;
    await tester.pumpWidget(
      _wrap(
        VenueSetupChecklistCard(
          steps: _steps(),
          venueStatus: VenueStatus.draft,
          saving: true,
          onRun: (s) => ran = s,
        ),
      ),
    );
    await tester.tap(find.text('ตั้งค่ากีฬาของสนาม'));
    await tester.pump();
    expect(ran, isNull);
  });
}
