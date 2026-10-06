import 'package:flutter/material.dart';

import '../../features/admin/models/map_provider_config.dart';
import 'adapters/google_adapter.dart';
import 'adapters/osm_adapter.dart';
import 'map_controller.dart';
import 'map_types.dart';

/// Provider-agnostic map widget. Give it the resolved [MapTarget] (from
/// `MapProviderConfig.resolveTarget`) and it picks the renderer. It never
/// silently falls back to another provider — a missing/disabled target
/// renders an explicit placeholder so the failure is visible and testable.
class SheservedMap extends StatelessWidget {
  const SheservedMap({
    super.key,
    required this.target,
    this.registry,
    this.initialCamera = MapCameraPosition.bangkok,
    this.markers = const {},
    this.polylines = const {},
    this.onMapCreated,
    this.onTap,
    this.showUserLocation = false,
    this.showMyLocationButton = false,
    this.userLocation,
    this.trafficEnabled = false,
    this.padding = EdgeInsets.zero,
    this.gesturesEnabled = true,
    this.zoomControlsEnabled = false,
    this.mapToolbarEnabled = false,
    this.tileProvider,
    this.unavailableBuilder,
  });

  /// Resolved config for this (feature, platform) — enabled flag + renderer
  /// + tile source id, already passed through override → platform → env
  /// resolution.
  final MapTarget target;

  /// Tile source catalog — defaults to the embedded registry; screens that
  /// loaded the server config should pass `config.registry` so server-side
  /// additions are honored.
  final TileSourceRegistry? registry;

  final MapCameraPosition initialCamera;
  final Set<MapMarker> markers;
  final Set<MapPolyline> polylines;
  final ValueChanged<SheservedMapController>? onMapCreated;
  final ValueChanged<MapLatLng>? onTap;

  final bool showUserLocation;
  final bool showMyLocationButton;
  final MapLatLng? userLocation;
  final bool trafficEnabled;
  final EdgeInsets padding;
  final bool gesturesEnabled;
  final bool zoomControlsEnabled;
  final bool mapToolbarEnabled;

  /// Injectable tile provider for OSM tests/goldens. Ignored by Google.
  final dynamic tileProvider;

  /// Custom placeholder when the map is disabled or misconfigured.
  final Widget Function(String reason)? unavailableBuilder;

  /// Renderer capabilities for the resolved target — lets callers hide
  /// Google-only UI (traffic toggle, my-location button) on OSM.
  MapCapabilities get capabilities => switch (target.renderer) {
        MapRendererKind.google => MapCapabilities.google,
        MapRendererKind.osm => MapCapabilities.osm,
      };

  @override
  Widget build(BuildContext context) {
    if (!target.enabled) {
      return _unavailable('แผนที่ถูกปิดสำหรับแพลตฟอร์มนี้');
    }
    return switch (target.renderer) {
      MapRendererKind.google => GoogleMapAdapter(
          initialCamera: initialCamera,
          markers: markers,
          polylines: polylines,
          onMapCreated: onMapCreated,
          onTap: onTap,
          showUserLocation: showUserLocation,
          showMyLocationButton: showMyLocationButton,
          zoomControlsEnabled: zoomControlsEnabled,
          mapToolbarEnabled: mapToolbarEnabled,
          trafficEnabled: trafficEnabled,
          padding: padding,
          gesturesEnabled: gesturesEnabled,
        ),
      MapRendererKind.osm => _buildOsm(),
    };
  }

  Widget _buildOsm() {
    final source =
        (registry ?? TileSourceRegistry.defaults())[target.tileSourceId];
    if (source == null) {
      // No silent fallback — missing tile source must be visible (§ invariant).
      return _unavailable('ไม่พบ tile source \'${target.tileSourceId}\'');
    }
    return OsmMapAdapter(
      tileSource: source,
      initialCamera: initialCamera,
      markers: markers,
      polylines: polylines,
      onMapCreated: onMapCreated,
      onTap: onTap,
      showUserLocation: showUserLocation,
      userLocation: userLocation,
      gesturesEnabled: gesturesEnabled,
      tileProvider: tileProvider,
    );
  }

  Widget _unavailable(String reason) =>
      unavailableBuilder?.call(reason) ??
      Container(
        color: Colors.grey.shade200,
        alignment: Alignment.center,
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.map_outlined, color: Colors.grey.shade500, size: 32),
            const SizedBox(height: 8),
            Text(
              reason,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
            ),
          ],
        ),
      );
}
