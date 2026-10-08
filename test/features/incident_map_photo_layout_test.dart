import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:sheserved/features/video/models/incident_map_models.dart';
import 'package:sheserved/features/video/presentation/pages/widgets/incident_map/incident_map_photo_layout.dart';

const _cardSize = Size(64, 64);
const _viewport = Size(390, 800);

// radial contract: ring radius = pinRadius(22) + cardHalfDiag(45.25) + gap(6)
const _ringRadius = 73.25;
const _pinExclusionRadius = 22 + 45.25 + 6;

IncidentMapPhoto _photo(String id, {DateTime? createdAt}) => IncidentMapPhoto(
  id: id,
  url: 'http://x/$id.jpg',
  createdAt: createdAt ?? DateTime.utc(2026, 10, 6, 12),
);

Rect _pinCircle(Offset anchor) =>
    Rect.fromCircle(center: anchor, radius: _pinExclusionRadius);

void main() {
  group('layoutIncidentPhotoCards — radial ring รอบหมุด (§22.17)', () {
    test('เหตุเดียว 3 ภาพ → วางเป็นวงแหวนรอบหมุด ไม่บังหมุด', () {
      final placements = layoutIncidentPhotoCards(
        anchorByIncidentId: {'a': const Offset(200, 300)},
        photosByIncidentId: {
          'a': [_photo('p1'), _photo('p2'), _photo('p3')],
        },
        viewport: _viewport,
        cardSize: _cardSize,
      );

      expect(placements.length, 3);
      final rects = placements.map((p) => p.rect).toList();
      for (var i = 0; i < rects.length; i++) {
        for (var j = i + 1; j < rects.length; j++) {
          expect(
            rects[i].overlaps(rects[j]),
            isFalse,
            reason: 'card $i ทับ card $j',
          );
        }
      }
      // ทุกใบอยู่บนวงแหวนรัศมีเดียวกันและไม่มีใบแตะวงกลมของหมุด
      for (final p in placements) {
        expect(
          (p.center - const Offset(200, 300)).distance,
          closeTo(_ringRadius, 0.5),
          reason: 'การ์ดไม่ได้อยู่บนวงแหวนรอบหมุด',
        );
        expect(
          p.rect.overlaps(
            Rect.fromCircle(center: const Offset(200, 300), radius: 22),
          ),
          isFalse,
          reason: 'การ์ดทับหมุดของตัวเอง',
        );
      }
    });

    test('การ์ดใบเดียวเริ่มที่ด้านบนของหมุด', () {
      final placements = layoutIncidentPhotoCards(
        anchorByIncidentId: {'a': const Offset(200, 300)},
        photosByIncidentId: {
          'a': [_photo('p1')],
        },
        viewport: _viewport,
        cardSize: _cardSize,
      );
      expect(placements, hasLength(1));
      final c = placements.single.center;
      expect(c.dx, closeTo(200, 0.5));
      expect(c.dy, closeTo(300 - _ringRadius, 0.5));
    });

    test(
      'จำกัด 15 ใบต่อเหตุ (เพดานเดียวกับ PHOTOS_PER_POINT) — ที่เหลือไม่วาด',
      () {
        final placements = layoutIncidentPhotoCards(
          anchorByIncidentId: {'a': const Offset(400, 400)},
          photosByIncidentId: {'a': List.generate(20, (i) => _photo('p$i'))},
          viewport: const Size(800, 800),
        );
        expect(placements.length, kIncidentMapMaxPhotosPerIncident);
        expect(kIncidentMapMaxPhotosPerIncident, 15);
      },
    );

    test('สองเหตุใกล้กัน → วงที่วางไม่ได้ถูกข้าม ไม่ทับหมุดเหตุอื่น', () {
      final placements = layoutIncidentPhotoCards(
        anchorByIncidentId: {
          'a': const Offset(100, 300),
          'b': const Offset(130, 300),
        },
        photosByIncidentId: {
          'a': [_photo('p1'), _photo('p2'), _photo('p3')],
          'b': [_photo('q1')],
        },
        viewport: _viewport,
        cardSize: _cardSize,
      );

      // ไม่มี card ใดทับวงกลม exclusion ของหมุดอีกเหตุ
      for (final p in placements) {
        if (p.incidentId == 'a') {
          expect(
            p.rect.overlaps(_pinCircle(const Offset(130, 300))),
            isFalse,
            reason: 'card ของ a ทับหมุดของ b',
          );
        } else {
          expect(
            p.rect.overlaps(_pinCircle(const Offset(100, 300))),
            isFalse,
            reason: 'card ของ b ทับหมุดของ a',
          );
        }
      }
      // ไม่มี card ทับกันเอง
      final rects = placements.map((p) => p.rect).toList();
      for (var i = 0; i < rects.length; i++) {
        for (var j = i + 1; j < rects.length; j++) {
          expect(rects[i].overlaps(rects[j]), isFalse);
        }
      }
    });

    test('สองเหตุห่างพอ → วางวงได้ทั้งคู่', () {
      final placements = layoutIncidentPhotoCards(
        anchorByIncidentId: {
          'a': const Offset(80, 300),
          'b': const Offset(330, 300),
        },
        photosByIncidentId: {
          'a': [_photo('p1')],
          'b': [_photo('q1')],
        },
        viewport: _viewport,
        cardSize: _cardSize,
      );
      expect(placements, hasLength(2));
    });

    test('หมุดชิดมุมจอ → หมุนวงหาด้านที่ว่าง (ยังแสดงการ์ด)', () {
      final placements = layoutIncidentPhotoCards(
        anchorByIncidentId: {'edge': const Offset(5, 5)},
        photosByIncidentId: {
          'edge': [_photo('p1')],
        },
        viewport: _viewport,
        cardSize: _cardSize,
      );
      // ด้านขวาล่างของหมุดยังอยู่ในจอ — วงแหวนหมุนไปทางนั้นได้
      expect(placements, hasLength(1));
      final rect = placements.single.rect;
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.top, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(_viewport.width));
      expect(rect.bottom, lessThanOrEqualTo(_viewport.height));
    });

    test('หมุดหลุดจอไกลเกินไป → ไม่วาด', () {
      final placements = layoutIncidentPhotoCards(
        anchorByIncidentId: {'far': const Offset(-200, 300)},
        photosByIncidentId: {
          'far': [_photo('p1')],
        },
        viewport: _viewport,
        cardSize: _cardSize,
      );
      expect(placements, isEmpty);
    });

    test('เหตุที่ไม่มีภาพไม่ถูกวาง แต่ไม่ทำให้เหตุอื่นหาย', () {
      final placements = layoutIncidentPhotoCards(
        anchorByIncidentId: {
          'a': const Offset(200, 300),
          'b': const Offset(60, 300),
        },
        photosByIncidentId: {
          'a': [_photo('p1')],
        },
        viewport: _viewport,
        cardSize: _cardSize,
      );
      expect(placements.length, 1);
      expect(placements.single.incidentId, 'a');
    });

    test('ลำดับความสำคัญตามภาพใหม่สุด (recency priority)', () {
      final old = _photo('old', createdAt: DateTime.utc(2026, 1, 1));
      final newPhoto = _photo('new', createdAt: DateTime.utc(2026, 10, 6));
      final placements = layoutIncidentPhotoCards(
        anchorByIncidentId: {
          'old-i': const Offset(100, 300),
          'new-i': const Offset(300, 300),
        },
        photosByIncidentId: {
          'old-i': [old],
          'new-i': [newPhoto],
        },
        viewport: _viewport,
        cardSize: _cardSize,
      );
      // ทั้งคู่วางได้ — ตรวจว่าใบของเหตุใหม่ถูกวางก่อนในลิสต์
      expect(placements.first.incidentId, 'new-i');
    });

    test('ภาพ 6 ใบ → กลยุทธ์ "ขยายวง" (ring > วงฐาน, การ์ดขนาดเดิม)', () {
      final placements = layoutIncidentPhotoCards(
        anchorByIncidentId: {'a': const Offset(400, 400)},
        photosByIncidentId: {'a': List.generate(6, (i) => _photo('p$i'))},
        viewport: const Size(800, 800),
        cardSize: _cardSize,
        maxPerIncident: 6,
      );
      expect(placements, hasLength(6));
      for (final p in placements) {
        // วงขยาย ≥ spacing·√2/(2 sin π/6) ≈ 94.8 และการ์ดไม่ย่อ
        expect(
          (p.center - const Offset(400, 400)).distance,
          greaterThan(_ringRadius + 10),
        );
        expect(p.size, _cardSize);
      }
      final rects = placements.map((p) => p.rect).toList();
      for (var i = 0; i < rects.length; i++) {
        for (var j = i + 1; j < rects.length; j++) {
          expect(rects[i].overlaps(rects[j]), isFalse);
        }
      }
    });

    test('ภาพ 10 ใบ → กลยุทธ์ "วงแหวน 2 ชั้น" (5 ชั้นใน + 5 ชั้นนอก)', () {
      final placements = layoutIncidentPhotoCards(
        anchorByIncidentId: {'a': const Offset(400, 400)},
        photosByIncidentId: {'a': List.generate(10, (i) => _photo('p$i'))},
        viewport: const Size(800, 800),
        cardSize: _cardSize,
        maxPerIncident: 10,
      );
      expect(placements, hasLength(10));
      final radii = placements
          .map((p) => (p.center - const Offset(400, 400)).distance)
          .toList();
      final inner = radii.where((r) => r < 100).length;
      final outer = radii.where((r) => r >= 100).length;
      expect(inner, 5);
      expect(outer, 5);
      final rects = placements.map((p) => p.rect).toList();
      for (var i = 0; i < rects.length; i++) {
        for (var j = i + 1; j < rects.length; j++) {
          expect(rects[i].overlaps(rects[j]), isFalse);
        }
      }
    });

    test('ภาพ 15 ใบ → วางครบ 5+10 ใบในวงแหวน 2 ชั้นบนจอมือถือ', () {
      const viewport = Size(390, 800);
      const anchor = Offset(195, 400);
      final placements = layoutIncidentPhotoCards(
        anchorByIncidentId: {'a': anchor},
        photosByIncidentId: {'a': List.generate(15, (i) => _photo('p$i'))},
        viewport: viewport,
      );

      expect(placements, hasLength(15));
      expect(placements.every((p) => p.size == _cardSize), isTrue);
      final radii = placements.map((p) => (p.center - anchor).distance);
      expect(radii.where((r) => r < 100), hasLength(5));
      expect(radii.where((r) => r >= 100), hasLength(10));
      for (final placement in placements) {
        expect(viewport.contains(placement.rect.topLeft), isTrue);
        expect(viewport.contains(placement.rect.bottomRight), isTrue);
        expect(
          placement.rect.overlaps(Rect.fromCircle(center: anchor, radius: 22)),
          isFalse,
        );
      }
      final rects = placements.map((p) => p.rect).toList();
      for (var i = 0; i < rects.length; i++) {
        for (var j = i + 1; j < rects.length; j++) {
          expect(rects[i].overlaps(rects[j].inflate(3)), isFalse);
        }
      }
    });

    test('ภาพ 16 ใบ → กลยุทธ์ "ย่อยการ์ด" (ขนาดการ์ด < 64 แต่ยังวางครบ)', () {
      final placements = layoutIncidentPhotoCards(
        anchorByIncidentId: {'a': const Offset(400, 400)},
        photosByIncidentId: {'a': List.generate(16, (i) => _photo('p$i'))},
        viewport: const Size(800, 800),
        cardSize: _cardSize,
        maxPerIncident: 16,
      );
      expect(placements, hasLength(16));
      expect(placements.first.size.width, lessThan(64));
      final rects = placements.map((p) => p.rect).toList();
      for (var i = 0; i < rects.length; i++) {
        for (var j = i + 1; j < rects.length; j++) {
          expect(rects[i].overlaps(rects[j]), isFalse);
        }
      }
    });

    test('map-return incident photos take layout priority', () {
      final placements = layoutIncidentPhotoCards(
        anchorByIncidentId: {
          'selected': const Offset(150, 400),
          'newer': const Offset(450, 400),
        },
        photosByIncidentId: {
          'selected': [
            _photo('selected-1', createdAt: DateTime.utc(2026, 1, 1)),
            _photo('selected-2', createdAt: DateTime.utc(2026, 1, 2)),
            _photo('selected-3', createdAt: DateTime.utc(2026, 1, 3)),
          ],
          'newer': [_photo('newer-1', createdAt: DateTime.utc(2026, 10, 6))],
        },
        viewport: const Size(600, 800),
        cardSize: _cardSize,
        preferredIncidentId: 'selected',
      );

      expect(
        placements.take(3).map((placement) => placement.incidentId),
        everyElement('selected'),
      );
      expect(
        placements.where((placement) => placement.incidentId == 'selected'),
        hasLength(3),
      );
    });
  });
}
