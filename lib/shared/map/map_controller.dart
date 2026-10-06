import 'map_types.dart';

/// Provider-agnostic controller facade. Screens command the map through this
/// interface only — they never hold a `GoogleMapController` or flutter_map
/// `MapController`.
///
/// Contract:
/// - Every command is a no-op after [dispose] (never throws, never crashes
///   when the widget is already gone).
/// - [fitToBounds] handles edge cases: empty list is a no-op, a single point
///   (or zero-area bounds) animates to that point at [fallbackZoom].
abstract class SheservedMapController {
  bool get isDisposed;

  /// Jump the camera to [target]. [zoom] keeps the current zoom when null.
  void moveTo(MapLatLng target, {double? zoom});

  /// Animate the camera to [target]. [zoom] keeps the current zoom when null.
  void animateTo(MapLatLng target, {double? zoom});

  /// Fit [points] into view with screen [padding]. Empty → no-op.
  /// A single point or zero-area bounds → [animateTo] center at
  /// [fallbackZoom] (degenerate bounds are never forwarded to the renderer).
  void fitToBounds(
    List<MapLatLng> points, {
    double padding = 64,
    double fallbackZoom = 15,
  });

  void dispose();
}

/// Bounds shared by both adapters so the degenerate-bounds rule lives in one
/// place. Returns a normalized [MapLatLngBounds], or null when [points] is
/// empty or reduces to a single location (caller should [moveTo]/[animateTo]
/// instead of fitting).
MapLatLngBounds? normalizedFitBounds(List<MapLatLng> points) {
  final bounds = MapLatLngBounds.fromPoints(points);
  if (bounds == null) return null;
  if (bounds.southwest == bounds.northeast) return null;
  return bounds.normalized();
}

/// Test/dev controller that records commands instead of touching a renderer.
class FakeSheservedMapController implements SheservedMapController {
  final List<String> calls = [];
  MapLatLng? lastTarget;
  double? lastZoom;
  List<MapLatLng>? lastFitPoints;
  double? lastFitPadding;
  bool _disposed = false;

  @override
  bool get isDisposed => _disposed;

  @override
  void moveTo(MapLatLng target, {double? zoom}) {
    if (_disposed) return;
    calls.add('moveTo');
    lastTarget = target;
    lastZoom = zoom;
  }

  @override
  void animateTo(MapLatLng target, {double? zoom}) {
    if (_disposed) return;
    calls.add('animateTo');
    lastTarget = target;
    lastZoom = zoom;
  }

  @override
  void fitToBounds(
    List<MapLatLng> points, {
    double padding = 64,
    double fallbackZoom = 15,
  }) {
    if (_disposed) return;
    calls.add('fitToBounds');
    lastFitPoints = points;
    lastFitPadding = padding;
  }

  @override
  void dispose() => _disposed = true;
}
