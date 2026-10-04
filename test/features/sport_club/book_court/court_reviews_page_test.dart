import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sheserved/features/sport_club/book_court/data/book_court_models.dart';
import 'package:sheserved/features/sport_club/book_court/data/book_court_repository.dart';
import 'package:sheserved/features/sport_club/book_court/presentation/pages/court_reviews_page.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _FakeBookCourtRepository extends BookCourtRepository {
  _FakeBookCourtRepository()
    : super(
        SupabaseClient(
          'https://example.com',
          'test-anon-key',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        ),
      );

  VenueReviewSummary summary = const VenueReviewSummary();
  List<VenueReview> reviews = const [];
  int totalCount = 0;
  List<VenueCourt> courts = const [];

  VenueReviewBand? lastBand;
  String? lastTagId;
  String? lastCourtId;
  VenueReviewSort? lastSort;
  int listCalls = 0;
  int summaryCalls = 0;
  final List<(String, bool)> helpfulCalls = [];

  @override
  Future<VenueReviewSummary> getVenueReviewSummary(
    String venueId, {
    String? courtId,
  }) async {
    summaryCalls++;
    lastCourtId = courtId;
    return summary;
  }

  @override
  Future<VenueReviewListPage> listVenueReviewsV2(
    String venueId, {
    String? courtId,
    String? tagId,
    VenueReviewBand? band,
    VenueReviewSort sort = VenueReviewSort.helpful,
    int limit = 20,
    int offset = 0,
    String? viewerId,
  }) async {
    listCalls++;
    lastBand = band;
    lastTagId = tagId;
    lastSort = sort;
    final page = reviews.skip(offset).take(limit).toList();
    return VenueReviewListPage(
      reviews: page,
      totalCount: totalCount,
      nextOffset: offset + page.length,
      hasMore: offset + page.length < totalCount,
    );
  }

  @override
  Future<List<VenueCourt>> listPublicCourts(
    String venueId, {
    String? sportId,
  }) async => courts;

  @override
  Future<void> setReviewHelpful(
    String userId,
    String reviewId, {
    required bool helpful,
  }) async {
    helpfulCalls.add((reviewId, helpful));
  }
}

VenueReview _review(
  String id, {
  required int rating10,
  int helpfulCount = 0,
  String? userId = 'reviewer-2',
  String? comment,
  List<String> tagLabels = const [],
}) => VenueReview(
  id: id,
  venueId: 'venue-1',
  courtId: 'court-1',
  bookingId: 'booking-$id',
  userId: userId ?? '',
  userDisplayName: 'ผู้ใช้$id',
  rating: (rating10 / 2).ceil(),
  rating10: rating10,
  comment: comment,
  courtName: 'คอร์ท 1',
  sportName: 'แบดมินตัน',
  tagLabels: tagLabels,
  helpfulCount: helpfulCount,
  createdAt: DateTime(2026, 7, 14),
);

const _summary = VenueReviewSummary(
  averageRating: 6.7,
  reviewCount: 7,
  bandCounts: {
    VenueReviewBand.excellent: 1,
    VenueReviewBand.good: 1,
    VenueReviewBand.fair: 3,
    VenueReviewBand.poor: 1,
    VenueReviewBand.veryPoor: 1,
  },
  categories: [
    VenueReviewCategoryScore(
      categoryId: 'cat-surface',
      key: 'surface',
      labelTh: 'สภาพพื้น/คุณภาพสนาม',
      average: 8.8,
      sampleCount: 3,
    ),
  ],
  topics: [
    VenueReviewTopic(tagId: 'tag-1', labelTh: 'ความสะอาด', reviewCount: 4),
  ],
);

Widget _harness(_FakeBookCourtRepository repo, {String? viewerId}) =>
    MaterialApp(
      home: CourtReviewsPage(
        venue: const VenueSummary(
          id: 'venue-1',
          name: 'สนามทดสอบ',
          averageRating: 6.7,
          reviewCount: 7,
        ),
        repo: repo,
        viewerId: viewerId,
      ),
    );

void main() {
  late _FakeBookCourtRepository repo;

  setUp(() async {
    repo = _FakeBookCourtRepository()
      ..summary = _summary
      ..totalCount = 1
      ..reviews = [
        _review(
          'r1',
          rating10: 10,
          helpfulCount: 3,
          comment: 'คอร์ทสะอาดมาก',
          tagLabels: ['สะอาด/ดูแลดี'],
        ),
      ];
  });

  testWidgets('shows overall score, band bars and a review item', (
    tester,
  ) async {
    await tester.pumpWidget(_harness(repo));
    await tester.pumpAndSettle();

    expect(find.text('สนามทดสอบ'), findsOneWidget);
    expect(find.text('6.7'), findsOneWidget);
    expect(find.text('7 รีวิว'), findsOneWidget);
    expect(find.text('ดีเลิศ: 9.0–10'), findsOneWidget);
    expect(find.text('แย่มาก: 1.0–2.9'), findsOneWidget);
    expect(find.text('10.0'), findsOneWidget);
    expect(find.text('จองจริง'), findsOneWidget);
    expect(find.text('มีประโยชน์ (3)'), findsOneWidget);
    expect(repo.summaryCalls, 1);
    expect(repo.listCalls, 1);
    expect(repo.lastSort, VenueReviewSort.helpful);
  });

  testWidgets('tapping a band filters the list server-side', (tester) async {
    await tester.pumpWidget(_harness(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.text('ดีเลิศ: 9.0–10'));
    await tester.pumpAndSettle();

    expect(repo.lastBand, VenueReviewBand.excellent);
    expect(repo.listCalls, 2);
  });

  testWidgets('topic chip under หัวข้อ tab filters by tag', (tester) async {
    await tester.pumpWidget(_harness(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.text('หัวข้อ'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ความสะอาด (4)'));
    await tester.pumpAndSettle();

    expect(repo.lastTagId, 'tag-1');
    expect(repo.listCalls, 2);
  });

  void useTallViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(900, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  testWidgets('guest sees a login snackbar instead of voting', (tester) async {
    useTallViewport(tester);
    await tester.pumpWidget(_harness(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.text('มีประโยชน์ (3)'));
    await tester.pumpAndSettle();

    expect(find.text('เข้าสู่ระบบเพื่อโหวตรีวิว'), findsOneWidget);
    expect(repo.helpfulCalls, isEmpty);
  });

  testWidgets('logged-in vote toggles the helpful count once', (tester) async {
    useTallViewport(tester);
    await tester.pumpWidget(_harness(repo, viewerId: 'user-1'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('มีประโยชน์ (3)'));
    await tester.pumpAndSettle();

    expect(repo.helpfulCalls, [('r1', true)]);
    expect(find.text('มีประโยชน์ (4)'), findsOneWidget);

    await tester.tap(find.text('มีประโยชน์ (4)'));
    await tester.pumpAndSettle();

    expect(repo.helpfulCalls, [('r1', true), ('r1', false)]);
    expect(find.text('มีประโยชน์ (3)'), findsOneWidget);
  });

  testWidgets('empty filter result shows the filtered empty state', (
    tester,
  ) async {
    repo
      ..summary = const VenueReviewSummary()
      ..reviews = const []
      ..totalCount = 0;
    await tester.pumpWidget(_harness(repo));
    await tester.pumpAndSettle();

    expect(find.text('ยังไม่มีรีวิว'), findsOneWidget);

    await tester.tap(find.text('ดีเลิศ: 9.0–10'));
    await tester.pumpAndSettle();

    expect(find.text('ไม่มีรีวิวตามตัวกรองนี้'), findsOneWidget);
  });
}
