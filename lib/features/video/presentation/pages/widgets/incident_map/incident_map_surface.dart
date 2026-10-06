import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:latlong2/latlong.dart' as ll;

import '../../../../../../services/map_config_service.dart';
import '../../../../../../shared/widgets/glass/glass_primitives.dart';
import '../../../../models/incident_map_models.dart';
import '../../../../../admin/models/map_provider_config.dart';
import 'incident_map_photo_layout.dart';

export 'incident_map_photo_layout.dart'
    show IncidentPhotoCardPlacement, layoutIncidentPhotoCards;

/// Zoom ที่เริ่มแสดงภาพตัวอย่างจาก gallery (§22.5)
const double kIncidentMapPhotoZoomThreshold = 13;

/// Cluster icon grows with the incident count.
Size _clusterIconSize(int count) {
  if (count < 10) return const Size(48, 48);
  if (count < 100) return const Size(56, 56);
  return const Size(64, 64);
}

/// Resolved provider target for the incident overview map (§22.5) —
/// produced by [MapConfigService] + `resolveTarget(MapFeature.emergency, …)`.
class IncidentMapAvailability {
  final bool enabled;
  final MapRendererKind renderer;
  final TileSource? tileSource;

  /// True when the server could not be reached and the embedded default is in
  /// use — the UI must surface this, never fake a saved state (§4.9).
  final bool isAppDefault;

  const IncidentMapAvailability({
    required this.enabled,
    required this.renderer,
    this.tileSource,
    this.isAppDefault = false,
  });
}

/// Camera snapshot shared by both renderers (§22.5: same domain state).
class IncidentMapCameraState {
  final double zoom;
  final IncidentMapBounds bounds;

  /// lat/lng → screen px inside the map viewport (null until known).
  final Offset Function(double lat, double lng)? projector;

  const IncidentMapCameraState({
    required this.zoom,
    required this.bounds,
    this.projector,
  });
}

/// The incident overview map surface — one widget, two renderers
/// (google_maps_flutter / flutter_map) fed by the same domain data
/// (§22.5 single-surface rule).
class IncidentMapSurface extends StatefulWidget {
  final IncidentMapAvailability availability;
  final IncidentMapBounds initialBounds;
  final List<IncidentMapItem> items;

  /// Legend chip highlight — dim markers outside this bucket (§22.3.4).
  final IncidentAgeBucket? highlightedBucket;

  final void Function(IncidentMapPointItem point)? onPointTap;
  final void Function(IncidentMapPointItem point, IncidentMapPhoto photo)?
  onPhotoTap;

  /// Debounced camera-settled callback for viewport fetches (§22.4.3).
  final void Function(double zoom, IncidentMapBounds bounds)? onCameraSettled;

  const IncidentMapSurface({
    super.key,
    required this.availability,
    required this.initialBounds,
    required this.items,
    this.highlightedBucket,
    this.onPointTap,
    this.onPhotoTap,
    this.onCameraSettled,
  });

  @override
  State<IncidentMapSurface> createState() => _IncidentMapSurfaceState();
}

class _IncidentMapSurfaceState extends State<IncidentMapSurface> {
  GoogleMapController? _googleController;
  fm.MapController? _osmController;
  IncidentMapCameraState? _camera;
  Timer? _settleDebounce;
  bool _didInitialFit = false;
  Set<Marker> _googleMarkers = {};

  @override
  void initState() {
    super.initState();
    _osmController = fm.MapController();
    _scheduleGoogleMarkers();
  }

