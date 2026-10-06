import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gm;

import '../map_controller.dart';
import '../map_types.dart';

/// Conversion between shared model and google_maps_flutter types lives here —
/// nowhere else. Exported top-level so unit tests cover it without a
/// platform view.
gm.LatLng toGoogleLatLng(MapLatLng p) => gm.LatLng(p.latitude, p.longitude);

gm.CameraPosition toGoogleCameraPosition(MapCameraPosition c) =>
    gm.CameraPosition(
      target: toGoogleLatLng(c.center),
      zoom: c.zoom,
      bearing: c.bearing,
      tilt: c.tilt,
    );

gm.LatLngBounds toGoogleBounds(MapLatLngBounds b) => gm.LatLngBounds(
      southwest: toGoogleLatLng(b.southwest),
      northeast: toGoogleLatLng(b.northeast),
    );

gm.Marker toGoogleMarker(MapMarker m) => gm.Marker(
      markerId: gm.MarkerId(m.id),
      position: toGoogleLatLng(m.position),
      icon: gm.BitmapDescriptor.defaultMarkerWithHue(m.hue),
      infoWindow: m.label != null ? gm.InfoWindow(title: m.label) : gm.InfoWindow.noText,
      onTap: m.onTap,
      consumeTapEvents: m.consumeTapEvents,
    );

gm.Polyline toGooglePolyline(MapPolyline p) => gm.Polyline(
      polylineId: gm.PolylineId(p.id),
      points: [for (final pt in p.points) toGoogleLatLng(pt)],
      color: p.color,
      width: p.width.round(),
      jointType: gm.JointType.round,
      startCap: gm.Cap.roundCap,
      endCap: gm.Cap.roundCap,
      patterns: p.dashed ? [gm.PatternItem.dash(20), gm.PatternItem.gap(10)] : const [],
    );

class GoogleMapAdapter extends StatefulWidget {
  const GoogleMapAdapter({
    super.key,
    this.initialCamera = MapCameraPosition.bangkok,
    this.markers = const {},
    this.polylines = const {},
    this.onMapCreated,
    this.onTap,
    this.showUserLocation = false,
    this.showMyLocationButton = false,
    this.zoomControlsEnabled = false,
    this.mapToolbarEnabled = false,
    this.trafficEnabled = false,
    this.padding = EdgeInsets.zero,
    this.gesturesEnabled = true,
  });

  final MapCameraPosition initialCamera;
  final Set<MapMarker> markers;
  final Set<MapPolyline> polylines;
  final ValueChanged<SheservedMapController>? onMapCreated;
  final ValueChanged<MapLatLng>? onTap;
  final bool showUserLocation;
  final bool showMyLocationButton;
  final bool zoomControlsEnabled;
  final bool mapToolbarEnabled;
  final bool trafficEnabled;
  final EdgeInsets padding;
  final bool gesturesEnabled;

  @override
  State<GoogleMapAdapter> createState() => _GoogleMapAdapterState();
}

class _GoogleMapAdapterState extends State<GoogleMapAdapter> {
  GoogleAdapterController? _facade;

  @override
  void dispose() {
    _facade?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return gm.GoogleMap(
      initialCameraPosition: toGoogleCameraPosition(widget.initialCamera),
      markers: {for (final m in widget.markers) toGoogleMarker(m)},
      polylines: {for (final p in widget.polylines) toGooglePolyline(p)},
      onMapCreated: (c) {
        final facade = GoogleAdapterController(c);
        _facade = facade;
        widget.onMapCreated?.call(facade);
      },
      onTap: widget.onTap == null
          ? null
          : (p) => widget.onTap!(MapLatLng(p.latitude, p.longitude)),
      myLocationEnabled: widget.showUserLocation,
      myLocationButtonEnabled: widget.showMyLocationButton,
      zoomControlsEnabled: widget.zoomControlsEnabled,
      mapToolbarEnabled: widget.mapToolbarEnabled,
      trafficEnabled: widget.trafficEnabled,
      padding: widget.padding,
      zoomGesturesEnabled: widget.gesturesEnabled,
      scrollGesturesEnabled: widget.gesturesEnabled,
      rotateGesturesEnabled: widget.gesturesEnabled,
      tiltGesturesEnabled: widget.gesturesEnabled,
    );
  }
}

/// Wraps a `GoogleMapController`. Commands after [dispose] are no-ops —
/// `GoogleMapController.dispose` is idempotent-safe to call once; we guard
/// anyway because screens may issue camera commands from async callbacks
/// racing teardown.
class GoogleAdapterController implements SheservedMapController {
  GoogleAdapterController(this._inner);

  final gm.GoogleMapController _inner;
  bool _disposed = false;

  @override
  bool get isDisposed => _disposed;

  @override
  void moveTo(MapLatLng target, {double? zoom}) {
    if (_disposed) return;
    final update = zoom == null
        ? gm.CameraUpdate.newLatLng(toGoogleLatLng(target))
        : gm.CameraUpdate.newLatLngZoom(toGoogleLatLng(target), zoom);
    _inner.moveCamera(update);
  }

  @override
  void animateTo(MapLatLng target, {double? zoom}) {
    if (_disposed) return;
    final update = zoom == null
        ? gm.CameraUpdate.newLatLng(toGoogleLatLng(target))
        : gm.CameraUpdate.newLatLngZoom(toGoogleLatLng(target), zoom);
    _inner.animateCamera(update);
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
        animateTo(points.first, zoom: fallbackZoom);
      }
      return;
    }
    _inner.animateCamera(
      gm.CameraUpdate.newLatLngBounds(toGoogleBounds(bounds), padding),
    );
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _inner.dispose();
  }
}
