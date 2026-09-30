import 'package:flutter_test/flutter_test.dart';
import 'package:sheserved/features/sport_club/book_court/data/book_court_models.dart';

void main() {
  group('VenueReview.fromJson', () {
    test('reads the authoritative rating_10 when present', () {
      final review = VenueReview.fromJson({
        'id': 'r1',
        'venue_id': 'v1',
        'booking_id': 'b1',
        'user_id': 'u1',
        'rating': 4,
        'rating_10': 9,
      });
      expect(review.rating10, 9);
      expect(review.rating, 4);
    });

    test('falls back to rating * 2 for legacy rows without rating_10', () {
      final review = VenueReview.fromJson({
        'id': 'r1',
        'venue_id': 'v1',
        'booking_id': 'b1',
        'user_id': 'u1',
        'rating': 3,
      });
      expect(review.rating10, 6);
    });

    test('parses list fields from list_sports_venue_reviews_v2 rows', () {
      final review = VenueReview.fromJson({
        'id': 'r1',
        'venue_id': 'v1',
        'court_id': 'c1',
        'booking_id': 'b1',
        'user_id': 'u1',
        'rating_10': 8,
        'court_name': 'คอร์ท 2',
        'sport_name': 'แบดมินตัน',
        'helpful_count': 5,
        'viewer_voted': true,
        'tag_labels': ['สะอาด', 'คุ้มค่า'],
      });
      expect(review.courtName, 'คอร์ท 2');
      expect(review.sportName, 'แบดมินตัน');
      expect(review.helpfulCount, 5);
      expect(review.viewerVoted, isTrue);
      expect(review.tagLabels, ['สะอาด', 'คุ้มค่า']);
    });
  });

  group('VenueReviewSummary.fromJson', () {
    test('parses bands, categories and topics', () {
      final summary = VenueReviewSummary.fromJson({
        'average_rating': 6.7,
        'review_count': 7,
        'band_counts': {
          'excellent': 1,
          'good': 1,
          'fair': 3,
          'poor': 1,
          'very_poor': 1,
        },
        'categories': [
          {
            'category_id': 'cat-1',
            'key': 'surface',
            'label_th': 'สภาพพื้น/คุณภาพสนาม',
            'average': 8.8,
            'sample_count': 3,
          },
          {
            'category_id': 'cat-2',
            'key': 'value',
            'label_th': 'ความคุ้มค่า',
            'average': null,
            'sample_count': 0,
          },
        ],
        'topics': [
          {'tag_id': 't1', 'label_th': 'ความสะอาด', 'review_count': 4},
        ],
      });

      expect(summary.averageRating, 6.7);
      expect(summary.reviewCount, 7);
      expect(summary.bandCount(VenueReviewBand.fair), 3);
      expect(summary.categories.length, 2);
      expect(summary.categories.first.average, 8.8);
      expect(summary.categories.last.average, isNull);
      expect(summary.categories.last.sampleCount, 0);
      expect(summary.topics.single.reviewCount, 4);
    });
  });

  group('VenueReviewBand', () {
    test('labels share the deterministic bucket boundaries', () {
      expect(VenueReviewBand.excellent.label, 'ดีเลิศ: 9.0–10');
      expect(VenueReviewBand.good.label, 'ดี: 7.0–8.9');
      expect(VenueReviewBand.fair.label, 'พอใช้ได้: 5.0–6.9');
      expect(VenueReviewBand.poor.label, 'แย่: 3.0–4.9');
      expect(VenueReviewBand.veryPoor.label, 'แย่มาก: 1.0–2.9');
    });

    test('bands cover the whole 1–10 range without overlap', () {
      var covered = 0;
      for (var score = 1; score <= 10; score++) {
        final hits = VenueReviewBand.values
            .where((b) => score >= b.min && score <= b.max)
            .length;
        expect(hits, 1, reason: 'score $score must fall in one band');
        covered += hits;
      }
      expect(covered, 10);
    });
  });

  group('VenueBooking.fromJson', () {
    test('reads the venue timezone from booking RPC data', () {
      final booking = VenueBooking.fromJson({
        'id': 'booking-1',
        'courtId': 'court-1',
        'venueId': 'venue-1',
        'sportId': 'sport-1',
        'startsAt': '2026-09-30T18:00:00Z',
        'endsAt': '2026-09-30T19:00:00Z',
        'status': 'pending',
        'timezone': 'Asia/Bangkok',
      });

      expect(booking.timezone, 'Asia/Bangkok');
    });

    test('defaults legacy booking payloads to Bangkok timezone', () {
      final booking = VenueBooking.fromJson({
        'id': 'booking-1',
        'courtId': 'court-1',
        'venueId': 'venue-1',
        'sportId': 'sport-1',
        'startsAt': '2026-09-30T18:00:00Z',
        'endsAt': '2026-09-30T19:00:00Z',
        'status': 'pending',
      });

      expect(booking.timezone, 'Asia/Bangkok');
    });
  });
}