  @override
  void didUpdateWidget(covariant IncidentMapSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.items, widget.items) ||
        oldWidget.highlightedBucket != widget.highlightedBucket) {
      _scheduleGoogleMarkers();
    }
  }

  @override
  void dispose() {
    _settleDebounce?.cancel();
    super.dispose();
  }

  double get _centerLat =>
      (widget.initialBounds.south + widget.initialBounds.north) / 2;
  double get _centerLng =>
      (widget.initialBounds.west + widget.initialBounds.east) / 2;

  // ──────────────────────────────────────────────────────────────
  // Camera sync (both renderers → one domain state)
  // ──────────────────────────────────────────────────────────────

  void _commitCamera(IncidentMapCameraState camera) {
    if (!mounted) return;
    setState(() => _camera = camera);
    _settleDebounce?.cancel();
    _settleDebounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) {
        widget.onCameraSettled?.call(camera.zoom, camera.bounds);
      }
    });
  }

  Future<void> _syncGoogleCamera() async {
    final controller = _googleController;
    final box = context.findRenderObject() as RenderBox?;
    if (controller == null || box == null || !mounted) return;
    try {
      final zoom = await controller.getZoomLevel();
      final region = await controller.getVisibleRegion();
      final sw = region.southwest;
      final ne = region.northeast;
      final bounds = IncidentMapBounds(
        south: math.min(sw.latitude, ne.latitude),
        west: math.min(sw.longitude, ne.longitude),
        north: math.max(sw.latitude, ne.latitude),
        east: math.max(sw.longitude, ne.longitude),
      );
      final size = box.size;
      _commitCamera(
        IncidentMapCameraState(
          zoom: zoom,
          bounds: bounds,
          projector: (lat, lng) => _mercatorProject(
            lat: lat,
            lng: lng,
            swLat: bounds.south,
            swLng: bounds.west,
            neLat: bounds.north,
            neLng: bounds.east,
            size: size,
          ),
        ),
      );
    } catch (_) {
      // Controller may be disposed mid-flight — ignore.
    }
  }

  void _syncOsmCamera() {
    final controller = _osmController;
    if (controller == null || !mounted) return;
    final cam = controller.camera;
    final vb = cam.visibleBounds;
    final bounds = IncidentMapBounds(
      south: vb.south,
      west: vb.west,
      north: vb.north,
      east: vb.east,
    );
    _commitCamera(
      IncidentMapCameraState(
        zoom: cam.zoom,
        bounds: bounds,
        projector: (lat, lng) => cam.projectAtZoom(ll.LatLng(lat, lng)),
      ),
    );
  }

  /// Web-Mercator projection from the visible region — exact for Google Maps
  /// as long as the viewport does not cross the antimeridian (Thailand never
  /// does; the server rejects wrapped bounds anyway).
  static Offset _mercatorProject({
    required double lat,
    required double lng,
    required double swLat,
    required double swLng,
    required double neLat,
    required double neLng,
    required Size size,
  }) {
    double mercY(double latitude) =>
        (1 -
            math.log(math.tan(math.pi / 4 + latitude * math.pi / 360)) /
                math.pi) /
        2;
    final x = (lng - swLng) / (neLng - swLng) * size.width;
    final yTop = mercY(neLat);
    final yBottom = mercY(swLat);
    final y = (mercY(lat) - yTop) / (yBottom - yTop) * size.height;
    return Offset(x, y);
  }

  // ──────────────────────────────────────────────────────────────
  // Dimming (legend highlight)
  // ──────────────────────────────────────────────────────────────

  bool _isDimmedPoint(IncidentMapPointItem p) =>
      widget.highlightedBucket != null && p.bucket != widget.highlightedBucket;

  bool _isDimmedCluster(IncidentMapClusterItem c) =>
      widget.highlightedBucket != null &&
      (c.byBucket[widget.highlightedBucket!] ?? 0) == 0;

  // ──────────────────────────────────────────────────────────────
  // Google renderer
  // ──────────────────────────────────────────────────────────────

  static final Map<String, BitmapDescriptor> _iconCache = {};

  Future<void> _fitInitialGoogleBounds() async {
    if (_didInitialFit) return;
    _didInitialFit = true;
    final controller = _googleController;
    if (controller == null) return;
    await controller.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(
            widget.initialBounds.south,
            widget.initialBounds.west,
          ),
          northeast: LatLng(
            widget.initialBounds.north,
            widget.initialBounds.east,
          ),
        ),
        16,
      ),
    );
  }

  void _zoomToCluster(IncidentMapClusterItem cluster) {
    final targetZoom = IncidentMapZoomPolicy.zoomAfterClusterTap(
      _camera?.zoom ?? 5.5,
    );
    final bounds = cluster.gridBounds;
    final currentBounds = _camera?.bounds;
    final canFitBounds = currentBounds != null &&
        bounds.north > bounds.south &&
        bounds.east > bounds.west &&
        bounds.north - bounds.south < currentBounds.north - currentBounds.south &&
        bounds.east - bounds.west < currentBounds.east - currentBounds.west;

    if (widget.availability.renderer == MapRendererKind.osm) {
      final controller = _osmController;
      if (controller == null) return;
      if (canFitBounds) {
        try {
          controller.fitCamera(
            fm.CameraFit.bounds(
              bounds: fm.LatLngBounds(
                ll.LatLng(bounds.south, bounds.west),
                ll.LatLng(bounds.north, bounds.east),
              ),
              padding: const EdgeInsets.all(48),
            ),
          );
          return;
        } catch (_) {}
      }
      controller.move(ll.LatLng(cluster.lat, cluster.lng), targetZoom);
      return;
    }

    final controller = _googleController;
    if (controller == null) return;
    final cameraUpdate = canFitBounds
        ? CameraUpdate.newLatLngBounds(
            LatLngBounds(
              southwest: LatLng(bounds.south, bounds.west),
              northeast: LatLng(bounds.north, bounds.east),
            ),
            48,
          )
        : CameraUpdate.newCameraPosition(
            CameraPosition(
              target: LatLng(cluster.lat, cluster.lng),
              zoom: targetZoom,
            ),
          );
    unawaited(
      controller.animateCamera(cameraUpdate).catchError((_) {}),
    );
  }

  Future<BitmapDescriptor?> _googleIconFor(IncidentMapItem item) async {
    final String key;
    if (item is IncidentMapClusterItem) {
      key =
          'cluster:${item.count}:'
          '${item.byBucket.entries.where((e) => e.value > 0).map((e) => '${e.key.name}${e.value}').join(',')}:'
          '${_isDimmedCluster(item)}';
    } else if (item is IncidentMapPointItem) {
      key = 'point:${item.bucket.name}:${_isDimmedPoint(item)}';
    } else {
      return null;
    }
    final cached = _iconCache[key];
    if (cached != null) return cached;

    final size = item is IncidentMapClusterItem
        ? _clusterIconSize(item.count)
        : const Size(44, 44);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    if (item is IncidentMapClusterItem) {
      _ClusterDonutPainter(
        byBucket: item.byBucket,
        count: item.count,
        dimmed: _isDimmedCluster(item),
      ).paint(canvas, size);
    } else if (item is IncidentMapPointItem) {
      _PointMarkerPainter(
        color: item.bucket.color,
        dimmed: _isDimmedPoint(item),
      ).paint(canvas, size);
    }
    final picture = recorder.endRecording();
    final image = await picture.toImage(
      size.width.toInt(),
      size.height.toInt(),
    );
    picture.dispose();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (bytes == null) return null;
    final descriptor = BitmapDescriptor.bytes(
      bytes.buffer.asUint8List(),
      width: size.width,
      height: size.height,
    );
    _iconCache[key] = descriptor;
    return descriptor;
  }

  void _scheduleGoogleMarkers() {
    _buildGoogleMarkers().then((markers) {
      if (mounted) setState(() => _googleMarkers = markers);
    });
  }

  Future<Set<Marker>> _buildGoogleMarkers() async {
    final markers = <Marker>{};
    for (final item in widget.items) {
      final icon = await _googleIconFor(item);
      if (icon == null) continue;
      final markerId = item is IncidentMapPointItem
          ? MarkerId('point_${item.id}')
          : MarkerId('cluster_${item.lat}_${item.lng}');
      markers.add(
        Marker(
          markerId: markerId,
          position: LatLng(item.lat, item.lng),
          icon: icon,
          consumeTapEvents: true,
          onTap: () {
            if (item is IncidentMapPointItem) {
              widget.onPointTap?.call(item);
            } else if (item is IncidentMapClusterItem) {
              _zoomToCluster(item);
            }
          },
        ),
      );
    }
    return markers;
  }

  Widget _buildGoogleMap() {
    return GoogleMap(
      initialCameraPosition: CameraPosition(
        target: LatLng(_centerLat, _centerLng),
        zoom: 5.5,
      ),
      onMapCreated: (controller) {
        _googleController = controller;
        _fitInitialGoogleBounds();
      },
      onCameraIdle: _syncGoogleCamera,
      markers: _googleMarkers,
      myLocationEnabled: false,
      myLocationButtonEnabled: false,
      zoomControlsEnabled: false,
      mapToolbarEnabled: false,
      compassEnabled: false,
      trafficEnabled: false,
      buildingsEnabled: false,
      indoorViewEnabled: false,
      mapType: MapType.normal,
    );
  }

  // ──────────────────────────────────────────────────────────────
  // OSM renderer
  // ──────────────────────────────────────────────────────────────

  Widget _buildOsmMap(TileSource source) {
    return fm.FlutterMap(
      mapController: _osmController,
      options: fm.MapOptions(
        initialCameraFit: fm.CameraFit.bounds(
          bounds: fm.LatLngBounds(
            ll.LatLng(widget.initialBounds.south, widget.initialBounds.west),
            ll.LatLng(widget.initialBounds.north, widget.initialBounds.east),
          ),
          padding: const EdgeInsets.all(16),
        ),
        onPositionChanged: (_, _) => _syncOsmCamera(),
      ),
      children: [
        fm.TileLayer(
          urlTemplate: source.urlTemplate,
          userAgentPackageName: 'com.sheserved.app',
        ),
        fm.MarkerLayer(
          markers: [
            for (final item in widget.items)
              fm.Marker(
                point: ll.LatLng(item.lat, item.lng),
                width: item is IncidentMapClusterItem
                    ? _clusterIconSize(item.count).width
                    : 44,
                height: item is IncidentMapClusterItem
                    ? _clusterIconSize(item.count).height
                    : 44,
                child: switch (item) {
                  final IncidentMapClusterItem cluster => _OsmClusterMarker(
                    cluster: cluster,
                    dimmed: _isDimmedCluster(cluster),
                    onTap: () => _zoomToCluster(cluster),
                  ),
                  final IncidentMapPointItem point => _OsmPointMarker(
                    point: point,
                    dimmed: _isDimmedPoint(point),
                    onTap: () => widget.onPointTap?.call(point),
                  ),
                },
              ),
          ],
        ),
        fm.RichAttributionWidget(
          attributions: [fm.TextSourceAttribution(source.attribution)],
        ),
      ],
    );
  }

  // ──────────────────────────────────────────────────────────────
  // Gallery photo overlay (§22.5)
  // ──────────────────────────────────────────────────────────────

  List<IncidentPhotoCardPlacement> _photoPlacements(Size viewport) {
    final camera = _camera;
    final projector = camera?.projector;
    if (projector == null || camera == null) return const [];
    if (camera.zoom < kIncidentMapPhotoZoomThreshold) return const [];
    final anchors = <String, Offset>{};
    final photos = <String, List<IncidentMapPhoto>>{};
    for (final item in widget.items) {
      if (item is! IncidentMapPointItem) continue;
      if (item.photos.isEmpty) continue;
      final anchor = projector(item.lat, item.lng);
      if (anchor.dx < -80 ||
          anchor.dy < -80 ||
          anchor.dx > viewport.width + 80 ||
          anchor.dy > viewport.height + 80) {
        continue;
      }
      anchors[item.id] = anchor;
      photos[item.id] = item.photos;
    }
    if (anchors.isEmpty) return const [];
    return layoutIncidentPhotoCards(
      anchorByIncidentId: anchors,
      photosByIncidentId: photos,
      viewport: viewport,
    );
  }

  Widget _buildPhotoOverlay(Size viewport) {
    final placements = _photoPlacements(viewport);
    if (placements.isEmpty) return const SizedBox.shrink();
    final pointsById = {
      for (final item in widget.items)
        if (item is IncidentMapPointItem) item.id: item,
    };
    return Stack(
      children: [
        for (final placement in placements)
          Positioned(
            left: placement.topLeft.dx,
            top: placement.topLeft.dy,
            width: placement.size.width,
            height: placement.size.height,
            child: _PhotoCard(
              photo: placement.photo,
              onTap: () {
                final point = pointsById[placement.incidentId];
                if (point != null)
                  widget.onPhotoTap?.call(point, placement.photo);
              },
            ),
          ),
      ],
    );
  }

  // ──────────────────────────────────────────────────────────────
  // Build
  // ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport = Size(
          constraints.maxWidth.isFinite ? constraints.maxWidth : 400,
          constraints.maxHeight.isFinite ? constraints.maxHeight : 800,
        );
        final availability = widget.availability;
        Widget map;
        if (availability.renderer == MapRendererKind.osm &&
            availability.tileSource != null) {
          map = _buildOsmMap(availability.tileSource!);
        } else {
          map = _buildGoogleMap();
        }
        return Stack(
          fit: StackFit.expand,
          children: [map, if (_camera != null) _buildPhotoOverlay(viewport)],
        );
      },
    );
  }
}

