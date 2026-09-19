import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sheserved/features/sport_club/application/sport_club_filter_store.dart';
import 'package:sheserved/features/sport_club/domain/sport_club_filter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const store = SportClubFilterStore();
  const filter = SportClubFilter(
    sportId: 'sport-1',
    q: 'court',
    province: 'กรุงเทพมหานคร',
    district: 'จตุจักร',
    openOnly: true,
    joinedOnly: true,
    managedOnly: true,
    allLevelsOnly: true,
    genderAnyOnly: true,
    noFeesOnly: true,
    locationEnabled: true,
    radiusKm: 25,
  );

  group('SportClubFilterStore', () {
    test('returns null when nothing stored or user missing', () async {
      SharedPreferences.setMockInitialValues({});
      expect(await store.load('u1'), isNull);
      expect(await store.load(null), isNull);
      expect(await store.load(''), isNull);
    });

    test('save then load round-trips the filter', () async {
      SharedPreferences.setMockInitialValues({});
      await store.save('u1', filter);
      expect(await store.load('u1'), filter);
    });

    test('filters are isolated per user id', () async {
      SharedPreferences.setMockInitialValues({});
      await store.save('u1', filter);
      await store.save('u2', const SportClubFilter());
      expect(await store.load('u1'), filter);
      expect(await store.load('u2'), const SportClubFilter());
      expect(await store.load('u3'), isNull);
    });

    test('malformed storage falls back to null', () async {
      SharedPreferences.setMockInitialValues({
        'sport_club_filters_v1_u1': 'not-json{',
        'sport_club_filters_v1_u2': '42',
      });
      expect(await store.load('u1'), isNull);
      expect(await store.load('u2'), isNull);
    });

    test('legacy v1 payload restores with same semantics', () async {
      SharedPreferences.setMockInitialValues({
        'sport_club_filters_v1_u1':
            '{"sportId":"s9","q":"q","province":"p","district":"d",'
            '"openOnly":true,"joinedOnly":false,"managedOnly":true,'
            '"locationEnabled":true,"radiusKm":33}',
      });
      final restored = await store.load('u1');
      expect(restored, isNotNull);
      expect(restored!.sportId, 's9');
      expect(restored.openOnly, isTrue);
      expect(restored.joinedOnly, isFalse);
      expect(restored.managedOnly, isTrue);
      expect(restored.radiusKm, 33);
    });
  });
}
