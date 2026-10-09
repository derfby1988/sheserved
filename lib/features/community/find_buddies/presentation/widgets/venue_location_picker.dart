import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' as fm;

import '../../../../../../features/admin/models/map_provider_config.dart';
import '../../../../../../shared/map/map_controller.dart';
import '../../../../../../shared/map/map_types.dart';
import '../../../../../../shared/map/sheserved_map.dart';

/// Provider-agnostic venue map for the create-group form — Phase 3 of
/// docs/guides/map_provider_rollout_plan.md. Renders through [SheservedMap]
/// so the pin-pick flow is identical on Google and OSM renderers.
class VenueLocationMap extends StatelessWidget {
  const VenueLocationMap({
    super.key,
    required this.target,
    this.registry,
    this.picked,
    this.onPicked,
    this.onMapCreated,
    this.tileProvider,
  });

  /// Resolved config for (`MapFeature.groupCreate`, current platform).
  final MapTarget target;
  final TileSourceRegistry? registry;

  /// The pinned venue coordinate, or null when nothing is picked yet.
  final MapLatLng? picked;
  final ValueChanged<MapLatLng>? onPicked;
  final ValueChanged<SheservedMapController>? onMapCreated;

  /// Injectable for tests/goldens — ignored by the Google renderer.
  final fm.TileProvider? tileProvider;

  @override
  Widget build(BuildContext context) {
    return SheservedMap(
      target: target,
      registry: registry,
      initialCamera: MapCameraPosition(
        center: picked ?? MapCameraPosition.bangkok.center,
        zoom: picked != null ? 15 : 6,
      ),
      markers: {
        if (picked != null) MapMarker(id: 'venue', position: picked!, hue: 0),
      },
      onMapCreated: onMapCreated,
      onTap: onPicked,
      zoomControlsEnabled: false,
      mapToolbarEnabled: false,
      compassEnabled: false,
      tileProvider: tileProvider,
    );
  }
}

/// Fullscreen "เลือกตำแหน่งสนาม" picker. Returns the confirmed coordinate,
/// or null when dismissed without choosing.
///
/// [getUserLocation] powers the my-location overlay shown for renderers
/// without a native puck (OSM). It is injected so permission handling stays
/// with the caller and tests never touch Geolocator.
class VenueLocationPicker {
  static Future<MapLatLng?> show(
    BuildContext context, {
    required MapTarget target,
    TileSourceRegistry? registry,
    MapLatLng? initial,
    Future<MapLatLng?> Function()? getUserLocation,
    fm.TileProvider? tileProvider,
  }) {
    final capabilities = SheservedMap.capabilitiesFor(target.renderer);
    SheservedMapController? controller;
    MapLatLng? picked = initial;
    MapLatLng? userLocation;

    return showGeneralDialog<MapLatLng>(
      context: context,
      barrierDismissible: false,
      pageBuilder: (ctx, anim1, anim2) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Scaffold(
              appBar: AppBar(
                title: const Text('เลือกตำแหน่งสนาม'),
                leading: IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: 'ปิด',
                  onPressed: () => Navigator.of(ctx).pop(),
                ),
              ),
              body: Stack(
                children: [
                  SheservedMap(
                    key: const ValueKey('venue_picker_fullscreen_map'),
                    target: target,
                    registry: registry,
                    initialCamera: MapCameraPosition(
                      center: initial ?? MapCameraPosition.bangkok.center,
                      zoom: initial != null ? 17 : 13,
                    ),
                    markers: {
                      if (picked != null)
                        MapMarker(id: 'picked', position: picked!, hue: 0),
                    },
                    onMapCreated: (c) => controller = c,
                    onTap: (pos) => setSheetState(() => picked = pos),
                    showUserLocation:
                        capabilities.myLocationPuck || userLocation != null,
                    showMyLocationButton: capabilities.myLocationPuck,
                    zoomControlsEnabled: capabilities.zoomControls,
                    mapToolbarEnabled: false,
                    userLocation: userLocation,
                    tileProvider: tileProvider,
                  ),
                  if (!capabilities.myLocationPuck ||
                      !capabilities.zoomControls)
                    Positioned(
                      right: 12,
                      bottom: 90,
                      child: Column(
                        children: [
                          if (!capabilities.myLocationPuck &&
                              getUserLocation != null)
                            _PickerOverlayButton(
                              key: const ValueKey('picker_my_location'),
                              icon: Icons.my_location,
                              tooltip: 'ใช้ตำแหน่งฉัน',
                              onPressed: () async {
                                final p = await getUserLocation();
                                if (p == null) return;
                                setSheetState(() => userLocation = p);
                                controller?.animateTo(p, zoom: 16);
                              },
                            ),
                          if (!capabilities.zoomControls) ...[
                            const SizedBox(height: 8),
                            _PickerOverlayButton(
                              key: const ValueKey('picker_zoom_in'),
                              icon: Icons.add,
                              tooltip: 'ซูมเข้า',
                              onPressed: () => controller?.zoomBy(1),
                            ),
                            const SizedBox(height: 8),
                            _PickerOverlayButton(
                              key: const ValueKey('picker_zoom_out'),
                              icon: Icons.remove,
                              tooltip: 'ซูมออก',
                              onPressed: () => controller?.zoomBy(-1),
                            ),
                          ],
                        ],
                      ),
                    ),
                ],
              ),
              floatingActionButton: picked != null
                  ? FloatingActionButton.extended(
                      onPressed: () => Navigator.of(ctx).pop(picked),
                      icon: const Icon(Icons.check),
                      label: const Text('เลือกพิกัดนี้'),
                    )
                  : null,
            );
          },
        );
      },
    );
  }
}

class _PickerOverlayButton extends StatelessWidget {
  const _PickerOverlayButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final button = Material(
      color: Colors.white,
      shape: const CircleBorder(),
      elevation: 3,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(icon, size: 20, semanticLabel: tooltip),
        ),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}
