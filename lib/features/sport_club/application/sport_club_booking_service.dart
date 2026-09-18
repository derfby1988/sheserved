typedef SportClubBookCall = Future<String> Function(
  String sessionId,
  String userId, {
  String? positionId,
});

/// Booking use case for sport-club sessions.
///
/// UI concerns (login redirect, snackbars, feed reload, `mounted` checks)
/// stay in the page; this service owns only the "is there a user / invoke
/// the repository" decision so it can be unit tested with a fake data
/// source.
class SportClubBookingService {
  const SportClubBookingService(this._book);

  final SportClubBookCall _book;

  /// Returns the booking id on success, `null` when [userId] is missing
  /// (the caller should route to login), and rethrows repository errors.
  Future<String?> book({
    required String? userId,
    required String sessionId,
    String? positionId,
  }) {
    if (userId == null || userId.isEmpty) {
      return Future<String?>.value(null);
    }
    return _book(sessionId, userId, positionId: positionId);
  }
}