// ──────────────────────────────────────────────────────────────
// Shared marker painters (Google bitmap + OSM widget use the same drawing)
// ──────────────────────────────────────────────────────────────

class _PointMarkerPainter {
  final Color color;
  final bool dimmed;

  const _PointMarkerPainter({required this.color, required this.dimmed});

  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.shortestSide / 2 - 3;
    final fill = dimmed ? color.withValues(alpha: 0.35) : color;
    // ขอบขาวเสมอ — คุม contrast บน tile เข้ม (§22.3.7)
    canvas.drawCircle(center, radius, Paint()..color = Colors.white);
    canvas.drawCircle(center, radius - 3, Paint()..color = fill);
  }
}

class _ClusterDonutPainter {
  final Map<IncidentAgeBucket, int> byBucket;
  final int count;
  final bool dimmed;

  const _ClusterDonutPainter({
    required this.byBucket,
    required this.count,
    required this.dimmed,
  });

  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.shortestSide / 2 - 3;
    final opacity = dimmed ? 0.35 : 1.0;

    // White base ring
    canvas.drawCircle(center, radius, Paint()..color = Colors.white);
    final inner = radius - 3;

    // Donut arcs per bucket (bucket order = legend order)
    final total = byBucket.values.fold(0, (a, b) => a + b);
    if (total > 0) {
      var start = -math.pi / 2;
      final rect = Rect.fromCircle(center: center, radius: inner - 4);
      for (final bucket in IncidentAgeBucket.values) {
        final value = byBucket[bucket] ?? 0;
        if (value == 0) continue;
        final sweep = value / total * 2 * math.pi;
        canvas.drawArc(
          rect,
          start,
          sweep,
          true,
          Paint()
            ..color = bucket.color.withValues(alpha: opacity)
            ..style = PaintingStyle.fill,
        );
        start += sweep;
      }
      // Inner hole
      canvas.drawCircle(
        center,
        inner - 8,
        Paint()..color = Colors.white.withValues(alpha: opacity),
      );
    } else {
      canvas.drawCircle(
        center,
        inner,
        Paint()..color = Colors.grey.shade400.withValues(alpha: opacity),
      );
    }

