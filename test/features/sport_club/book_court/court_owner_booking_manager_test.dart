import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sheserved/features/sport_club/book_court/data/book_court_models.dart';
import 'package:sheserved/features/sport_club/book_court/presentation/widgets/court_owner_booking_manager.dart';

void main() {
  testWidgets('renders the booking range in the venue timezone', (tester) async {
    final booking = VenueBooking.fromJson({
      'id': 'b1',
      'venueId': 'v1',
      'courtId': 'c1',
      'courtName': 'คอร์ท 3',
      'timezone': 'Asia/Bangkok',
      'status': 'pending',
      // 21:00–22:00 in Asia/Bangkok, stored as UTC by the booking RPC.
      'startsAt': DateTime.utc(2030, 1, 1, 14).toIso8601String(),
      'endsAt': DateTime.utc(2030, 1, 1, 15).toIso8601String(),
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: CourtOwnerBookingManager(booking: booking)),
      ),
    );

    expect(find.textContaining('21:00–22:00'), findsOneWidget);
    expect(find.textContaining('14:00'), findsNothing);
  });
}
