import 'package:flutter_test/flutter_test.dart';
import 'package:sheserved/features/sport_club/application/sport_club_booking_service.dart';

void main() {
  group('SportClubBookingService', () {
    test('returns null without calling the data source when user is missing',
        () async {
      var calls = 0;
      final service = SportClubBookingService(
        (sessionId, userId, {positionId}) async {
          calls++;
          return 'b1';
        },
      );

      expect(await service.book(userId: null, sessionId: 's1'), isNull);
      expect(await service.book(userId: '', sessionId: 's1'), isNull);
      expect(calls, 0);
    });

    test('books successfully and returns the id', () async {
      final service = SportClubBookingService(
        (sessionId, userId, {positionId}) async => 'booking-9',
      );

      final id = await service.book(userId: 'u1', sessionId: 's1');
      expect(id, 'booking-9');
    });

    test('forwards sessionId, userId and positionId to the data source',
        () async {
      String? gotSession, gotUser, gotPosition;
      final service = SportClubBookingService(
        (sessionId, userId, {positionId}) async {
          gotSession = sessionId;
          gotUser = userId;
          gotPosition = positionId;
          return 'b1';
        },
      );

      await service.book(userId: 'u1', sessionId: 's1', positionId: 'p7');
      expect(gotSession, 's1');
      expect(gotUser, 'u1');
      expect(gotPosition, 'p7');
    });

    test('repository errors propagate to the caller', () {
      final service = SportClubBookingService(
        (sessionId, userId, {positionId}) async =>
            throw StateError('POSITION_FULL'),
      );

      expect(
        () => service.book(userId: 'u1', sessionId: 's1'),
        throwsA(isA<StateError>()),
      );
    });
  });
}
