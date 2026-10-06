import 'package:flutter_test/flutter_test.dart';
import 'package:sheserved/shared/map/map_controller.dart';
import 'package:sheserved/shared/map/map_types.dart';

void main() {
  group('MapLatLng', () {
    test('equality + hash', () {
      const a = MapLatLng(13.75, 100.5);
      const b = MapLatLng(13.75, 100.5);
      const c = MapLatLng(13.76, 100.5);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
    });
  });

  group('MapLatLngBounds', () {
    test('fromPoints empty → null', () {
      expect(MapLatLngBounds.fromPoints(const []), isNull);
    });

    test('fromPoints single → degenerate bounds', () {
      final b = MapLatLngBounds.fromPoints(const [MapLatLng(10, 20)])!;
      expect(b.southwest, const MapLatLng(10, 20));
      expect(b.northeast, const MapLatLng(10, 20));
      expect(b.isDegenerate, isTrue);
    });

    test('fromPoints multi → min/max corners regardless of order', () {
      final b = MapLatLngBounds.fromPoints(const [
        MapLatLng(14.0, 101.0),
        MapLatLng(13.0, 100.0),
        MapLatLng(13.5, 100.5),
      ])!;
      expect(b.southwest, const MapLatLng(13.0, 100.0));
      expect(b.northeast, const MapLatLng(14.0, 101.0));
      expect(b.isDegenerate, isFalse);
      expect(b.center, const MapLatLng(13.5, 100.5));
    });

    test('normalized expands degenerate axes only', () {
      // Flat along latitude (same lat, different lng).
      final flat = MapLatLngBounds.fromPoints(const [
        MapLatLng(13.0, 100.0),
        MapLatLng(13.0, 101.0),
      ])!;
      expect(flat.isDegenerate, isTrue);
      final n = flat.normalized();
      expect(n.isDegenerate, isFalse);
      expect(n.southwest.latitude, lessThan(13.0));
      expect(n.northeast.latitude, greaterThan(13.0));
      expect(n.southwest.longitude, 100.0);
      expect(n.northeast.longitude, 101.0);
    });
  });

  group('normalizedFitBounds', () {
    test('empty → null (caller must no-op)', () {
      expect(normalizedFitBounds(const []), isNull);
    });

    test('single point → null (caller animates instead)', () {
      expect(
        normalizedFitBounds(const [MapLatLng(13.7, 100.5)]),
        isNull,
      );
    });

    test('two identical points → null', () {
      expect(
        normalizedFitBounds(const [
          MapLatLng(13.7, 100.5),
          MapLatLng(13.7, 100.5),
        ]),
        isNull,
      );
    });

    test('two distinct points → normalized bounds', () {
      final b = normalizedFitBounds(const [
        MapLatLng(13.0, 100.0),
        MapLatLng(14.0, 101.0),
      ])!;
      expect(b.isDegenerate, isFalse);
      expect(b.southwest, const MapLatLng(13.0, 100.0));
    });

    test('collinear points → expanded to non-degenerate', () {
      final b = normalizedFitBounds(const [
        MapLatLng(13.0, 100.0),
        MapLatLng(13.0, 101.0),
      ])!;
      expect(b.isDegenerate, isFalse);
    });
  });

  group('MapCapabilities', () {
    test('google exposes traffic + puck, osm does not', () {
      expect(MapCapabilities.google.trafficLayer, isTrue);
      expect(MapCapabilities.google.myLocationPuck, isTrue);
      expect(MapCapabilities.osm.trafficLayer, isFalse);
      expect(MapCapabilities.osm.myLocationPuck, isFalse);
      expect(MapCapabilities.osm.customMarkerWidgets, isTrue);
    });
  });
}
