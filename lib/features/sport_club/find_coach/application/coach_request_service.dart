import '../data/coach_models.dart';

typedef CoachRequestCreateCall =
    Future<String> Function({
      required String userId,
      required String coachId,
      required String sportId,
      required String teachingMode,
      required DateTime startsAt,
      required DateTime endsAt,
      String? message,
      String? idempotencyKey,
    });

typedef CoachRequestDecideCall =
    Future<void> Function(
      String userId,
      String requestId,
      String decision, {
      String? reason,
    });

typedef CoachRequestCancelCall =
    Future<void> Function(String userId, String requestId, {String? reason});

typedef CoachReviewSubmitCall =
    Future<String> Function({
      required String userId,
      required String requestId,
      required int rating,
      String? comment,
    });

/// Booking-request use cases for Find Coach.
///
/// Mirrors [BookCourtBookingService]: UI concerns stay in pages; this
/// service owns the "is there a user / invoke the repository" decision so
/// it is unit-testable with fakes. Slot validation and duplicate request
/// protection live server-side in `create_coach_booking_request`.
class CoachRequestService {
  const CoachRequestService({
    required this.createRequest,
    required this.decideRequest,
    required this.cancelRequest,
    required this.submitReview,
  });

  final CoachRequestCreateCall createRequest;
  final CoachRequestDecideCall decideRequest;
  final CoachRequestCancelCall cancelRequest;
  final CoachReviewSubmitCall submitReview;

  /// Sends a booking request to a coach. Returns null when [userId] is
  /// missing (caller routes to login). The server re-validates coach
  /// approval, sport coverage, teaching mode, availability and overlap.
  Future<String?> request({
    required String? userId,
    required CoachSummary coach,
    required String sportId,
    required TeachingMode teachingMode,
    required DateTime startsAt,
    required DateTime endsAt,
    String? message,
    String? idempotencyKey,
  }) {
    if (userId == null || userId.isEmpty) {
      return Future<String?>.value(null);
    }
    final mode = switch (teachingMode) {
      TeachingMode.online => 'online',
      _ => 'onsite',
    };
    return createRequest(
      userId: userId,
      coachId: coach.id,
      sportId: sportId,
      teachingMode: mode,
      startsAt: startsAt,
      endsAt: endsAt,
      message: message,
      idempotencyKey: idempotencyKey,
    );
  }

  /// Coach approves or rejects a pending request.
  Future<bool> decide({
    required String? userId,
    required CoachBookingRequest request,
    required bool approve,
    String? reason,
  }) async {
    if (userId == null || userId.isEmpty) return false;
    if (!request.isPending) return false;
    await decideRequest(
      userId,
      request.id,
      approve ? 'approve' : 'reject',
      reason: reason,
    );
    return true;
  }

  /// Requester or coach/admin cancels a pending/confirmed request.
  Future<bool> cancel({
    required String? userId,
    required CoachBookingRequest request,
    String? reason,
  }) async {
    if (userId == null || userId.isEmpty) return false;
    if (!request.isPending && !request.isConfirmed) return false;
    await cancelRequest(userId, request.id, reason: reason);
    return true;
  }

  /// Submits a review for a completed request. Eligibility (ownership,
  /// completed status, one review per booking, no self-review) is enforced
  /// server-side.
  Future<bool> review({
    required String? userId,
    required CoachBookingRequest request,
    required int rating,
    String? comment,
  }) async {
    if (userId == null || userId.isEmpty) return false;
    if (!request.isCompleted) return false;
    await submitReview(
      userId: userId,
      requestId: request.id,
      rating: rating,
      comment: comment,
    );
    return true;
  }
}
