import 'package:flutter_test/flutter_test.dart';

import 'package:sheserved/features/sport_club/find_coach/application/coach_request_service.dart';
import 'package:sheserved/features/sport_club/find_coach/data/coach_models.dart';

const _coach = CoachSummary(
  id: 'coach-1',
  userId: 'coach-user',
  displayName: 'Coach A',
);

CoachBookingRequest _request({
  CoachRequestStatus status = CoachRequestStatus.pending,
}) => CoachBookingRequest(
  id: 'req-1',
  coachId: 'coach-1',
  sportId: 'sport-1',
  startsAt: DateTime(2026, 10, 1, 18),
  endsAt: DateTime(2026, 10, 1, 19),
  status: status,
);

CoachRequestService _service({
  void Function()? onCreate,
  void Function(String decision)? onDecide,
  void Function()? onCancel,
  void Function()? onReview,
}) => CoachRequestService(
  createRequest: ({
    required userId,
    required coachId,
    required sportId,
    required teachingMode,
    required startsAt,
    required endsAt,
    message,
    idempotencyKey,
  }) async {
    onCreate?.call();
    return 'req-1';
  },
  decideRequest: (userId, requestId, decision, {reason}) async {
    onDecide?.call(decision);
  },
  cancelRequest: (userId, requestId, {reason}) async {
    onCancel?.call();
  },
  submitReview: ({
    required userId,
    required requestId,
    required rating,
    comment,
  }) async {
    onReview?.call();
    return 'rev-1';
  },
);

void main() {
  group('CoachRequestService.request', () {
    test('returns null without invoking the data source when logged out',
        () async {
      var calls = 0;
      final service = _service(onCreate: () => calls++);
      final id = await service.request(
        userId: null,
        coach: _coach,
        sportId: 'sport-1',
        teachingMode: TeachingMode.online,
        startsAt: DateTime(2026, 10, 1, 18),
        endsAt: DateTime(2026, 10, 1, 19),
      );
      expect(id, isNull);
      expect(calls, 0);
    });

    test('maps teaching modes and forwards the snapshot fields', () async {
      String? gotMode;
      final service = CoachRequestService(
        createRequest: ({
          required userId,
          required coachId,
          required sportId,
          required teachingMode,
          required startsAt,
          required endsAt,
          message,
          idempotencyKey,
        }) async {
          gotMode = teachingMode;
          return 'r';
        },
        decideRequest: (_, _, _, {reason}) async {},
        cancelRequest: (_, _, {reason}) async {},
        submitReview: ({
          required userId,
          required requestId,
          required rating,
          comment,
        }) async =>
            'rev',
      );

      await service.request(
        userId: 'u1',
        coach: _coach,
        sportId: 's1',
        teachingMode: TeachingMode.both,
        startsAt: DateTime(2026, 10, 1, 18),
        endsAt: DateTime(2026, 10, 1, 19),
      );
      // 'both' requests are stored as onsite+online-capable -> 'onsite'
      // per the service's mode mapping contract.
      expect(gotMode, 'onsite');
    });
  });

  group('CoachRequestService.decide', () {
    test('only pending requests can be decided', () async {
      var calls = 0;
      final service = _service(onDecide: (_) => calls++);

      expect(
        await service.decide(
          userId: 'coach-user',
          request: _request(status: CoachRequestStatus.confirmed),
          approve: true,
        ),
        isFalse,
      );
      expect(calls, 0);

      expect(
        await service.decide(
          userId: 'coach-user',
          request: _request(),
          approve: false,
          reason: 'busy',
        ),
        isTrue,
      );
      expect(calls, 1);
    });

    test('missing user never reaches the data source', () async {
      var calls = 0;
      final service = _service(onDecide: (_) => calls++);
      expect(
        await service.decide(
          userId: null,
          request: _request(),
          approve: true,
        ),
        isFalse,
      );
      expect(calls, 0);
    });
  });

  group('CoachRequestService.cancel', () {
    test('pending and confirmed are cancellable; terminal states are not',
        () async {
      var calls = 0;
      final service = _service(onCancel: () => calls++);

      for (final status in [
        CoachRequestStatus.pending,
        CoachRequestStatus.confirmed,
      ]) {
        expect(
          await service.cancel(
            userId: 'u1',
            request: _request(status: status),
          ),
          isTrue,
        );
      }
      for (final status in [
        CoachRequestStatus.completed,
        CoachRequestStatus.cancelled,
        CoachRequestStatus.rejected,
        CoachRequestStatus.expired,
      ]) {
        expect(
          await service.cancel(
            userId: 'u1',
            request: _request(status: status),
          ),
          isFalse,
        );
      }
      expect(calls, 2);
    });
  });

  group('CoachRequestService.review', () {
    test('reviews require a completed request', () async {
      var calls = 0;
      final service = _service(onReview: () => calls++);

      expect(
        await service.review(
          userId: 'u1',
          request: _request(status: CoachRequestStatus.confirmed),
          rating: 5,
        ),
        isFalse,
      );
      expect(
        await service.review(
          userId: 'u1',
          request: _request(status: CoachRequestStatus.completed),
          rating: 5,
          comment: 'great',
        ),
        isTrue,
      );
      expect(calls, 1);
    });
  });
}
