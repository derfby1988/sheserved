import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gm;
import 'package:sheserved/features/admin/models/map_provider_config.dart';
import 'package:sheserved/shared/map/sheserved_map.dart';
import 'package:sheserved/shared/map/testing/fake_tile_provider.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('google target → GoogleMap widget', (tester) async {
    await tester.pumpWidget(_wrap(const SheservedMap(
      target: MapTarget(enabled: true, renderer: MapRendererKind.google),
    )));
    expect(find.byType(gm.GoogleMap), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('osm target with known tile source → FlutterMap', (tester) async {
    await tester.pumpWidget(_wrap(SheservedMap(
      target: const MapTarget(
        enabled: true,
        renderer: MapRendererKind.osm,
        tileSourceId: 'osm_standard',
      ),
      tileProvider: FakeTileProvider(),
    )));
    await tester.pumpAndSettle();
    expect(find.byType(fm.FlutterMap), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('disabled target → explicit placeholder, not a map', (tester) async {
    await tester.pumpWidget(_wrap(const SheservedMap(
      target: MapTarget(enabled: false, renderer: MapRendererKind.google),
    )));
    expect(find.byType(gm.GoogleMap), findsNothing);
    expect(find.byType(fm.FlutterMap), findsNothing);
    expect(find.textContaining('แผนที่ถูกปิด'), findsOneWidget);
  });

  testWidgets('unknown tile source → visible error, no silent fallback', (tester) async {
    await tester.pumpWidget(_wrap(const SheservedMap(
      target: MapTarget(
        enabled: true,
        renderer: MapRendererKind.osm,
        tileSourceId: 'nonexistent',
      ),
    )));
    expect(find.byType(fm.FlutterMap), findsNothing);
    expect(find.byType(gm.GoogleMap), findsNothing); // no hidden Google fallback
    expect(find.textContaining('nonexistent'), findsOneWidget);
  });

  testWidgets('capabilities reflect the resolved renderer', (tester) async {
    const googleMap = SheservedMap(
      target: MapTarget(enabled: true, renderer: MapRendererKind.google),
    );
    const osmMap = SheservedMap(
      target: MapTarget(enabled: true, renderer: MapRendererKind.osm),
    );
    expect(googleMap.capabilities.trafficLayer, isTrue);
    expect(osmMap.capabilities.trafficLayer, isFalse);
  });
}
