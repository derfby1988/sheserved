import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sheserved/features/home/presentation/widgets/home_header_section.dart';

void main() {
  testWidgets('renders fitness booking alert while header is loading', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeHeaderSection(
            isLoading: true,
            fitnessBookingAlerts: [
              {
                'booking_id': 'booking-1',
                'status': 'rejected',
                'message': 'คำขอเข้าร่วมก๊วนของคุณถูกปฏิเสธ',
                'updated_at': '2026-08-25T10:00:00Z',
              },
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.textContaining('คำขอเข้าร่วมก๊วนของคุณถูกปฏิเสธ'),
      findsOneWidget,
    );
  });

  testWidgets('passes pending owner request alert to callback', (tester) async {
    Map<String, dynamic>? tappedAlert;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeHeaderSection(
            fitnessBookingAlerts: [
              {
                'bookingId': 'booking-2',
                'groupId': 'group-2',
                'status': 'pending',
                'message': 'มีคำขอเข้าร่วมก๊วนใหม่',
                'updatedAt': DateTime(2026, 8, 25, 10),
              },
            ],
            onFitnessBookingAlertTapped: (alert) => tappedAlert = alert,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.textContaining('มีคำขอเข้าร่วมก๊วนใหม่'));

    expect(tappedAlert?['bookingId'], 'booking-2');
    expect(tappedAlert?['groupId'], 'group-2');
    expect(tappedAlert?['status'], 'pending');
  });
}
