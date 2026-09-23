import 'package:flutter_test/flutter_test.dart';
import 'package:sheserved/features/sport_club/application/sport_club_data_freshness_policy.dart';

void main() {
  group('SportClubDataFreshnessPolicy', () {
    const policy = SportClubDataFreshnessPolicy();
    final now = DateTime.utc(2026, 9, 23, 12);

    test('refreshes if the feed has not loaded successfully yet', () {
      expect(policy.shouldRefresh(null, now: now), isTrue);
    });

    test('keeps recently fetched data fresh within the interval', () {
      expect(
        policy.shouldRefresh(
          now.subtract(const Duration(seconds: 59)),
          now: now,
        ),
        isFalse,
      );
    });

    test('refreshes when the freshness interval has elapsed', () {
      expect(
        policy.shouldRefresh(
          now.subtract(const Duration(seconds: 60)),
          now: now,
        ),
        isTrue,
      );
    });

    test('treats a future timestamp as fresh', () {
      expect(
        policy.shouldRefresh(now.add(const Duration(seconds: 30)), now: now),
        isFalse,
      );
    });
  });
}
