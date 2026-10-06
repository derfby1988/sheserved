import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sheserved/features/sport_club/book_court/data/book_court_models.dart';
import 'package:sheserved/features/sport_club/book_court/data/book_court_repository.dart';
import 'package:sheserved/features/sport_club/book_court/presentation/widgets/booking_group_sheet.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _FakeRepo extends BookCourtRepository {
  _FakeRepo()
    : super(
        SupabaseClient(
          'https://example.com',
          'test-anon-key',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        ),
      );

  List<VenueBookingGroup> groups = const [];

  @override
  Future<({DateTime? serverNow, List<VenueBookingGroup> groups})>
  listMyBookingGroups(String userId) async =>
      (serverNow: DateTime.now(), groups: groups);
}

const _slipReq = EvidenceRequirement(
  key: 'payment',
  label: 'สลิปชำระเงิน',
  kind: 'payment_slip',
  stage: 'payment',
  reviewMode: 'owner_review',
  required: true,
);

VenueBookingGroup _group(
  BookingGroupStatus status, {
  List<EvidenceRequirement> requirements = const [_slipReq],
}) => VenueBookingGroup(
  id: 'group-1',
  venueId: 'venue-1',
  venueName: 'สนามทดสอบ',
  timezone: 'Asia/Bangkok',
  status: status,
  stage: 'payment',
  approvalMode: BookingApprovalMode.instant,
  totalAmount: 100,
  requirements: requirements,
  bookings: [
    BookingGroupChild(
      id: 'b-1',
      courtId: 'court-1',
      courtName: 'คอร์ท 1',
      startsAt: DateTime(2026, 10, 20, 10),
      endsAt: DateTime(2026, 10, 20, 11),
      status: VenueBookingStatus.forfeited,
    ),
  ],
);

void main() {
  Future<void> openSheet(
    WidgetTester tester,
    _FakeRepo repo,
    VenueBookingGroup group, {
    Future<void> Function()? onRebook,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => BookingGroupSheet.show(
              context,
              repo: repo,
              userId: 'u-1',
              group: group,
              serverNow: DateTime.now(),
              onRebook: onRebook,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    // pump() — not pumpAndSettle: the sheet's countdown runs a periodic
    // timer that never lets the tree fully settle.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets(
    'forfeited group offers rebook and claim; rebook closes the sheet',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      final repo = _FakeRepo();
      final group = _group(BookingGroupStatus.forfeited);
      repo.groups = [group];
      var rebooked = false;

      await openSheet(
        tester,
        repo,
        group,
        onRebook: () async => rebooked = true,
      );

      expect(find.text('เลือกเวลาใหม่'), findsOneWidget);
      expect(find.text('แจ้งว่าโอนเงินแล้ว'), findsOneWidget);

      await tester.tap(find.text('เลือกเวลาใหม่'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(rebooked, isTrue);
      expect(find.text('เลือกเวลาใหม่'), findsNothing);
    },
  );

  testWidgets(
    'open group hides claim and rebook actions',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      final repo = _FakeRepo();
      final group = _group(BookingGroupStatus.awaitingEvidence);
      repo.groups = [group];

      await openSheet(tester, repo, group, onRebook: () async {});

      // The claim RPC rejects open groups — the button must not offer it.
      expect(find.text('แจ้งว่าโอนเงินแล้ว'), findsNothing);
      expect(find.text('เลือกเวลาใหม่'), findsNothing);
      expect(find.text('ยกเลิกการจอง'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );

  testWidgets(
    'forfeited group without a slip requirement hides the claim button',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      final repo = _FakeRepo();
      final group = _group(
        BookingGroupStatus.rejected,
        requirements: const [],
      );
      repo.groups = [group];

      await openSheet(tester, repo, group, onRebook: () async {});

      expect(find.text('แจ้งว่าโอนเงินแล้ว'), findsNothing);
      expect(find.text('เลือกเวลาใหม่'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );
}
