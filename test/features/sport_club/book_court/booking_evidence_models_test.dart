import 'package:flutter_test/flutter_test.dart';
import 'package:sheserved/features/sport_club/book_court/data/book_court_models.dart';

void main() {
  group('VenueEvidencePolicy.toJson (server contract)', () {
    test('serialises the exact snake_case JSONB the validator accepts', () {
      const policy = VenueEvidencePolicy(
        requirements: [
          EvidenceRequirement(
            key: 'slip',
            label: 'สลิปโอนเงิน',
            kind: 'payment_slip',
            stage: 'payment',
            reviewMode: 'auto_verify',
            required: true,
          ),
        ],
        deadlineMode: 'per_booking',
        minutes: 30,
        ownerApprovalDeadlineEnabled: true,
        minGraceMinutes: 10,
        ownerDecisionMinutes: 1440,
        maxHoldsPerUser: 3,
        paymentDestination: 'promptpay:0812345678',
      );
      final json = policy.toJson();
      expect(json['deadline_mode'], 'per_booking');
      expect(json['minutes'], 30);
      expect(json['owner_approval_deadline_enabled'], true);
      expect(json['min_grace_minutes'], 10);
      expect(json['owner_decision_minutes'], 1440);
      expect(json['max_holds_per_user'], 3);
      expect(json['payment_destination'], 'promptpay:0812345678');
      final req = (json['requirements'] as List).single as Map;
      expect(req['kind'], 'payment_slip');
      expect(req['stage'], 'payment');
      expect(req['review_mode'], 'auto_verify');
    });

    test('round-trips through fromJson with camelCase variants', () {
      final policy = VenueEvidencePolicy.fromJson({
        'requirements': [
          {
            'key': 'id',
            'label': 'บัตรประชาชน',
            'kind': 'document',
            'stage': 'booking',
            'review_mode': 'auto',
            'required': false,
          },
        ],
        'deadlineMode': 'after_release',
        'minGraceMinutes': 5,
        'ownerDecisionMinutes': 720,
        'maxHoldsPerUser': 2,
      });
      expect(policy.deadlineMode, 'after_release');
      expect(policy.minGraceMinutes, 5);
      expect(policy.requirements.single.isDocument, true);
      expect(policy.requirements.single.reviewMode, 'auto');
    });
  });

  group('CourtEvidenceSurface', () {
    test('parses the sanitized booker surface', () {
      final s = CourtEvidenceSurface.fromJson({
        'source': 'court',
        'requirements': [
          {
            'key': 'slip',
            'label': 'สลิป',
            'kind': 'payment_slip',
            'stage': 'payment',
            'review_mode': 'owner_review',
            'required': true,
          },
        ],
        'deadlineMode': 'release_day_time',
        'deadlineTime': '20:00:00',
        'minGraceMinutes': 15,
        'ownerDecisionMinutes': 2880,
        'ownerApprovalDeadlineEnabled': true,
        'maxHoldsPerUser': 4,
        'requiresPaymentSlip': true,
      });
      expect(s.source, 'court');
      expect(s.requiresPaymentSlip, true);
      expect(s.deadlineTime, '20:00:00');
      expect(s.requirements.single.isPaymentSlip, true);
    });
  });

  group('VenueBookingGroup', () {
    test('parses children, evidence, claims and refunds', () {
      final g = VenueBookingGroup.fromJson({
        'id': 'g1',
        'venueId': 'v1',
        'status': 'awaiting_evidence',
        'totalAmount': 400,
        'currency': 'THB',
        'evidenceDeadline': '2040-01-02T10:00:00Z',
        'bookings': [
          {
            'id': 'b1',
            'courtId': 'c1',
            'courtName': 'Court 1',
            'startsAt': '2040-01-05T08:00:00Z',
            'endsAt': '2040-01-05T09:00:00Z',
            'status': 'awaiting_evidence',
            'priceTotal': 200,
            'unitLabel': 'ชั่วโมง',
          },
          {
            'id': 'b2',
            'courtId': 'c1',
            'courtName': 'Court 1',
            'startsAt': '2040-01-05T09:00:00Z',
            'endsAt': '2040-01-05T10:00:00Z',
            'status': 'awaiting_evidence',
            'priceTotal': 200,
          },
        ],
        'requirements': [
          {
            'key': 'slip',
            'label': 'สลิป',
            'kind': 'payment_slip',
            'stage': 'payment',
            'review_mode': 'owner_review',
            'required': true,
          },
        ],
        'evidence': [
          {
            'id': 'e1',
            'requirementKey': 'slip',
            'kind': 'payment_slip',
            'verificationStatus': 'pending',
            'revision': 1,
          },
        ],
        'claims': [
          {
            'id': 'cl1',
            'reportedAmount': 400,
            'status': 'submitted',
          },
        ],
        'refundCases': [
          {
            'id': 'r1',
            'allocatedAmount': 200,
            'status': 'open',
            'reason': 'partial cancel',
          },
        ],
      });
      expect(g.status, BookingGroupStatus.awaitingEvidence);
      expect(g.bookings.length, 2);
      expect(g.bookings.first.unitLabel, 'ชั่วโมง');
      expect(
        g.evidence.single.verificationStatus,
        GroupEvidenceVerification.pending,
      );
      expect(g.claims.single.reportedAmount, 400);
      expect(g.refundCases.single.status, 'open');
    });
  });

  group('GlobalSlipVerificationPolicy', () {
    test('decodes platform scope and rollout counts', () {
      final policy = GlobalSlipVerificationPolicy.fromJson({
        'scope': 'whitelist',
        'approvedVenueCount': 12,
        'allowlistedVenueCount': 3,
        'configuredProviderCount': 1,
      });
      expect(policy.scope, 'whitelist');
      expect(policy.approvedVenueCount, 12);
      expect(policy.allowlistedVenueCount, 3);
      expect(policy.configuredProviderCount, 1);
    });

    test('defaults global scope to disabled', () {
      expect(GlobalSlipVerificationPolicy.fromJson({}).scope, 'disabled');
    });
  });

  group('AdminVenueVerifyPolicy', () {
    test('decodes per-venue allowlist, estimate and reserved-call signals', () {
      final v = AdminVenueVerifyPolicy.fromJson({
        'venueId': 'v1',
        'name': 'สนามทดสอบ',
        'status': 'approved',
        'globalScope': 'whitelist',
        'isAllowlisted': true,
        'isAutoVerifyAllowed': true,
        'costBearer': 'owner',
        'monthlyQuota': 500,
        'verifyTimeoutMinutes': 30,
        'hasEvidencePolicy': true,
        'configuredProviderCount': 1,
        'callsThisMonth': 12,
        'pendingCallsThisMonth': 2,
        'costEstimateThisMonth': 18.5,
        'lastCallAt': '2026-10-11T10:00:00Z',
      });
      expect(v.venueId, 'v1');
      expect(v.globalScope, 'whitelist');
      expect(v.isAllowlisted, isTrue);
      expect(v.costBearer, 'owner');
      expect(v.monthlyQuota, 500);
      expect(v.isScopeEnabled, isTrue);
      expect(v.isVerifyReady, isTrue);
      expect(v.isQuotaExhausted, isFalse);
      expect(v.callsThisMonth, 12);
      expect(v.pendingCallsThisMonth, 2);
      expect(v.costEstimateThisMonth, 18.5);
      expect(v.lastCallAt, DateTime.utc(2026, 10, 11, 10));
    });

    test('defaults to disabled without providers or quota', () {
      final v = AdminVenueVerifyPolicy.fromJson({
        'venueId': 'v2',
        'name': 'สนามใหม่',
      });
      expect(v.globalScope, 'disabled');
      expect(v.isAllowlisted, isFalse);
      expect(v.costBearer, 'platform');
      expect(v.monthlyQuota, isNull);
      expect(v.isScopeEnabled, isFalse);
      expect(v.isVerifyReady, isFalse);
      expect(v.isQuotaExhausted, isFalse);
    });

    test('whitelist needs both global scope and per-venue allowlisting', () {
      final blocked = AdminVenueVerifyPolicy.fromJson({
        'venueId': 'v3',
        'name': 'สนามนอก allowlist',
        'globalScope': 'whitelist',
        'isAllowlisted': false,
        'configuredProviderCount': 1,
      });
      expect(blocked.isScopeEnabled, isFalse);
      expect(blocked.isVerifyReady, isFalse);
      final allowed = AdminVenueVerifyPolicy.fromJson({
        'venueId': 'v4',
        'name': 'สนามใน allowlist',
        'globalScope': 'whitelist',
        'isAllowlisted': true,
        'configuredProviderCount': 1,
        'isAutoVerifyAllowed': true,
      });
      expect(allowed.isScopeEnabled, isTrue);
      expect(allowed.isVerifyReady, isTrue);
    });

    test('quota exhaustion follows reserved provider attempts', () {
      final v = AdminVenueVerifyPolicy.fromJson({
        'venueId': 'v5',
        'name': 'สนามโควตาหมด',
        'globalScope': 'all',
        'monthlyQuota': 10,
        'callsThisMonth': 10,
        'configuredProviderCount': 2,
        'isAutoVerifyAllowed': true,
      });
      expect(v.isQuotaExhausted, isTrue);
      expect(v.isVerifyReady, isTrue);
    });
  });

  group('OwnerEvidenceQueue', () {
    test('parses defer state, cursor pagination and bulk helpers', () {
      final q = OwnerEvidenceQueue.fromJson({
        'serverNow': '2026-10-14T10:00:00Z',
        'hasMore': true,
        'nextCursor': {
          'due': '2026-10-20T03:00:00Z',
          'created': '2026-10-14T01:00:00Z',
          'id': 'g1',
        },
        'deferredCount': 2,
        'groups': [
          {
            'id': 'g1',
            'venueId': 'v1',
            'status': 'awaiting_evidence',
            'stage': 'payment',
            'approvalMode': 'instant',
            'bookerName': 'สมชาย',
            'deferredUntil': '2026-10-14T12:00:00Z',
            'firstStartsAt': '2026-10-20T03:00:00Z',
            'hasPendingSlip': true,
          },
        ],
      });
      expect(q.hasMore, isTrue);
      expect(q.nextCursor?.id, 'g1');
      expect(q.nextCursor?.due, '2026-10-20T03:00:00Z');
      expect(q.deferredCount, 2);
      final g = q.groups.single;
      expect(g.deferredUntil, DateTime.utc(2026, 10, 14, 12));
      expect(g.firstStartsAt, DateTime.utc(2026, 10, 20, 3));
      expect(g.hasPendingSlip, isTrue);
      expect(g.isAwaitingEvidence, isTrue);
    });

    test('defaults to a first page without cursor', () {
      final q = OwnerEvidenceQueue.fromJson({'groups': []});
      expect(q.hasMore, isFalse);
      expect(q.nextCursor, isNull);
      expect(q.deferredCount, 0);
    });
  });

  group('OwnerQueueBulkResult', () {
    test('decodes per-group results and errors', () {
      final ok = OwnerQueueBulkResult.fromJson({
        'groupId': 'g1',
        'result': 'rejected',
      });
      final failed = OwnerQueueBulkResult.fromJson({
        'groupId': 'g2',
        'error': 'GROUP_NOT_OPEN',
      });
      expect(ok.ok, isTrue);
      expect(failed.ok, isFalse);
      expect(failed.error, 'GROUP_NOT_OPEN');
    });
  });

  group('status enums', () {
    test('new statuses decode from server strings', () {
      expect(
        venueBookingStatusFrom('awaiting_evidence'),
        VenueBookingStatus.awaitingEvidence,
      );
      expect(
        venueBookingStatusFrom('forfeited'),
        VenueBookingStatus.forfeited,
      );
      expect(
        venueBookingStatusFrom('unknown_value'),
        VenueBookingStatus.pending,
      );
    });
  });
}
