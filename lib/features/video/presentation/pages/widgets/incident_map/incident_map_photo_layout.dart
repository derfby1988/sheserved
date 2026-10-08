import 'dart:math' as math;
import 'dart:ui';

import '../../../../models/incident_map_models.dart';

/// Screen-space collision layout for incident gallery thumbnails
/// (VIDEO_SYSTEM_PLAN.md §22.5/§22.17).
///
/// Pure function — no Flutter dependencies beyond `dart:ui`, so the no-overlap
/// guarantee is unit-testable:
///   * each incident may show up to [maxPerIncident] cards arranged as a
///     **radial ring around its pin** — the same pattern as the consultation
///     `RadialQuestionLayout` (`angle = startAngle + 2π·i/n`, `offset =
///     r·(cos θ, sin θ)`): cards orbit the anchor instead of sitting in a row
///     above it, so the pin face is always visible
///   * [ringRadius] defaults to `pinRadius + cardHalfDiagonal + pad` → a card
///     is geometrically incapable of covering its own pin
///   * a ring is committed all-or-none; up to 8 rotations are tried before
///     the incident's cards are dropped (the pin itself remains on the map)
///   * a card is placed only when it does not intersect any already-placed
///     card, any other incident's pin exclusion circle, or the viewport edge
///   * [preferredIncidentId] is placed first when returning from map playback;
///     remaining incidents are newest-first (recency priority), ties by id

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

  /// จุดกึ่งกลางของการ์ด — ใช้ตรวจระยะห่างจากหมุด (radial contract)
  Offset get center => rect.center;
}

/// รัศมีที่หมุดอีกเหตุต้องรักษา — การ์ดใด ๆ ที่มาทับวงกลมนี้จะถือว่าบังหมุด
/// (radius = รัศมีหมุดที่มองเห็น + ครึ่งเส้นทแยงมุมการ์ด + pad)
Rect _anchorExclusion(Offset anchor, double radius) =>
    Rect.fromCircle(center: anchor, radius: radius);

List<IncidentPhotoCardPlacement> layoutIncidentPhotoCards({
  required Map<String, Offset> anchorByIncidentId,
  required Map<String, List<IncidentMapPhoto>> photosByIncidentId,
  required Size viewport,
  String? preferredIncidentId,
  Size cardSize = const Size(64, 64),
  double gap = 6,
  int maxPerIncident = 3,
  double minZoomScale = 1.0,

  /// รัศมีของหมุดบนแผนที่ (รวมขอบขาว) — OSM widget ~22px box, Google
  /// painter รัศมี ~19 บนบิตแมป 44dp; ใช้ 22 เผื่อทั้งคู่
  double pinRadius = 22,

  /// มุมเริ่มของการ์ดใบแรก — ดีฟอลต์ด้านบนของหมุด (เดียวกับ
  /// RadialQuestionLayout)
  double startAngle = -math.pi / 2,

  /// ระยะจุดกลางการ์ดถึงหมุด — null = `pinRadius + cardHalfDiagonal + gap`
  /// (ค่าที่ทำให้การ์ดไม่มีทางทับหน้าหมุด)
  double? ringRadius,
}) {
  if (minZoomScale <= 0) return const [];
  final effectiveCard = Size(
    cardSize.width * minZoomScale,
    cardSize.height * minZoomScale,
  );
  final cardHalfDiag =
      math.sqrt(
        effectiveCard.width * effectiveCard.width +
            effectiveCard.height * effectiveCard.height,
      ) /
      2;
  final ring = ringRadius ?? (pinRadius + cardHalfDiag + gap);
  final placements = <IncidentPhotoCardPlacement>[];
  final placedRects = <Rect>[];
  // Cards must never cover another incident's pin (§22.5) — radial rings
  // ทิ้งการ์ดได้รอบทิศ จึงขยาย zone เป็นวงกลมรอบหมุดแทนกล่องเหนือหมุด;
  // หมุดของตัวเองเว้นไว้เพราะ ringRadius คุมไม่ให้การ์ดแตะหน้าหมุดอยู่แล้ว
  const pad = 6.0;
  final anchorExclusions = <String, Rect>{
    for (final entry in anchorByIncidentId.entries)
      entry.key: _anchorExclusion(entry.value, pinRadius + cardHalfDiag + pad),
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

  // ลองหมุนวงรอบหมุด (0°, ±45°, ±90°, ±135°, 180°) จนกว่าจะวางครบทุกใบ
  const rotations = <double>[
    0,
    math.pi / 4,
    -math.pi / 4,
    math.pi / 2,
    -math.pi / 2,
    3 * math.pi / 4,
    -3 * math.pi / 4,
    math.pi,
  ];

  for (final id in ids) {
    final anchor = anchorByIncidentId[id];
    if (anchor == null) continue;
    final photos = (photosByIncidentId[id] ?? const [])
        .take(maxPerIncident)
        .toList();
    if (photos.isEmpty) continue;
    final n = photos.length;

    bool tryRing(double rotation) {
      final rects = <Rect>[];
      for (var i = 0; i < n; i++) {
        final angle = startAngle + rotation + 2 * math.pi * i / n;
        final center = Offset(
          anchor.dx + ring * math.cos(angle),
          anchor.dy + ring * math.sin(angle),
        );
        final rect = Rect.fromCenter(
          center: center,
          width: effectiveCard.width,
          height: effectiveCard.height,
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
      for (var i = 0; i < n; i++) {
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

    for (final rotation in rotations) {
      if (tryRing(rotation)) break;
    }
    // วงไม่มีที่วาง → ไม่แสดงการ์ดของเหตุนี้; หมุดยังอยู่บนแผนที่
  }
  return placements;
}
