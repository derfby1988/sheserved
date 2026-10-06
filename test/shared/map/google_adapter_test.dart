import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gm;
import 'package:sheserved/shared/map/adapters/google_adapter.dart';
import 'package:sheserved/shared/map/map_types.dart';

void main() {
  group('google adapter conversion', () {
    test('latlng round-trips coordinates', () {
      final g = toGoogleLatLng(const MapLatLng(13.7563, 100.5018));
      expect(g.latitude, 13.7563);
      expect(g.longitude, 100.5018);
    });

    test('camera position keeps zoom/bearing/tilt', () {
      final g = toGoogleCameraPosition(const MapCameraPosition(
        center: MapLatLng(13.7, 100.5),
        zoom: 16,
        bearing: 30,
        tilt: 45,
      ));
      expect(g.zoom, 16);
      expect(g.bearing, 30);
      expect(g.tilt, 45);
      expect(g.target, const gm.LatLng(13.7, 100.5));
    });

    test('marker conversion keeps id/hue/label/tap', () {
      var tapped = false;
      final m = toGoogleMarker(MapMarker(
        id: 'incident',
        position: const MapLatLng(13.7, 100.5),
        hue: gm.BitmapDescriptor.hueRed,
        label: 'เหตุฉุกเฉิน',
        onTap: () => tapped = true,
      ));
      expect(m.markerId, const gm.MarkerId('incident'));
      expect(m.position, const gm.LatLng(13.7, 100.5));
      expect(m.infoWindow.title, 'เหตุฉุกเฉิน');
      m.onTap!();
      expect(tapped, isTrue);
    });

    test('marker without label has no info window', () {
      final m = toGoogleMarker(const MapMarker(
        id: 'a',
        position: MapLatLng(1, 1),
      ));
      expect(m.infoWindow, gm.InfoWindow.noText);
    });

    test('polyline conversion keeps points/color/width + round caps', () {
      final p = toGooglePolyline(const MapPolyline(
        id: 'route',
        points: [MapLatLng(13.0, 100.0), MapLatLng(14.0, 101.0)],
        color: Colors.red,
        width: 5,
      ));
      expect(p.polylineId, const gm.PolylineId('route'));
      expect(p.points, [
        const gm.LatLng(13.0, 100.0),
        const gm.LatLng(14.0, 101.0),
      ]);
      expect(p.color, Colors.red);
      expect(p.width, 5);
      expect(p.patterns, isEmpty);
    });

    test('dashed polyline emits dash pattern', () {
      final p = toGooglePolyline(const MapPolyline(
        id: 'route',
        points: [MapLatLng(13.0, 100.0), MapLatLng(14.0, 101.0)],
        dashed: true,
      ));
      expect(p.patterns, isNotEmpty);
    });

    test('bounds conversion keeps corners', () {
      final b = toGoogleBounds(const MapLatLngBounds(
        southwest: MapLatLng(13.0, 100.0),
        northeast: MapLatLng(14.0, 101.0),
      ));
      expect(b.southwest, const gm.LatLng(13.0, 100.0));
      expect(b.northeast, const gm.LatLng(14.0, 101.0));
    });
  });
}
