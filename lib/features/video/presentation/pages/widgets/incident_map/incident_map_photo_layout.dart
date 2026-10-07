import 'dart:ui';

import '../../../../models/incident_map_models.dart';

/// Screen-space collision layout for incident gallery thumbnails
/// (VIDEO_SYSTEM_PLAN.md §22.5).
///
/// Pure function — no Flutter dependencies beyond `dart:ui`, so the no-overlap
/// guarantee is unit-testable:
///   * each incident may show up to [maxPerIncident] cards in a row anchored
///     above its pin
///   * a card is placed only when it does not intersect any already-placed
///     card, any other incident's anchor exclusion zone, or the viewport edge
///   * [preferredIncidentId] is placed first when returning from map playback;
///     remaining incidents are newest-first (recency priority), ties by id
///   * incidents that cannot fit simply show fewer/no cards — the incident
///     itself is never dropped (the pin remains on the map)

class IncidentPhotoCardPlacement {
  final String incidentId;
  final IncidentMapPhoto photo;
  final Offset topLeft;
  final Size size;

  const IncidentPhotoCardPlacement({
    required this.incidentId,
    required this.photo,
    required this.topLeft,
    required this.size,
  });

  Rect get rect => topLeft & size;
}

Rect _anchorExclusion(Offset anchor, Size size) {
  // Keep a small zone around the pin itself so cards never cover the marker.
  const pad = 6.0;
  return Rect.fromCenter(
    center: anchor,
    width: size.width + pad * 2,
    height: size.height + pad * 2,
  );
}

List<IncidentPhotoCardPlacement> layoutIncidentPhotoCards({
  required Map<String, Offset> anchorByIncidentId,
  required Map<String, List<IncidentMapPhoto>> photosByIncidentId,
  required Size viewport,
  String? preferredIncidentId,
  Size cardSize = const Size(64, 64),
  double gap = 6,
  int maxPerIncident = 3,
  double minZoomScale = 1.0,
}) {
  if (minZoomScale <= 0) return const [];
  final effectiveCard = Size(
    cardSize.width * minZoomScale,
    cardSize.height * minZoomScale,
  );
  final placements = <IncidentPhotoCardPlacement>[];
  final placedRects = <Rect>[];
  // Cards must never cover another incident's pin (§22.5) — the incident's
  // own anchor is exempt because its card row sits above the pin by design.
  final anchorExclusions = <String, Rect>{
    for (final entry in anchorByIncidentId.entries)
      entry.key: _anchorExclusion(entry.value, effectiveCard),
  };

  // Recency priority: newest photo first, ties by incident id.
  DateTime firstCreatedAt(String id) {
    final list = photosByIncidentId[id] ?? const [];
    if (list.isEmpty) return DateTime.fromMillisecondsSinceEpoch(0);
    return list.first.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
  }

  final ids =
      anchorByIncidentId.keys.where(photosByIncidentId.containsKey).toList()
        ..sort((a, b) {
          if (a == preferredIncidentId) return -1;
          if (b == preferredIncidentId) return 1;
          final byTime = firstCreatedAt(b).compareTo(firstCreatedAt(a));
          if (byTime != 0) return byTime;
          return a.compareTo(b);
        });

  for (final id in ids) {
    final anchor = anchorByIncidentId[id];
    if (anchor == null) continue;
    final photos = (photosByIncidentId[id] ?? const [])
        .take(maxPerIncident)
        .toList();
    if (photos.isEmpty) continue;

    // Row of cards centered above the anchor: try offsets 0, -1, +1, -2, +2 …
    // in units of (cardWidth + gap) until every card fits without overlap.
    final rowWidth =
        photos.length * effectiveCard.width + (photos.length - 1) * gap;
    final rowTop = anchor.dy - effectiveCard.height - 10;
    final unit = effectiveCard.width + gap;

    bool tryRow(double startDx) {
      final rects = <Rect>[];
      for (var i = 0; i < photos.length; i++) {
        final left = anchor.dx - rowWidth / 2 + startDx + i * unit;
        final rect = Rect.fromLTWH(
          left,
          rowTop,
          effectiveCard.width,
          effectiveCard.height,
        );
        if (rect.left < 0 ||
            rect.right > viewport.width ||
            rect.top < 0 ||
            rect.bottom > viewport.height) {
          return false;
        }
        for (final placed in [...placedRects, ...rects]) {
          if (placed.overlaps(rect.inflate(gap / 2))) return false;
        }
        for (final entry in anchorExclusions.entries) {
          if (entry.key == id) continue;
          if (entry.value.overlaps(rect)) return false;
        }
        rects.add(rect);
      }
      // Commit
      for (var i = 0; i < photos.length; i++) {
        placements.add(
          IncidentPhotoCardPlacement(
            incidentId: id,
            photo: photos[i],
            topLeft: rects[i].topLeft,
            size: effectiveCard,
          ),
        );
        placedRects.add(rects[i]);
      }
      return true;
    }

    var placed = false;
    for (var step = 0; step <= 6 && !placed; step++) {
      for (final dx in step == 0 ? [0.0] : [-step * unit, step * unit]) {
        if (tryRow(dx)) {
          placed = true;
          break;
        }
      }
    }
    // Cannot fit → show nothing for this incident; the pin still exists.
  }
  return placements;
}
