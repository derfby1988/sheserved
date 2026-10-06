import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Provider-agnostic map model shared by the Google and OSM adapters.
/// Screen code must never reference `google_maps_flutter` or `flutter_map`
/// types directly — conversion happens inside each adapter only.

@immutable
class MapLatLng {
  const MapLatLng(this.latitude, this.longitude);

  final double latitude;
  final double longitude;

  @override
  bool operator ==(Object other) =>
      other is MapLatLng &&
      other.latitude == latitude &&
      other.longitude == longitude;

  @override
  int get hashCode => Object.hash(latitude, longitude);

  @override
  String toString() => 'MapLatLng($latitude, $longitude)';
}

@immutable
class MapCameraPosition {
  const MapCameraPosition({
    required this.center,
    this.zoom = 14,
    this.bearing = 0,
    this.tilt = 0,
  });

  final MapLatLng center;
  final double zoom;
  final double bearing;
  final double tilt;

  static const bangkok = MapCameraPosition(
    center: MapLatLng(13.7563, 100.5018),
    zoom: 14,
  );
}

@immutable
class MapLatLngBounds {
  const MapLatLngBounds({required this.southwest, required this.northeast});

  /// Builds bounds covering all [points]. Returns null for an empty list.
  static MapLatLngBounds? fromPoints(List<MapLatLng> points) {
    if (points.isEmpty) return null;
    var minLat = points.first.latitude;
    var maxLat = minLat;
    var minLng = points.first.longitude;
    var maxLng = minLng;
    for (final p in points.skip(1)) {
      minLat = math.min(minLat, p.latitude);
      maxLat = math.max(maxLat, p.latitude);
      minLng = math.min(minLng, p.longitude);
      maxLng = math.max(maxLng, p.longitude);
    }
    return MapLatLngBounds(
      southwest: MapLatLng(minLat, minLng),
      northeast: MapLatLng(maxLat, maxLng),
    );
  }

  final MapLatLng southwest;
  final MapLatLng northeast;

  bool get isDegenerate =>
      southwest.latitude == northeast.latitude ||
      southwest.longitude == northeast.longitude;

  /// Google rejects bounds where south >= north or west >= east, and a
  /// zero-area bounds zooms to max level. Expand degenerate axes slightly.
  MapLatLngBounds normalized({double epsilon = 0.0005}) {
    var sw = southwest;
    var ne = northeast;
    if (sw.latitude == ne.latitude) {
      sw = MapLatLng(sw.latitude - epsilon, sw.longitude);
      ne = MapLatLng(ne.latitude + epsilon, ne.longitude);
    }
    if (sw.longitude == ne.longitude) {
      sw = MapLatLng(sw.latitude, sw.longitude - epsilon);
      ne = MapLatLng(ne.latitude, ne.longitude + epsilon);
    }
    return MapLatLngBounds(southwest: sw, northeast: ne);
  }

  MapLatLng get center => MapLatLng(
        (southwest.latitude + northeast.latitude) / 2,
        (southwest.longitude + northeast.longitude) / 2,
      );
}

/// Marker hue follows the Google convention (0–360). OSM adapters map the
/// same hue to a Material color, so callers keep one model for both
/// renderers. Set [markerWidget] when an OSM marker needs a custom widget —
/// Google cannot draw arbitrary widgets; the adapter falls back to [hue].
@immutable
class MapMarker {
  const MapMarker({
    required this.id,
    required this.position,
    this.hue = 210,
    this.label,
    this.onTap,
    this.markerWidget,
    this.consumeTapEvents = true,
  });

  final String id;
  final MapLatLng position;
  final double hue;
  final String? label;
  final VoidCallback? onTap;
  final Widget? markerWidget;
  final bool consumeTapEvents;
}

@immutable
class MapPolyline {
  const MapPolyline({
    required this.id,
    required this.points,
    this.color = Colors.red,
    this.width = 5,
    this.dashed = false,
  });

  final String id;
  final List<MapLatLng> points;
  final Color color;
  final double width;
  final bool dashed;
}

/// What a renderer can and cannot do. Screens must not assume Google-only
/// features exist — check capabilities before enabling UI that depends on
/// them (e.g. traffic toggle, my-location puck).
@immutable
class MapCapabilities {
  const MapCapabilities({
    required this.trafficLayer,
    required this.myLocationPuck,
    required this.zoomControls,
    required this.mapToolbar,
    required this.customMarkerWidgets,
  });

  final bool trafficLayer;
  final bool myLocationPuck;
  final bool zoomControls;
  final bool mapToolbar;
  final bool customMarkerWidgets;

  static const google = MapCapabilities(
    trafficLayer: true,
    myLocationPuck: true,
    zoomControls: true,
    mapToolbar: true,
    customMarkerWidgets: false,
  );

  static const osm = MapCapabilities(
    trafficLayer: false,
    myLocationPuck: false,
    zoomControls: false,
    mapToolbar: false,
    customMarkerWidgets: true,
  );
}
