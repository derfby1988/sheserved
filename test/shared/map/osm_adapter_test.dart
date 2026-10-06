import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:flutter_test/flutter_test.dart';
import 'package:sheserved/features/admin/models/map_provider_config.dart';
import 'package:sheserved/shared/map/adapters/osm_adapter.dart';
import 'package:sheserved/shared/map/map_controller.dart';
import 'package:sheserved/shared/map/map_types.dart';
import 'package:sheserved/shared/map/testing/fake_tile_provider.dart';

const _source = TileSource(
  id: 'fake',
  label: 'Fake OSM',
  urlTemplate: 'https://tiles.invalid/{z}/{x}/{y}.png',
  attribution: '© Test contributors',
  readiness: TileSourceReadiness.ready,
);

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('renders FlutterMap + markers + polyline + attribution', (tester) async {
    await tester.pumpWidget(_wrap(OsmMapAdapter(
      tileSource: _source,
      tileProvider: FakeTileProvider(),
      markers: const {
        MapMarker(id: 'incident', position: MapLatLng(13.75, 100.50), hue: 0),
        MapMarker(id: 'user', position: MapLatLng(13.76, 100.51), hue: 210),
      },
      polylines: const {
        MapPolyline(
          id: 'route',
          points: [MapLatLng(13.75, 100.50), MapLatLng(13.76, 100.51)],
        ),
      },
    )));
    await tester.pumpAndSettle();

    expect(find.byType(fm.FlutterMap), findsOneWidget);
    expect(find.byType(fm.MarkerLayer), findsOneWidget);
    expect(find.byType(fm.PolylineLayer), findsOneWidget);
    expect(find.byType(fm.RichAttributionWidget), findsOneWidget);
    expect(find.byIcon(Icons.location_pin), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('onMapCreated hands a working facade; camera commands apply', (tester) async {
    SheservedMapController? facade;
    await tester.pumpWidget(_wrap(OsmMapAdapter(
      tileSource: _source,
      tileProvider: FakeTileProvider(),
      onMapCreated: (c) => facade = c,
    )));
    await tester.pumpAndSettle();
    expect(facade, isNotNull);
    expect(facade!.isDisposed, isFalse);

    // Single point → no crash, moves to fallback zoom (contract §6.2).
    facade!.fitToBounds(const [MapLatLng(13.7, 100.5)]);
    // Zero-area bounds (two identical points) → same path, no throw.
    facade!.fitToBounds(const [MapLatLng(13.7, 100.5), MapLatLng(13.7, 100.5)]);
    facade!.fitToBounds(const [MapLatLng(13.0, 100.0), MapLatLng(14.0, 101.0)]);
    facade!.moveTo(const MapLatLng(13.8, 100.6), zoom: 12);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('dispose → facade becomes no-op, no crash', (tester) async {
    SheservedMapController? facade;
    await tester.pumpWidget(_wrap(OsmMapAdapter(
      tileSource: _source,
      tileProvider: FakeTileProvider(),
      onMapCreated: (c) => facade = c,
    )));
    await tester.pumpAndSettle();

    // Unmount the map.
    await tester.pumpWidget(_wrap(const SizedBox()));
    expect(facade!.isDisposed, isTrue);

    // Commands after dispose must not throw (async callbacks racing teardown).
    facade!.moveTo(const MapLatLng(13.8, 100.6));
    facade!.fitToBounds(const [MapLatLng(13.0, 100.0), MapLatLng(14.0, 101.0)]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('map tap forwards coordinate', (tester) async {
    MapLatLng? tapped;
    await tester.pumpWidget(_wrap(SizedBox(
      width: 400,
      height: 400,
      child: OsmMapAdapter(
        tileSource: _source,
        tileProvider: FakeTileProvider(),
        onTap: (p) => tapped = p,
      ),
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(fm.FlutterMap));
    // flutter_map debounces single taps ~250ms to detect double-tap zoom.
    await tester.pump(const Duration(milliseconds: 300));
    expect(tapped, isNotNull);
    expect(tapped!.latitude, closeTo(13.7563, 0.5));
    expect(tapped!.longitude, closeTo(100.5018, 0.5));
  });

  testWidgets('marker tap fires callback', (tester) async {
    var taps = 0;
    await tester.pumpWidget(_wrap(SizedBox(
      width: 400,
      height: 400,
      child: OsmMapAdapter(
        tileSource: _source,
        tileProvider: FakeTileProvider(),
        markers: {
          MapMarker(
            id: 'm1',
            position: const MapLatLng(13.7563, 100.5018),
            onTap: () => taps++,
          ),
        },
      ),
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.location_pin));
    expect(taps, 1);
  });

  testWidgets('user location dot renders from provided position (no puck)', (tester) async {
    await tester.pumpWidget(_wrap(OsmMapAdapter(
      tileSource: _source,
      tileProvider: FakeTileProvider(),
      showUserLocation: true,
      userLocation: const MapLatLng(13.76, 100.51),
    )));
    await tester.pumpAndSettle();
    final layer = tester.widget<fm.MarkerLayer>(find.byType(fm.MarkerLayer));
    expect(layer.markers, hasLength(1));
  });

  testWidgets('hueToColor covers hue range without crash', (tester) async {
    for (final h in [0.0, 60.0, 120.0, 210.0, 360.0]) {
      expect(hueToColor(h).a, 1.0);
    }
  });
}
