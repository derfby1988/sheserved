import '../data/book_court_models.dart';

typedef BookCourtCreateCall =
    Future<String> Function({
      required String userId,
      required String courtId,
      required DateTime startsAt,
      required DateTime endsAt,
      required int termsVersion,
      String? idempotencyKey,
    });

typedef BookCourtCancelCall =
    Future<void> Function(String userId, String bookingId, {String? reason});

typedef BookCourtDecideCall =
    Future<String> Function(
      String userId,
      String bookingId,
      String decision, {
      String? reason,
    });

typedef BookCourtChangeSlotCall =
    Future<void> Function({
      required String userId,
      required String bookingId,
      required DateTime startsAt,
      required DateTime endsAt,
      int? termsVersion,
    });

/// Booking use cases for Book Court.
///
/// UI concerns (login redirect, snackbars, feed reload, `mounted` checks)
/// stay in the page; this service owns the "is there a user / invoke the
/// repository" decision so it can be unit tested with a fake data source.
/// Terms consent is validated server-side; the client always sends the
/// version it displayed.
class BookCourtBookingService {
  const BookCourtBookingService({
    required this.create,
    required this.cancel,
    required this.decide,
    required this.changeSlot,
  });

  final BookCourtCreateCall create;
  final BookCourtCancelCall cancel;
  final BookCourtDecideCall decide;
  final BookCourtChangeSlotCall changeSlot;

  /// Creates a booking. Returns null when [userId] is missing (caller
  /// should route to login). `TERMS_VERSION_CHANGED` from the RPC means the
  /// venue terms moved while the dialog was open — the caller must re-show
  /// the terms dialog with the new version.
  Future<String?> book({
    required String? userId,
    required VenueCourt court,
    required DateTime startsAt,
    required DateTime endsAt,
    required int termsVersion,
    String? idempotencyKey,
  }) {
    if (userId == null || userId.isEmpty) {
      return Future<String?>.value(null);
    }
    return create(
      userId: userId,
      courtId: court.id,
      startsAt: startsAt,
      endsAt: endsAt,
      termsVersion: termsVersion,
      idempotencyKey: idempotencyKey,
    );
  }

  /// Cancels a booking. Booker path enforces the snapshot cutoff
  /// server-side; the manager path requires [reason].
  Future<bool> cancelBooking({
    required String? userId,
    required VenueBooking booking,
    String? reason,
  }) async {
    if (userId == null || userId.isEmpty) return false;
    await cancel(userId, booking.id, reason: reason);
    return true;
  }

  /// Approves or rejects a pending booking.
  /// Returns 'confirmed' | 'rejected' | 'conflict'; 'conflict' means the
  /// slot was taken while pending and the booking stays pending for the
  /// booker to move or cancel.
  Future<String?> decideBooking({
    required String? userId,
    required VenueBooking booking,
    required bool approve,
    String? reason,
  }) async {
    if (userId == null || userId.isEmpty) return null;
    return decide(
      userId,
      booking.id,
      approve ? 'approve' : 'reject',
      reason: reason,
    );
  }

  /// Moves a pending booking to a new slot on the same court.
  Future<bool> movePendingSlot({
    required String? userId,
    required VenueBooking booking,
    required DateTime startsAt,
    required DateTime endsAt,
    int? termsVersion,
  }) async {
    if (userId == null || userId.isEmpty) return false;
    if (!booking.isPending) return false;
    await changeSlot(
      userId: userId,
      bookingId: booking.id,
      startsAt: startsAt,
      endsAt: endsAt,
      termsVersion: termsVersion,
    );
    return true;
  }
}
