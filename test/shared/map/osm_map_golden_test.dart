import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sheserved/features/admin/models/map_provider_config.dart';
import 'package:sheserved/shared/map/adapters/osm_adapter.dart';
import 'package:sheserved/shared/map/map_types.dart';
import 'package:sheserved/shared/map/testing/fake_tile_provider.dart';

/// Teardrop pin drawn with primitives — no font dependency in goldens.
class _FixturePin extends StatelessWidget {
  const _FixturePin({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
              border: Border.all(color: Colors.white, width: 3),
            ),
          ),
          Transform.rotate(
            angle: 0.785398,
            child: Container(width: 14, height: 14, color: color),
          ),
        ],
      );
}

const _source = TileSource(
  id: 'fake',
  label: 'Fake OSM',
  urlTemplate: 'https://tiles.invalid/{z}/{x}/{y}.png',
  attribution: '© Test contributors',
  readiness: TileSourceReadiness.ready,
);

/// Golden uses ONLY embedded fixtures — fake tile bytes + fixed marker/
/// polyline fixture. Never a live tile server (plan §11).
void main() {
  testWidgets('osm map with markers and polyline matches golden', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 400));
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: OsmMapAdapter(
          tileSource: _source,
          tileProvider: FakeTileProvider(),
          initialCamera: const MapCameraPosition(
            center: MapLatLng(13.7563, 100.5018),
            zoom: 14,
          ),
          markers: const {
            // Explicit markerWidgets — golden tests can't render icon fonts
            // (Ahem font → tofu boxes), so fixture markers draw real shapes.
            MapMarker(
              id: 'incident',
              position: MapLatLng(13.7600, 100.5100),
              markerWidget: _FixturePin(color: Colors.red),
            ),
            MapMarker(
              id: 'user',
              position: MapLatLng(13.7520, 100.4940),
              markerWidget: _FixturePin(color: Colors.blue),
            ),
          },
          polylines: const {
            MapPolyline(
              id: 'route',
              points: [
                MapLatLng(13.7520, 100.4940),
                MapLatLng(13.7600, 100.5100),
              ],
              color: Colors.red,
              width: 5,
            ),
          },
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(OsmMapAdapter),
      matchesGoldenFile('goldens/osm_map_markers_route.png'),
    );
  });
}
