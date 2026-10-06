import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:sheserved/features/video/models/incident_map_models.dart';
import 'package:sheserved/features/video/presentation/pages/widgets/incident_map/incident_map_photo_layout.dart';

const _cardSize = Size(64, 64);
const _viewport = Size(390, 800);

IncidentMapPhoto _photo(String id, {DateTime? createdAt}) => IncidentMapPhoto(
  id: id,
  url: 'http://x/$id.jpg',
  createdAt: createdAt ?? DateTime.utc(2026, 10, 6, 12),
);

void main() {
  group('layoutIncidentPhotoCards — ไม่ทับกัน (§22.5)', () {
    test('เหตุเดียว 3 ภาพ → เรียงแถวเหนือหมุด', () {
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
      // ทุกใบอยู่เหนือหมุด
      for (final p in placements) {
        expect(p.rect.bottom, lessThanOrEqualTo(300));
      }
    });

    test('จำกัด 3 ใบต่อเหตุ — ส่วนที่เหลือไม่วาด (ยังอยู่ใน gallery เต็ม)', () {
      final placements = layoutIncidentPhotoCards(
        anchorByIncidentId: {'a': const Offset(200, 300)},
        photosByIncidentId: {
          'a': [
            _photo('p1'),
            _photo('p2'),
            _photo('p3'),
            _photo('p4'),
            _photo('p5'),
          ],
        },
        viewport: _viewport,
        cardSize: _cardSize,
      );
      expect(placements.length, 3);
    });

    test('สองเหตุใกล้กัน → ใบที่วางไม่ได้ถูกข้าม ไม่ทับหมุดเหตุอื่น', () {
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

      // ไม่มี card ใดทับ exclusion zone ของหมุดอีกเหตุ
      for (final p in placements) {
        if (p.incidentId == 'a') {
          final bExclusion = Rect.fromCenter(
            center: const Offset(130, 300),
            width: _cardSize.width + 12,
            height: _cardSize.height + 12,
          );
          expect(
            p.rect.overlaps(bExclusion),
            isFalse,
            reason: 'card ของ a ทับหมุดของ b',
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

    test('ออกนอกจอ → ไม่วาด (ไม่ล้น viewport)', () {
      final placements = layoutIncidentPhotoCards(
        anchorByIncidentId: {'edge': const Offset(5, 5)},
        photosByIncidentId: {
          'edge': [_photo('p1')],
        },
        viewport: _viewport,
        cardSize: _cardSize,
      );
      // หมุดชิดมุมบนซ้าย — แถวเหนือหมุดลบกับขอบบน จึงไม่มีที่วาง
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
  });
}
