import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sheserved/features/sport_club/book_court/data/book_court_models.dart';
import 'package:sheserved/features/sport_club/book_court/domain/court_card_style.dart';
import 'package:sheserved/features/sport_club/book_court/presentation/widgets/court_card.dart';
import 'package:sheserved/features/sport_club/book_court/presentation/widgets/court_card_art.dart';

VenueBooking _booking({
  required String venueId,
  required VenueBookingStatus status,
  required DateTime startsAt,
}) => VenueBooking(
  id: 'booking-$venueId-${status.name}',
  courtId: 'court-1',
  venueId: venueId,
  sportId: 'sport-1',
  startsAt: startsAt,
  endsAt: startsAt.add(const Duration(hours: 1)),
  status: status,
  courtName: '3',
  unitLabel: 'คอร์ท',
);

void main() {
  testWidgets('shows the matching venue appointment in one pink line', (
    tester,
  ) async {
    final now = DateTime.now();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              child: CourtCard(
                venue: const VenueSummary(
                  id: 'venue-1',
                  name: 'สนามทดสอบ',
                  courtCount: 3,
                ),
                upcomingBookings: [
                  _booking(
                    venueId: 'venue-1',
                    status: VenueBookingStatus.confirmed,
                    startsAt: now.add(const Duration(hours: 2, minutes: 15)),
                  ),
                  _booking(
                    venueId: 'venue-2',
                    status: VenueBookingStatus.confirmed,
                    startsAt: now.add(const Duration(minutes: 20)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final summaryFinder = find.textContaining('คุณมีนัดหมาย');
    expect(summaryFinder, findsOneWidget);
    final summary = tester.widget<Text>(summaryFinder);
    expect(summary.data, contains('คอร์ท 3'));
    expect(summary.data, contains('กำลังจะเริ่มใน 2 ชม. 15 นาที'));
    expect(summary.maxLines, 1);
    expect(summary.softWrap, isFalse);
    expect(summary.style?.color, const Color(0xFFC2185B));
    expect(find.byType(FittedBox), findsOneWidget);
  });

  testWidgets('painter 3D style draws the cube stack itself', (tester) async {
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CourtCard(
            venue: const VenueSummary(
              id: 'venue-1',
              name: 'สนามทดสอบ',
              district: 'คลองเตย',
              province: 'กรุงเทพฯ',
              courtCount: 6,
              averageRating: 4.3,
              reviewCount: 18,
              startingPriceAmount: 250,
            ),
            styleOverride: CourtCardStyle.painter3d,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey(CourtCardCubeArt.painterKey)), findsOne);
    expect(
      find.byKey(const ValueKey(CourtCardCubeArt.lottieKey)),
      findsNothing,
    );
    // The score block repeats the rating shown in the detail row.
    expect(find.text('4.3'), findsNWidgets(2));
    expect(find.text('/5'), findsOneWidget);
    expect(find.text('คะแนนสนาม'), findsOneWidget);
  });

  testWidgets('shader style falls back to the painter art without a program', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CourtCard(
            venue: const VenueSummary(
              id: 'venue-1',
              name: 'สนามทดสอบ',
              courtCount: 6,
              averageRating: 4.3,
              reviewCount: 18,
            ),
            styleOverride: CourtCardStyle.shaderGlass,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const ValueKey(CourtCardCubeArt.shaderKey)), findsOne);
    expect(find.text('คะแนนสนาม'), findsOneWidget);
  });

  testWidgets('lottie style renders the animation widget', (tester) async {
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CourtCard(
            venue: const VenueSummary(
              id: 'venue-1',
              name: 'สนามทดสอบ',
              courtCount: 6,
            ),
            styleOverride: CourtCardStyle.lottieCubes,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey(CourtCardCubeArt.lottieKey)), findsOne);
    // No rating -> the score block falls back to the court count.
    expect(find.text('6'), findsOneWidget);
    expect(find.text('รายการ'), findsOneWidget);
  });

  testWidgets(
    'hides appointments for other venues and non-confirmed bookings',
    (tester) async {
      final now = DateTime.now();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CourtCard(
              venue: const VenueSummary(
                id: 'venue-1',
                name: 'สนามทดสอบ',
                courtCount: 3,
              ),
              upcomingBookings: [
                _booking(
                  venueId: 'venue-2',
                  status: VenueBookingStatus.confirmed,
                  startsAt: now.add(const Duration(minutes: 20)),
                ),
                _booking(
                  venueId: 'venue-1',
                  status: VenueBookingStatus.pending,
                  startsAt: now.add(const Duration(minutes: 30)),
                ),
                _booking(
                  venueId: 'venue-1',
                  status: VenueBookingStatus.confirmed,
                  startsAt: now.subtract(const Duration(minutes: 10)),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.textContaining('คุณมีนัดหมาย'), findsNothing);
    },
  );
}
