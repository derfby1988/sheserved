// Scratch harness for Phase 0 (map_provider_rollout_plan.md §10.2 Phase 0).
// Low-volume smoke test of keyless candidate tile sources on device + web/Caddy.
// NOT part of the app — run with:
//   flutter run -t tool/osm_tile_smoke/main.dart -d <device>
//   flutter build web -t tool/osm_tile_smoke/main.dart -o build/osm_smoke
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_cancellable_tile_provider/flutter_map_cancellable_tile_provider.dart';
import 'package:latlong2/latlong.dart';

void main() => runApp(const TileSmokeApp());

class TileSource {
  const TileSource(this.id, this.label, this.urlTemplate, this.attribution);

  final String id;
  final String label;
  final String urlTemplate;
  final String attribution;
}

// Keyless candidates only — sources that need an API key/signup are evaluated
// in the Phase 0 decision record, not hardcoded here.
const _sources = [
  TileSource(
    'osm_standard',
    'OSM Standard',
    'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
    '© OpenStreetMap contributors',
  ),
  TileSource(
    'carto_light',
    'CARTO Light',
    'https://basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png',
    '© OpenStreetMap contributors © CARTO',
  ),
  TileSource(
    'carto_voyager',
    'CARTO Voyager',
    'https://basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png',
    '© OpenStreetMap contributors © CARTO',
  ),
  TileSource(
    'opentopo',
    'OpenTopoMap',
    'https://a.tile.opentopomap.org/{z}/{x}/{y}.png',
    '© OpenStreetMap contributors, SRTM | style: © OpenTopoMap (CC-BY-SA)',
  ),
];

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

  @override
  Widget build(BuildContext context) {
    final source = _sources[_index];
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        appBar: AppBar(title: Text('Tile smoke: ${source.label}')),
        body: Column(
          children: [
            Expanded(
              child: FlutterMap(
                options: const MapOptions(
                  initialCenter: LatLng(13.7563, 100.5018), // Bangkok
                  initialZoom: 12,
                ),
                children: [
                  TileLayer(
                    key: ValueKey(source.id),
                    urlTemplate: source.urlTemplate,
                    userAgentPackageName: 'com.sheserved.mapsmoke',
                    tileProvider: CancellableNetworkTileProvider(),
                  ),
                  RichAttributionWidget(
                    attributions: [
                      TextSourceAttribution(source.attribution),
                    ],
                  ),
                ],
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
