import 'package:flutter_test/flutter_test.dart';
import 'package:sheserved/shared/map/map_controller.dart';
import 'package:sheserved/shared/map/map_types.dart';

void main() {
  group('FakeSheservedMapController', () {
    test('records commands', () {
      final c = FakeSheservedMapController();
      const p = MapLatLng(13.7, 100.5);
      c.moveTo(p, zoom: 12);
      c.animateTo(p);
      c.fitToBounds(const [p, MapLatLng(14, 101)], padding: 40);

      expect(c.calls, ['moveTo', 'animateTo', 'fitToBounds']);
      expect(c.lastTarget, p);
      expect(c.lastZoom, isNull);
      expect(c.lastFitPoints, hasLength(2));
      expect(c.lastFitPadding, 40);
    });

    test('dispose → isDisposed + commands become no-ops', () {
      final c = FakeSheservedMapController();
      c.dispose();
      expect(c.isDisposed, isTrue);
      c.moveTo(const MapLatLng(1, 1));
      c.fitToBounds(const [MapLatLng(1, 1)]);
      expect(c.calls, isEmpty);
    });
  });
}