    // Count text
    final textPainter = TextPainter(
      text: TextSpan(
        text: count > 999 ? '999+' : '$count',
        style: TextStyle(
          fontSize: inner > 20 ? 15 : 12,
          fontWeight: FontWeight.bold,
          color: Colors.black87,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: size.width);
    textPainter.paint(
      canvas,
      center - Offset(textPainter.width / 2, textPainter.height / 2),
    );
  }
}

class _OsmPointMarker extends StatelessWidget {
  final IncidentMapPointItem point;
  final bool dimmed;
  final VoidCallback onTap;

  const _OsmPointMarker({
    required this.point,
    required this.dimmed,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Center(
        child: Opacity(
          opacity: dimmed ? 0.35 : 1.0,
          child: Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: point.bucket.color,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
              boxShadow: const [
                BoxShadow(color: Colors.black38, blurRadius: 4),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OsmClusterMarker extends StatelessWidget {
  final IncidentMapClusterItem cluster;
  final bool dimmed;
  final VoidCallback onTap;

  const _OsmClusterMarker({
    required this.cluster,
    required this.dimmed,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final size = _clusterIconSize(cluster.count);
    return GestureDetector(
      onTap: onTap,
      child: CustomPaint(
        size: size,
        painter: _ClusterDonutWidgetPainter(
          byBucket: cluster.byBucket,
          count: cluster.count,
          dimmed: dimmed,
        ),
      ),
    );
  }
}

/// CustomPaint adapter — same drawing as the Google bitmap painter.
class _ClusterDonutWidgetPainter extends CustomPainter {
  final Map<IncidentAgeBucket, int> byBucket;
  final int count;
  final bool dimmed;

  const _ClusterDonutWidgetPainter({
    required this.byBucket,
    required this.count,
    required this.dimmed,
  });

  @override
  void paint(Canvas canvas, Size size) => _ClusterDonutPainter(
    byBucket: byBucket,
    count: count,
    dimmed: dimmed,
  ).paint(canvas, size);

  @override
  bool shouldRepaint(covariant _ClusterDonutWidgetPainter old) =>
      old.count != count ||
      old.dimmed != dimmed ||
      !mapEquals(old.byBucket, byBucket);
}

class _PhotoCard extends StatelessWidget {
  final IncidentMapPhoto photo;
  final VoidCallback onTap;

  const _PhotoCard({required this.photo, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white, width: 2),
          boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 6)],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: CachedNetworkImage(
            imageUrl: photo.url,
            fit: BoxFit.cover,
            placeholder: (_, _) => const ColoredBox(color: Colors.black26),
            errorWidget: (_, _, _) => const ColoredBox(
              color: Colors.black26,
              child: Icon(Icons.broken_image, color: Colors.white54, size: 18),
            ),
          ),
        ),
      ),
    );
  }
}

/// Legend chip row — 5 buckets with counts; tap = highlight/dim (§22.3.4).
class IncidentMapLegendBar extends StatelessWidget {
  final IncidentMapLegend legend;
  final IncidentAgeBucket? highlighted;
  final ValueChanged<IncidentAgeBucket?> onHighlight;

  const IncidentMapLegendBar({
    super.key,
    required this.legend,
    required this.highlighted,
    required this.onHighlight,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final bucket in IncidentAgeBucket.values)
          _LegendChip(
            bucket: bucket,
            count: legend.countOf(bucket),
            selected: highlighted == bucket,
            onTap: () => onHighlight(highlighted == bucket ? null : bucket),
          ),
      ],
    );
  }
}

class _LegendChip extends StatelessWidget {
  final IncidentAgeBucket bucket;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  const _LegendChip({
    required this.bucket,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.black54,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? bucket.color : Colors.white24,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: bucket.color,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1),
              ),
            ),
            const SizedBox(width: 4),
            Text(
              '${bucket.labelTh} $count',
              style: TextStyle(
                fontSize: 10.5,
                color: selected ? Colors.black87 : Colors.white,
                fontWeight: selected ? FontWeight.bold : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Center-state card for loading/empty/error/degraded (§22.3.3).
class IncidentMapStateCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Color accent;

  const IncidentMapStateCard({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
    this.accent = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: LitGlassSurface(
          borderRadius: 20,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: accent, size: 34),
                const SizedBox(height: 10),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    subtitle!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.75),
                      fontSize: 12,
                    ),
                  ),
                ],
                if (actionLabel != null && onAction != null) ...[
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: onAction,
                    child: Text(
                      actionLabel!,
                      style: const TextStyle(
                        color: Color(0xFFFF6B35),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
