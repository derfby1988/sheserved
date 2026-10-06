// Scratch harness for Phase 0→2 (map_provider_rollout_plan.md §10.2).
// Smoke-tests the PRODUCTION shared map adapter (lib/shared/map/) with real
// tile sources on device + web/Caddy — NOT a copy of adapter code.
// NOT part of the app — run with:
//   flutter run -t tool/osm_tile_smoke/main.dart -d <device>
//   flutter build web -t tool/osm_tile_smoke/main.dart -o build/osm_smoke
import 'package:flutter/material.dart';
import 'package:sheserved/features/admin/models/map_provider_config.dart';
import 'package:sheserved/shared/map/map_controller.dart';
import 'package:sheserved/shared/map/map_types.dart';
import 'package:sheserved/shared/map/sheserved_map.dart';

void main() => runApp(const TileSmokeApp());

// Candidate tile sources — resolved through the production registry so the
// smoke exercises the same catalog the app config uses.
final _registry = TileSourceRegistry.defaults();
final _sources = _registry.sources.values.toList();

class TileSmokeApp extends StatefulWidget {
  const TileSmokeApp({super.key});

  @override
  State<TileSmokeApp> createState() => _TileSmokeAppState();
}

class _TileSmokeAppState extends State<TileSmokeApp> {
  // ?src=<id> lets headless browser runs select the source without taps.
  int _index = (() {
    final src = Uri.base.queryParameters['src'];
    final i = _sources.indexWhere((s) => s.id == src);
    return i < 0 ? 0 : i;
  })();

  SheservedMapController? _map;

  static const _incident = MapLatLng(13.7600, 100.5100);
  static const _user = MapLatLng(13.7520, 100.4940);
  static const _markers = {
    MapMarker(id: 'incident', position: _incident, hue: 0, label: 'เหตุ'),
    MapMarker(id: 'user', position: _user, hue: 210, label: 'เรา'),
  };
  static const _polylines = {
    MapPolyline(id: 'route', points: [_user, _incident], color: Colors.red),
  };

  @override
  Widget build(BuildContext context) {
    final source = _sources[_index];
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        appBar: AppBar(
          title: Text('Adapter smoke: ${source.label}'),
          actions: [
            IconButton(
              tooltip: 'fitToBounds (facade)',
              icon: const Icon(Icons.fit_screen),
              onPressed: () => _map?.fitToBounds(
                const [_incident, _user],
                padding: 60,
              ),
            ),
            IconButton(
              tooltip: 'animateTo (facade)',
              icon: const Icon(Icons.my_location),
              onPressed: () => _map?.animateTo(_user, zoom: 15),
            ),
          ],
        ),
        body: Column(
          children: [
            Expanded(
              child: SheservedMap(
                key: ValueKey(source.id),
                target: MapTarget(
                  enabled: true,
                  renderer: MapRendererKind.osm,
                  tileSourceId: source.id,
                ),
                registry: _registry,
                initialCamera: const MapCameraPosition(
                  center: MapLatLng(13.7563, 100.5018),
                  zoom: 12,
                ),
                markers: _markers,
                polylines: _polylines,
                onMapCreated: (c) => _map = c,
                onTap: (p) => debugPrint('map tap: $p'),
              ),
            ),
            SafeArea(
              top: false,
              child: Wrap(
                spacing: 8,
                children: [
                  for (var i = 0; i < _sources.length; i++)
                    ChoiceChip(
                      label: Text(_sources[i].label),
                      selected: _index == i,
                      onSelected: (_) => setState(() => _index = i),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
