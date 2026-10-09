import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gm;
import 'package:sheserved/features/admin/models/map_provider_config.dart';
import 'package:sheserved/features/community/find_buddies/presentation/widgets/venue_location_picker.dart';
import 'package:sheserved/shared/map/map_types.dart';
import 'package:sheserved/shared/map/testing/fake_tile_provider.dart';

const _osmTarget = MapTarget(
  enabled: true,
  renderer: MapRendererKind.osm,
  tileSourceId: 'osm_standard',
);
const _googleTarget = MapTarget(
  enabled: true,
  renderer: MapRendererKind.google,
);
const _offTarget = MapTarget(enabled: false, renderer: MapRendererKind.google);

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('VenueLocationMap', () {
    testWidgets('osm target renders FlutterMap with the picked pin', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          SizedBox(
            width: 400,
            height: 200,
            child: VenueLocationMap(
              target: _osmTarget,
              picked: const MapLatLng(13.75, 100.50),
              tileProvider: FakeTileProvider(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(fm.FlutterMap), findsOneWidget);
      expect(find.byIcon(Icons.location_pin), findsOneWidget);
      expect(find.byType(fm.RichAttributionWidget), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('map tap reports the picked coordinate', (tester) async {
      MapLatLng? picked;
      await tester.pumpWidget(
        _wrap(
          SizedBox(
            width: 400,
            height: 400,
            child: VenueLocationMap(
              target: _osmTarget,
              onPicked: (p) => picked = p,
              tileProvider: FakeTileProvider(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(fm.FlutterMap));
      // flutter_map debounces single taps ~250ms to detect double-tap zoom.
      await tester.pump(const Duration(milliseconds: 300));

      expect(picked, isNotNull);
      expect(picked!.latitude, closeTo(13.7563, 0.5));
      expect(picked!.longitude, closeTo(100.5018, 0.5));
    });

    testWidgets('disabled target shows a placeholder, not a map', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const SizedBox(
            width: 400,
            height: 200,
            child: VenueLocationMap(target: _offTarget),
          ),
        ),
      );
      expect(find.byType(fm.FlutterMap), findsNothing);
      expect(find.byType(gm.GoogleMap), findsNothing);
      expect(find.textContaining('แผนที่ถูกปิด'), findsOneWidget);
    });
  });

  group('VenueLocationPicker', () {
    testWidgets('osm: tap → marker → confirm returns picked coordinate', (
      tester,
    ) async {
      MapLatLng? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await VenueLocationPicker.show(
                    context,
                    target: _osmTarget,
                    tileProvider: FakeTileProvider(),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // OSM renderer has no native zoom controls / puck — overlays stand in.
      expect(find.byKey(const ValueKey('picker_zoom_in')), findsOneWidget);
      expect(find.byKey(const ValueKey('picker_zoom_out')), findsOneWidget);
      // No my-location overlay without an injected location source.
      expect(find.byKey(const ValueKey('picker_my_location')), findsNothing);
      // No confirm button until a point is picked.
      expect(find.text('เลือกพิกัดนี้'), findsNothing);

      await tester.tap(find.byType(fm.FlutterMap));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.location_pin), findsOneWidget);

      await tester.tap(find.text('เลือกพิกัดนี้'));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.latitude, closeTo(13.7563, 0.5));
      expect(result!.longitude, closeTo(100.5018, 0.5));
      expect(tester.takeException(), isNull);
    });

    testWidgets('initial pin restores and confirm returns the same point', (
      tester,
    ) async {
      MapLatLng? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await VenueLocationPicker.show(
                    context,
                    target: _osmTarget,
                    initial: const MapLatLng(13.8, 100.6),
                    tileProvider: FakeTileProvider(),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('เลือกพิกัดนี้'), findsOneWidget);
      await tester.tap(find.text('เลือกพิกัดนี้'));
      await tester.pumpAndSettle();

      expect(result, const MapLatLng(13.8, 100.6));
    });

    testWidgets('close button dismisses without a result', (tester) async {
      var closed = false;
      MapLatLng? result = const MapLatLng(1, 1);
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await VenueLocationPicker.show(
                    context,
                    target: _osmTarget,
                    tileProvider: FakeTileProvider(),
                  );
                  closed = true;
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      expect(closed, isTrue);
      expect(result, isNull);
    });

    testWidgets('my-location overlay calls injected source and animates', (
      tester,
    ) async {
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => VenueLocationPicker.show(
                  context,
                  target: _osmTarget,
                  getUserLocation: () async {
                    calls++;
                    return const MapLatLng(13.7, 100.5);
                  },
                  tileProvider: FakeTileProvider(),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      final btn = find.byKey(const ValueKey('picker_my_location'));
      expect(btn, findsOneWidget);
      await tester.tap(btn);
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('google target keeps native controls (no overlays)', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => VenueLocationPicker.show(
                  context,
                  target: _googleTarget,
                  tileProvider: FakeTileProvider(),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.byType(gm.GoogleMap), findsOneWidget);
      expect(find.byKey(const ValueKey('picker_zoom_in')), findsNothing);
      expect(find.byKey(const ValueKey('picker_zoom_out')), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
