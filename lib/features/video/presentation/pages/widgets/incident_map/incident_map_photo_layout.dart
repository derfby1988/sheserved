import 'dart:math' as math;
import 'dart:ui';

import '../../../../models/incident_map_models.dart';

/// เพดาน preview cards ต่อเหตุ — ต้องตรงกับ `PHOTOS_PER_POINT` ฝั่ง server.
const int kIncidentMapMaxPhotosPerIncident = 15;

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
///     is geometrically incapable of covering its own pin; the base ring fits
///     up to 5 cards per incident at the default card size
///   * when `n` exceeds the base ring's capacity the layout adapts
///     automatically (least distortion first — see [_RingLayout.forCount]):
///     expand the ring → split into two concentric rings → shrink the card
///   * a layout is committed all-or-none; up to 8 rotations are tried per
///     candidate before moving to the next strategy — when every strategy
///     fails, a partial-ring fallback keeps the rotation that fits the most
///     cards on the base ring (a partial ring beats no ring); an incident
///     that still fits nothing is dropped (the pin itself remains on the map)
///   * photo pins stacked on top of each other (screen distance below one
///     pin diameter) can never satisfy each other's pin exclusion — and the
///     lower pin is not tappable anyway — so they share one ring slot that
///     goes to the highest-priority incident (preferred → recency → id)
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
  int maxPerIncident = kIncidentMapMaxPhotosPerIncident,
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

  /// เพดานรัศมีสำหรับกลยุทธ์ "ขยายวง" — วงที่ใหญ่กว่านี้ให้แตกเป็น 2 ชั้นแทน
  /// (default 140 ≈ พอดี 9 ใบบนวงเดียว)
  double expandedRingLimit = 140,

  /// เพดานรัศมีสูงสุดที่ยอมให้การ์ดออกจากหมุด (ครอบคลุมชั้นนอก/วงที่ย่อการ์ด)
  double maxRingRadius = 200,

  /// สเกลการ์ดต่ำสุดสำหรับกลยุทธ์ "ย่อยการ์ด" — ต่ำกว่านี้เลิกวางเหตุนั้น
  double minCardScale = 0.5,
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
  // ระยะศูนย์การ์ดขั้นต่ำให้ไม่ชนกัน: rect ใหม่ถูก inflate gap/2 ก่อนเทียบ
  // กับ rect เดิม → ต้องห่าง ≥ card + gap/2 บนแกนใดแกนหนึ่ง (64→67px)
  final spacing = math.max(effectiveCard.width, effectiveCard.height) + gap / 2;
  final placements = <IncidentPhotoCardPlacement>[];
  final placedRects = <Rect>[];
  // Cards must never cover another incident's pin (§22.5) — radial rings
  // ทิ้งการ์ดได้รอบทิศ จึงขยาย zone เป็นวงกลมรอบหมุดแทนกล่องเหนือหมุด;
  // หมุดของตัวเองเว้นไว้เพราะ ringRadius คุมไม่ให้การ์ดแตะหน้าหมุดอยู่แล้ว
  const pad = 6.0;

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

  // Stacked photo pins share one ring slot: pins closer than a pin diameter
  // already overlap visually, their mutual exclusion circles would make
  // every card illegal, and only the top pin is tappable anyway. The
  // representative is the first in priority order (preferred → recency).
  final ids2 = <String>[];
  final repAnchors = <String, Offset>{};
  for (final id in ids) {
    final anchor = anchorByIncidentId[id];
    if (anchor == null) continue;
    var stacked = false;
    for (final repAnchor in repAnchors.values) {
      if ((anchor - repAnchor).distance <= pinRadius * 2) {
        stacked = true;
        break;
      }
    }
    if (!stacked) {
      ids2.add(id);
      repAnchors[id] = anchor;
    }
  }

  final anchorExclusions = <String, Rect>{
    for (final entry in repAnchors.entries)
      entry.key: _anchorExclusion(entry.value, pinRadius + cardHalfDiag + pad),
  };

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

  for (final id in ids2) {
    final anchor = anchorByIncidentId[id];
    if (anchor == null) continue;
    final photos = (photosByIncidentId[id] ?? const [])
        .take(maxPerIncident)
        .toList();
    if (photos.isEmpty) continue;
    final n = photos.length;

    bool tryLayout(_RingLayout layout, double rotation) {
      final rects = <Rect>[];
      for (final spec in layout.rings) {
        for (var i = 0; i < spec.count; i++) {
          final angle =
              startAngle + rotation + spec.phase + 2 * math.pi * i / spec.count;
          final center = Offset(
            anchor.dx + spec.radius * math.cos(angle),
            anchor.dy + spec.radius * math.sin(angle),
          );
          final rect = Rect.fromCenter(
            center: center,
            width: layout.card.width,
            height: layout.card.height,
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
      }
      // Commit — ภาพเรียงตามวง (ชั้นในก่อน) แล้วตามมุม
      for (var i = 0; i < rects.length; i++) {
        placements.add(
          IncidentPhotoCardPlacement(
            incidentId: id,
            photo: photos[i],
            topLeft: rects[i].topLeft,
            size: layout.card,
          ),
        );
        placedRects.add(rects[i]);
      }
      return true;
    }

    var placed = false;
    for (final layout in _RingLayout.forCount(
      n,
      card: effectiveCard,
      baseRing: ring,
      spacing: spacing,
      pinRadius: pinRadius,
      gap: gap,
      expandedRingLimit: expandedRingLimit,
      maxRingRadius: maxRingRadius,
      minCardScale: minCardScale,
    )) {
      for (final rotation in rotations) {
        if (tryLayout(layout, rotation)) {
          placed = true;
          break;
        }
      }
      if (placed) break;
    }

    if (!placed) {
      // Partial-ring fallback: no strategy fits all n cards (viewport edge
      // or a neighbouring photo pin's exclusion) — keep the base-ring
      // rotation that fits the most cards instead of dropping the ring.
      var best = <Rect>[];
      for (final rotation in rotations) {
        final candidate = <Rect>[];
        for (var i = 0; i < n; i++) {
          final angle = startAngle + rotation + 2 * math.pi * i / n;
          final rect = Rect.fromCenter(
            center: Offset(
              anchor.dx + ring * math.cos(angle),
              anchor.dy + ring * math.sin(angle),
            ),
            width: effectiveCard.width,
            height: effectiveCard.height,
          );
          if (rect.left < 0 ||
              rect.right > viewport.width ||
              rect.top < 0 ||
              rect.bottom > viewport.height) {
            continue;
          }
          var blocked = false;
          for (final other in [...placedRects, ...candidate]) {
            if (other.overlaps(rect.inflate(gap / 2))) {
              blocked = true;
              break;
            }
          }
          if (!blocked) {
            for (final entry in anchorExclusions.entries) {
              if (entry.key == id) continue;
              if (entry.value.overlaps(rect)) {
                blocked = true;
                break;
              }
            }
          }
          if (!blocked) candidate.add(rect);
        }
        if (candidate.length > best.length) best = candidate;
        if (best.length == n) break;
      }
      for (var i = 0; i < best.length; i++) {
        placements.add(
          IncidentPhotoCardPlacement(
            incidentId: id,
            photo: photos[i],
            topLeft: best[i].topLeft,
            size: effectiveCard,
          ),
        );
        placedRects.add(best[i]);
      }
    }
    // ยังไม่มีที่วางเลย → ไม่แสดงการ์ดของเหตุนี้; หมุดยังอยู่บนแผนที่
  }
  return placements;
}

/// วงแหวนชั้นเดียวใน [ _RingLayout ] — `phase` เลื่อนมุมเริ่ม (ใช้สลับช่อง
/// ของชั้นนอกให้ตรงกลางช่องว่างชั้นใน)
class _RingSpec {
  final double radius;
  final int count;
  final double phase;

  const _RingSpec(this.radius, this.count, {this.phase = 0});
}

/// ชุดผู้สมัคร layout ของเหตุหนึ่ง — `card` อาจถูกย่อในกลยุทธ์สุดท้าย
class _RingLayout {
  final Size card;
  final List<_RingSpec> rings;

  const _RingLayout(this.card, this.rings);

  /// รัศมีขั้นต่ำที่รับประกันว่าการ์ด `count` ใบไม่ชนกัน **ทุกมุมหมุน** —
  /// คู่ที่ชิดที่สุดต้องห่างกัน ≥ `spacing·√2` (worst case ทแยง 45°)
  static double _minRingFor(int count, double spacing) =>
      count < 2 ? 0 : (spacing * math.sqrt2) / (2 * math.sin(math.pi / count));

  /// Candidate layouts เรียงจากบิดเบือนภาพน้อยไปมาก (§22.17):
  ///   1. วงฐานเดิม — รองรับสูงสุด ~5 ใบ (rotation sweep ตัดสิน)
  ///   2. ขยายวง — คงขนาดการ์ด เพิ่มรัศมีจนชนกันไม่ได้ทางเรขาคณิต (≤ limit)
  ///   3. วงแหวน 2 ชั้น — ชั้นใน ≤5 ใบบนวงฐาน, ชั้นนอกห่างชั้นใน spacing·√2
  ///   4. ย่อยการ์ด — เหตุสุดท้าย: ลดสเกลจนวงเดียวรับได้ภายใต้ maxRingRadius
  static Iterable<_RingLayout> forCount(
    int n, {
    required Size card,
    required double baseRing,
    required double spacing,
    required double pinRadius,
    required double gap,
    required double expandedRingLimit,
    required double maxRingRadius,
    required double minCardScale,
  }) sync* {
    yield _RingLayout(card, [_RingSpec(baseRing, n)]);
    if (n < 2) return;

    final expanded = math.max(baseRing, _minRingFor(n, spacing));
    if (expanded > baseRing && expanded <= expandedRingLimit) {
      yield _RingLayout(card, [_RingSpec(expanded, n)]);
    }

    const innerMax = 5; // เพดานเชิงประจักษ์ของวงฐาน (ดู §22.17)
    final innerCount = n < innerMax ? n : innerMax;
    final outerCount = n - innerCount;
    if (outerCount > 0) {
      final outerRadius = baseRing + spacing * math.sqrt2;
      if (outerRadius <= maxRingRadius &&
          _minRingFor(outerCount, spacing) <= outerRadius) {
        yield _RingLayout(card, [
          _RingSpec(baseRing, innerCount),
          _RingSpec(outerRadius, outerCount, phase: math.pi / outerCount),
        ]);
      }
    }

    for (final scale in const [0.85, 0.7, 0.55]) {
      if (scale < minCardScale) break;
      final shrunk = Size(card.width * scale, card.height * scale);
      final shrunkSpacing = math.max(shrunk.width, shrunk.height) + gap / 2;
      final shrunkBase = pinRadius + shrunk.width * math.sqrt2 / 2 + gap;
      final shrunkRing = math.max(shrunkBase, _minRingFor(n, shrunkSpacing));
      if (shrunkRing <= maxRingRadius) {
        yield _RingLayout(shrunk, [_RingSpec(shrunkRing, n)]);
        break;
      }
    }
  }
}
