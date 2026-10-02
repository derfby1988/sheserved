import 'package:flutter_test/flutter_test.dart';

import 'package:sheserved/features/sport_club/book_court/application/book_court_booking_service.dart';
import 'package:sheserved/features/sport_club/book_court/data/book_court_models.dart';

const _court = VenueCourt(
  id: 'court-1',
  venueId: 'venue-1',
  sportId: 'sport-1',
  name: 'Court 1',
);

VenueBooking _booking({
  VenueBookingStatus status = VenueBookingStatus.pending,
}) => VenueBooking(
  id: 'b1',
  courtId: 'court-1',
  venueId: 'venue-1',
  sportId: 'sport-1',
  startsAt: DateTime(2026, 10, 1, 18),
  endsAt: DateTime(2026, 10, 1, 19),
  status: status,
);

void main() {
  group('BookCourtBookingService.book', () {
    test(
      'returns null without calling the data source when user missing',
      () async {
        var calls = 0;
        final service = BookCourtBookingService(
          create:
              ({
                required userId,
                required courtId,
                required startsAt,
                required endsAt,
                required termsVersion,
                idempotencyKey,
                priceScheduleVersion,
              }) async {
                calls++;
                return 'b1';
              },
          cancel: (_, _, {reason}) async {},
          decide: (_, _, _, {reason}) async => 'confirmed',
          changeSlot:
              ({
                required userId,
                required bookingId,
                required startsAt,
                required endsAt,
                termsVersion,
                priceScheduleVersion,
              }) async {},
        );

        final startsAt = DateTime(2026, 10, 1, 18);
        expect(
          await service.book(
            userId: null,
            court: _court,
            startsAt: startsAt,
            endsAt: startsAt.add(const Duration(hours: 1)),
            termsVersion: 2,
          ),
          isNull,
        );
        expect(calls, 0);
      },
    );

    test('forwards court, slot, terms version and idempotency key', () async {
      String? gotCourt, gotKey;
      int? gotTerms, gotPriceScheduleVersion;
      final service = BookCourtBookingService(
        create:
            ({
              required userId,
              required courtId,
              required startsAt,
              required endsAt,
              required termsVersion,
              idempotencyKey,
              priceScheduleVersion,
            }) async {
              gotCourt = courtId;
              gotTerms = termsVersion;
              gotKey = idempotencyKey;
              gotPriceScheduleVersion = priceScheduleVersion;
              return 'booking-7';
            },
        cancel: (_, _, {reason}) async {},
        decide: (_, _, _, {reason}) async => 'confirmed',
        changeSlot:
            ({
              required userId,
              required bookingId,
              required startsAt,
              required endsAt,
              termsVersion,
              priceScheduleVersion,
            }) async {},
      );

      final startsAt = DateTime(2026, 10, 1, 18);
      final id = await service.book(
        userId: 'u1',
        court: _court,
        startsAt: startsAt,
        endsAt: startsAt.add(const Duration(hours: 2)),
        termsVersion: 3,
        idempotencyKey: 'idem-9',
        priceScheduleVersion: 7,
      );
      expect(id, 'booking-7');
      expect(gotCourt, 'court-1');
      expect(gotTerms, 3);
      expect(gotKey, 'idem-9');
      expect(gotPriceScheduleVersion, 7);
    });

    test('server errors (e.g. TERMS_VERSION_CHANGED) propagate', () {
      final service = BookCourtBookingService(
        create:
            ({
              required userId,
              required courtId,
              required startsAt,
              required endsAt,
              required termsVersion,
              idempotencyKey,
              priceScheduleVersion,
            }) async => throw StateError('TERMS_VERSION_CHANGED'),
        cancel: (_, _, {reason}) async {},
        decide: (_, _, _, {reason}) async => 'confirmed',
        changeSlot:
            ({
              required userId,
              required bookingId,
              required startsAt,
              required endsAt,
              termsVersion,
              priceScheduleVersion,
            }) async {},
      );

      final startsAt = DateTime(2026, 10, 1, 18);
      expect(
        () => service.book(
          userId: 'u1',
          court: _court,
          startsAt: startsAt,
          endsAt: startsAt.add(const Duration(hours: 1)),
          termsVersion: 1,
        ),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('BookCourtBookingService.bookSlots', () {
    test(
      'stops at failure and resumes remaining slots with original keys',
      () async {
        final calls = <String>[];
        final receivedStarts = <DateTime>[];
        var failSecond = true;
        final service = BookCourtBookingService(
          create:
              ({
                required userId,
                required courtId,
                required startsAt,
                required endsAt,
                required termsVersion,
                idempotencyKey,
                priceScheduleVersion,
              }) async {
                calls.add(idempotencyKey!);
                receivedStarts.add(startsAt);
                if (idempotencyKey == 'key-1' && failSecond) {
                  throw StateError('TERMS_VERSION_CHANGED');
                }
                return 'booking-$idempotencyKey';
              },
          cancel: (_, _, {reason}) async {},
          decide: (_, _, _, {reason}) async => 'confirmed',
          changeSlot:
              ({
                required userId,
                required bookingId,
                required startsAt,
                required endsAt,
                termsVersion,
                priceScheduleVersion,
              }) async {},
        );
        final slots = [
          for (var i = 0; i < 3; i++)
            (
              start: DateTime(2030, 1, 1, 10 + i * 3),
              end: DateTime(2030, 1, 1, 11 + i * 3),
              idempotencyKey: 'key-$i',
              priceScheduleVersion: 7,
            ),
        ];
        final first = await service.bookSlots(
          userId: 'u1',
          court: _court,
          slots: slots,
          termsVersion: 1,
        );
        expect(first.completed, 1);
        expect(first.error.toString(), contains('TERMS_VERSION_CHANGED'));
        expect(calls, ['key-0', 'key-1']);
        failSecond = false;
        final second = await service.bookSlots(
          userId: 'u1',
          court: _court,
          slots: slots.sublist(first.completed),
          termsVersion: 2,
        );
        expect(second.completed, 2);
        expect(second.error, isNull);
        expect(calls, ['key-0', 'key-1', 'key-1', 'key-2']);
        expect(receivedStarts, [
          slots[0].start,
          slots[1].start,
          slots[1].start,
          slots[2].start,
        ]);
      },
    );

    test('missing user cannot report a successful batch', () async {
      final service = BookCourtBookingService(
        create:
            ({
              required userId,
              required courtId,
              required startsAt,
              required endsAt,
              required termsVersion,
              idempotencyKey,
              priceScheduleVersion,
            }) async => throw StateError('must not call'),
        cancel: (_, _, {reason}) async {},
        decide: (_, _, _, {reason}) async => 'confirmed',
        changeSlot:
            ({
              required userId,
              required bookingId,
              required startsAt,
              required endsAt,
              termsVersion,
              priceScheduleVersion,
            }) async {},
      );
      final result = await service.bookSlots(
        userId: null,
        court: _court,
        slots: [
          (
            start: DateTime(2030),
            end: DateTime(2030, 1, 1, 1),
            idempotencyKey: 'key',
            priceScheduleVersion: null,
          ),
        ],
        termsVersion: 1,
      );
      expect(result.completed, 0);
      expect(result.error.toString(), contains('UNAUTHORIZED'));
    });
  });

  group('BookCourtBookingService.decideBooking', () {
    test(
      'returns null for missing user; approve maps to approve decision',
      () async {
        String? gotDecision;
        final service = BookCourtBookingService(
          create:
              ({
                required userId,
                required courtId,
                required startsAt,
                required endsAt,
                required termsVersion,
                idempotencyKey,
                priceScheduleVersion,
              }) async => 'b1',
          cancel: (_, _, {reason}) async {},
          decide: (_, _, decision, {reason}) async {
            gotDecision = decision;
            return 'confirmed';
          },
          changeSlot:
              ({
                required userId,
                required bookingId,
                required startsAt,
                required endsAt,
                termsVersion,
                priceScheduleVersion,
              }) async {},
        );

        expect(
          await service.decideBooking(
            userId: null,
            booking: _booking(),
            approve: true,
          ),
          isNull,
        );
        await service.decideBooking(
          userId: 'owner-1',
          booking: _booking(),
          approve: false,
          reason: 'full',
        );
        expect(gotDecision, 'reject');
      },
    );
  });

  group('BookCourtBookingService.movePendingSlot', () {
    test(
      'rejects non-pending bookings without calling the data source',
      () async {
        var calls = 0;
        final service = BookCourtBookingService(
          create:
              ({
                required userId,
                required courtId,
                required startsAt,
                required endsAt,
                required termsVersion,
                idempotencyKey,
                priceScheduleVersion,
              }) async => 'b1',
          cancel: (_, _, {reason}) async {},
          decide: (_, _, _, {reason}) async => 'confirmed',
          changeSlot:
              ({
                required userId,
                required bookingId,
                required startsAt,
                required endsAt,
                termsVersion,
                priceScheduleVersion,
              }) async {
                calls++;
              },
        );

        final ok = await service.movePendingSlot(
          userId: 'u1',
          booking: _booking(status: VenueBookingStatus.confirmed),
          startsAt: DateTime(2026, 10, 2, 18),
          endsAt: DateTime(2026, 10, 2, 19),
        );
        expect(ok, isFalse);
        expect(calls, 0);
      },
    );

    test('moves a pending booking to a new slot', () async {
      var calls = 0;
      final service = BookCourtBookingService(
        create:
            ({
              required userId,
              required courtId,
              required startsAt,
              required endsAt,
              required termsVersion,
              idempotencyKey,
              priceScheduleVersion,
            }) async => 'b1',
        cancel: (_, _, {reason}) async {},
        decide: (_, _, _, {reason}) async => 'confirmed',
        changeSlot:
            ({
              required userId,
              required bookingId,
              required startsAt,
              required endsAt,
              termsVersion,
              priceScheduleVersion,
            }) async {
              calls++;
            },
      );

      final ok = await service.movePendingSlot(
        userId: 'u1',
        booking: _booking(),
        startsAt: DateTime(2026, 10, 2, 18),
        endsAt: DateTime(2026, 10, 2, 19),
        termsVersion: 4,
      );
      expect(ok, isTrue);
      expect(calls, 1);
    });
  });
}
