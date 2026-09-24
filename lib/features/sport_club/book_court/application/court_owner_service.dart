import '../data/book_court_models.dart';

typedef OwnerApplicationSubmit =
    Future<String> Function({
      required String userId,
      required String businessName,
      required String contactName,
      required String contactPhone,
      String? contactEmail,
      List<Map<String, dynamic>> evidence,
    });

typedef OwnerProfileGet = Future<VenueOwnerProfile?> Function(String userId);
typedef MyVenuesList = Future<List<VenueSummary>> Function(String userId);
typedef VenueUpsert =
    Future<String> Function({
      required String userId,
      String? venueId,
      required String name,
      String? description,
      String? province,
      String? district,
      String? address,
      double? lat,
      double? lng,
      String? timezone,
    });
typedef AdminApplicationsList =
    Future<List<VenueOwnerProfile>> Function(String adminId, {String status});
typedef AdminReview =
    Future<void> Function(
      String adminId,
      String ownerProfileId,
      String decision, {
      String? reason,
    });

/// Owner onboarding and venue management use cases for Book Court.
///
/// Keeps UI free of auth/repo decisions; every method takes the actor id
/// explicitly so it is unit-testable with fakes.
class CourtOwnerService {
  const CourtOwnerService({
    required this.submitApplication,
    required this.getMyOwnerProfile,
    required this.listMyVenues,
    required this.upsertVenue,
    required this.listApplications,
    required this.reviewApplication,
  });

  final OwnerApplicationSubmit submitApplication;
  final OwnerProfileGet getMyOwnerProfile;
  final MyVenuesList listMyVenues;
  final VenueUpsert upsertVenue;
  final AdminApplicationsList listApplications;
  final AdminReview reviewApplication;

  /// Whether the user can register venues (approved owner profile).
  Future<bool> canRegisterVenue(String? userId) async {
    if (userId == null || userId.isEmpty) return false;
    final profile = await getMyOwnerProfile(userId);
    return profile?.status == VenueOwnerStatus.approved;
  }

  Future<String?> applyAsOwner({
    required String? userId,
    required String businessName,
    required String contactName,
    required String contactPhone,
    String? contactEmail,
    List<Map<String, dynamic>> evidence = const [],
  }) {
    if (userId == null || userId.isEmpty) {
      return Future<String?>.value(null);
    }
    return submitApplication(
      userId: userId,
      businessName: businessName,
      contactName: contactName,
      contactPhone: contactPhone,
      contactEmail: contactEmail,
      evidence: evidence,
    );
  }
}
