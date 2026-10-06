import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:flutter_map_cancellable_tile_provider/flutter_map_cancellable_tile_provider.dart';
import 'package:latlong2/latlong.dart' as ll;

import '../../../features/admin/models/map_provider_config.dart' show TileSource;
import '../map_controller.dart';
import '../map_types.dart';

/// OSM tile usage policy requires an identifiable user agent.
const kOsmUserAgent = 'com.sheserved.app';

ll.LatLng toOsmLatLng(MapLatLng p) => ll.LatLng(p.latitude, p.longitude);

fm.LatLngBounds toOsmBounds(MapLatLngBounds b) => fm.LatLngBounds(
      toOsmLatLng(b.southwest),
      toOsmLatLng(b.northeast),
    );

Color hueToColor(double hue) =>
    HSVColor.fromAHSV(1, hue.clamp(0, 360), 0.85, 0.9).toColor();

class OsmMapAdapter extends StatefulWidget {
  const OsmMapAdapter({
    super.key,
    required this.tileSource,
    this.initialCamera = MapCameraPosition.bangkok,
    this.markers = const {},
    this.polylines = const {},
    this.onMapCreated,
    this.onTap,
    this.showUserLocation = false,
    this.userLocation,
    this.gesturesEnabled = true,
    this.tileProvider,
    this.retainTileCache = true,
  });

  final TileSource tileSource;
  final MapCameraPosition initialCamera;
  final Set<MapMarker> markers;
  final Set<MapPolyline> polylines;
  final ValueChanged<SheservedMapController>? onMapCreated;
  final ValueChanged<MapLatLng>? onTap;

  /// OSM has no native my-location puck — the screen supplies the position
  /// from Geolocator and we render a dot marker.
  final bool showUserLocation;
  final MapLatLng? userLocation;
  final bool gesturesEnabled;

  /// Injectable for tests/goldens (FakeTileProvider). Defaults to the
  /// cancellable network provider with the OSM-required user agent.
  final fm.TileProvider? tileProvider;
  final bool retainTileCache;

  @override
  State<OsmMapAdapter> createState() => _OsmMapAdapterState();
}

class _OsmMapAdapterState extends State<OsmMapAdapter> {
  late final fm.MapController _mapController;
  late final OsmAdapterController _facade;

  @override
  void initState() {
    super.initState();
    _mapController = fm.MapController();
    _facade = OsmAdapterController(_mapController);
  }

  @override
  void dispose() {
    _facade.dispose();
    _mapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return fm.FlutterMap(
      mapController: _mapController,
      options: fm.MapOptions(
        initialCenter: toOsmLatLng(widget.initialCamera.center),
        initialZoom: widget.initialCamera.zoom,
        initialRotation: widget.initialCamera.bearing,
        onMapReady: () => widget.onMapCreated?.call(_facade),
        onTap: widget.onTap == null
            ? null
            : (_, point) =>
                widget.onTap!(MapLatLng(point.latitude, point.longitude)),
        interactionOptions: fm.InteractionOptions(
          flags: widget.gesturesEnabled
              ? fm.InteractiveFlag.all
              : fm.InteractiveFlag.none,
        ),
      ),
      children: [
        fm.TileLayer(
          urlTemplate: widget.tileSource.urlTemplate,
          userAgentPackageName: kOsmUserAgent,
          tileProvider: widget.tileProvider ?? CancellableNetworkTileProvider(),
          keepBuffer: 4,
          panBuffer: 1,
        ),
        if (widget.polylines.isNotEmpty)
          fm.PolylineLayer(
            polylines: [
              for (final p in widget.polylines)
                fm.Polyline(
                  points: [for (final pt in p.points) toOsmLatLng(pt)],
                  color: p.color,
                  strokeWidth: p.width,
                  pattern: p.dashed
                      ? const fm.StrokePattern.dotted()
                      : const fm.StrokePattern.solid(),
                ),
            ],
          ),
        fm.MarkerLayer(
          markers: [
            if (widget.showUserLocation && widget.userLocation != null)
              fm.Marker(
                point: toOsmLatLng(widget.userLocation!),
                width: 24,
                height: 24,
                child: const _UserLocationDot(),
              ),
            for (final m in widget.markers)
              fm.Marker(
                point: toOsmLatLng(m.position),
                width: 40,
                height: 48,
                alignment: Alignment.topCenter,
                child: GestureDetector(
                  onTap: m.onTap,
                  child: m.markerWidget ??
                      _PinMarker(color: hueToColor(m.hue), label: m.label),
                ),
              ),
          ],
        ),
        fm.RichAttributionWidget(
          attributions: [
            fm.TextSourceAttribution(
              widget.tileSource.attribution,
              textStyle: const TextStyle(fontSize: 10),
            ),
          ],
        ),
      ],
    );
  }
}

class _UserLocationDot extends StatelessWidget {
  const _UserLocationDot();

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.blueAccent,
          border: Border.all(color: Colors.white, width: 3),
          boxShadow: const [
            BoxShadow(color: Colors.black26, blurRadius: 4),
          ],
        ),
      );
}

class _PinMarker extends StatelessWidget {
  const _PinMarker({required this.color, this.label});

  final Color color;
  final String? label;

  @override
  Widget build(BuildContext context) => Semantics(
        label: label,
        child: Icon(Icons.location_pin, color: color, size: 40),
      );
}

/// Wraps a flutter_map `MapController`. flutter_map has no explicit dispose
/// flag — we guard calls after [dispose] because screens can issue camera
/// commands from async callbacks racing teardown.
class OsmAdapterController implements SheservedMapController {
  OsmAdapterController(this._inner);

  final fm.MapController _inner;
  bool _disposed = false;

  @override
  bool get isDisposed => _disposed;

  @override
  void moveTo(MapLatLng target, {double? zoom}) {
    if (_disposed) return;
    _inner.move(toOsmLatLng(target), zoom ?? _inner.camera.zoom);
  }

  @override
  void animateTo(MapLatLng target, {double? zoom}) {
    // flutter_map has no built-in animated move; `move` is the same command.
    moveTo(target, zoom: zoom);
  }

  @override
  void fitToBounds(
    List<MapLatLng> points, {
    double padding = 64,
    double fallbackZoom = 15,
  }) {
    if (_disposed) return;
    final bounds = normalizedFitBounds(points);
    if (bounds == null) {
      if (points.isNotEmpty) {
        moveTo(points.first, zoom: fallbackZoom);
      }
      return;
    }
    _inner.fitCamera(
      fm.CameraFit.bounds(
        bounds: toOsmBounds(bounds),
        padding: EdgeInsets.all(padding),
      ),
    );
  }

  @override
  void dispose() => _disposed = true;
}
