import 'package:flutter_test/flutter_test.dart';
import 'package:sheserved/features/video/data/repositories/video_repository.dart';
import 'package:sheserved/features/video/models/incident_map_models.dart';

void main() {
  group('IncidentAgeBucketPolicy — ขอบเขตช่วงสีต่อเนื่อง (§22.1)', () {
    final now = DateTime.utc(2026, 10, 6, 12, 0, 0);
    DateTime ago(Duration d) => now.subtract(d);

    test('แดง: 0–24 ชม. (รวมขอบ 24 ชม.)', () {
      expect(
        IncidentAgeBucketPolicy.bucketForCreatedAt(ago(Duration.zero), now),
        IncidentAgeBucket.red,
      );
      expect(
        IncidentAgeBucketPolicy.bucketForCreatedAt(
          ago(const Duration(hours: 24)),
          now,
        ),
        IncidentAgeBucket.red,
      );
    });

    test('ส้ม: >24 ชม.–7 วัน', () {
      expect(
        IncidentAgeBucketPolicy.bucketForCreatedAt(
          ago(const Duration(hours: 24, milliseconds: 1)),
          now,
        ),
        IncidentAgeBucket.orange,
      );
      expect(
        IncidentAgeBucketPolicy.bucketForCreatedAt(
          ago(const Duration(days: 7)),
          now,
        ),
        IncidentAgeBucket.orange,
      );
    });

    test('ทอง: >7–35 วัน', () {
      expect(
        IncidentAgeBucketPolicy.bucketForCreatedAt(
          ago(const Duration(days: 7, milliseconds: 1)),
          now,
        ),
        IncidentAgeBucket.gold,
      );
      expect(
        IncidentAgeBucketPolicy.bucketForCreatedAt(
          ago(const Duration(days: 35)),
          now,
        ),
        IncidentAgeBucket.gold,
      );
    });

    test('เทา: >35–365 วัน', () {
      expect(
        IncidentAgeBucketPolicy.bucketForCreatedAt(
          ago(const Duration(days: 35, milliseconds: 1)),
          now,
        ),
        IncidentAgeBucket.gray,
      );
      expect(
        IncidentAgeBucketPolicy.bucketForCreatedAt(
          ago(const Duration(days: 365)),
          now,
        ),
        IncidentAgeBucket.gray,
      );
    });

    test('ดำ: >365 วัน', () {
      expect(
        IncidentAgeBucketPolicy.bucketForCreatedAt(
          ago(const Duration(days: 365, milliseconds: 1)),
          now,
        ),
        IncidentAgeBucket.black,
      );
      expect(
        IncidentAgeBucketPolicy.bucketForCreatedAt(
          ago(const Duration(days: 400)),
          now,
        ),
        IncidentAgeBucket.black,
      );
    });

    test('อนาคต/ค่าว่าง ไม่ถูกจัดช่วง (ห้ามขึ้นสีแดง — §22.1 note)', () {
      expect(
        IncidentAgeBucketPolicy.bucketForCreatedAt(
          now.add(const Duration(minutes: 1)),
          now,
        ),
        isNull,
      );
      expect(IncidentAgeBucketPolicy.bucketForCreatedAt(null, now), isNull);
      expect(
        IncidentAgeBucketPolicy.bucketForAge(const Duration(milliseconds: -1)),
        isNull,
      );
    });
  });

  group('IncidentMapResponse.fromJson — contract fixtures', () {
    test('point item: bucket/photos/createdAt parse ครบ', () {
      final response = IncidentMapResponse.fromJson({
        'mode': 'points',
        'zoom': 14,
        'truncated': false,
        'legend': {'red': 1, 'orange': 0, 'gold': 0, 'gray': 0, 'black': 0},
        'excluded': {'noUsableCoordinate': 2, 'invalidTime': 1},
        'items': [
          {
            'kind': 'point',
            'id': 'v1',
            'categoryId': 'c1',
            'createdAt': '2026-10-06T11:00:00.000Z',
            'bucket': 'red',
            'lat': 13.7,
            'lng': 100.5,
            'photos': [
              {
                'id': 'p1',
                'url': 'http://x/p1.jpg',
                'createdAt': '2026-10-06T11:00:00.000Z',
              },
            ],
          },
        ],
        'nextCursor': 'abc',
      });

      expect(response.mode, IncidentMapMode.points);
      expect(response.legend.total, 1);
      expect(response.excluded.total, 3);
      expect(response.nextCursor, 'abc');
      final point = response.items.single as IncidentMapPointItem;
      expect(point.id, 'v1');
      expect(point.bucket, IncidentAgeBucket.red);
      expect(point.photos.single.url, 'http://x/p1.jpg');
    });

    test('cluster item: byBucket parse ตามชื่อ bucket', () {
      final response = IncidentMapResponse.fromJson({
        'mode': 'clusters',
        'zoom': 5,
        'legend': {'red': 0, 'orange': 1, 'gold': 2, 'gray': 3, 'black': 0},
        'excluded': {'noUsableCoordinate': 0, 'invalidTime': 0},
        'items': [
          {
            'kind': 'cluster',
            'lat': 15.0,
            'lng': 101.0,
            'count': 6,
            'byBucket': {'orange': 1, 'gold': 2, 'gray': 3},
          },
        ],
      });

      final cluster = response.items.single as IncidentMapClusterItem;
      expect(cluster.count, 6);
      expect(cluster.zoom, 5);
      expect(cluster.gridBounds.south, 11.25);
      expect(cluster.gridBounds.west, 95.625);
      expect(cluster.gridBounds.contains(15.0, 101.0), isTrue);
      expect(cluster.byBucket[IncidentAgeBucket.orange], 1);
      expect(cluster.byBucket[IncidentAgeBucket.gold], 2);
      expect(cluster.byBucket[IncidentAgeBucket.gray], 3);
    });

    test('ข้อมูลเสียหาย (lat/lng หาย, bucket ไม่รู้จัก) ถูกข้าม ไม่ crash', () {
      final response = IncidentMapResponse.fromJson({
        'mode': 'points',
        'zoom': 14,
        'legend': {},
        'excluded': {},
        'items': [
          {'kind': 'point', 'id': 'v1', 'bucket': 'red'}, // no lat/lng
          {
            'kind': 'point',
            'id': 'v2',
            'lat': 1,
            'lng': 2,
            'bucket': 'magenta',
          },
          {'kind': 'unknown'},
        ],
      });
      expect(response.items, isEmpty);
    });
  });

  group('IncidentMapZoomPolicy', () {
    test('cluster taps zoom in and stop at the point threshold', () {
      expect(IncidentMapZoomPolicy.zoomAfterClusterTap(5.5), 7.5);
      expect(IncidentMapZoomPolicy.zoomAfterClusterTap(11), 12);
      expect(IncidentMapZoomPolicy.zoomAfterClusterTap(12), 12);
    });

    test('map return focuses the selected point at photo overview zoom', () {
      final point = IncidentMapPointItem(
        lat: 13.75,
        lng: 100.5,
        id: 'incident-1',
        categoryId: 'category-1',
        createdAt: DateTime.utc(2026, 10, 6),
        bucket: IncidentAgeBucket.red,
        photos: const [
          IncidentMapPhoto(id: 'photo-1', url: 'https://example.test/1'),
        ],
      );

      final focus = IncidentMapCameraFocus.forPoint(point);
      expect(focus.incidentId, point.id);
      expect(focus.latitude, point.lat);
      expect(focus.longitude, point.lng);
      expect(focus.zoom, IncidentMapZoomPolicy.photoOverviewZoom);
      expect(
        focus.zoom,
        greaterThanOrEqualTo(IncidentMapZoomPolicy.photoPreviewThreshold),
      );
    });
  });

  group('IncidentMapPhoto blur status (§22.19)', () {
    test('completed photo is ready and keeps its url', () {
      final photo = IncidentMapPhoto.fromJson({
        'id': 'p1',
        'url': 'https://example.test/1',
        'blurStatus': 'completed',
      });
      expect(photo.isPending, isFalse);
      expect(photo.blurStatus, 'completed');
    });

    test('blurring photo keeps its slot but is pending with no url', () {
      final photo = IncidentMapPhoto.fromJson({
        'id': 'p2',
        'url': '',
        'blurStatus': 'blurring',
      });
      expect(photo.isPending, isTrue);
      expect(photo.blurStatus, 'blurring');
    });

    test('missing blurStatus defaults to completed (older server payload)', () {
      final photo = IncidentMapPhoto.fromJson({
        'id': 'p3',
        'url': 'https://example.test/3',
      });
      expect(photo.blurStatus, 'completed');
      expect(photo.isPending, isFalse);
    });
  });

  group('gallery photo page resolution', () {
    test(
      'finds the photo and absolute index within a bounded page scan',
      () async {
        final requestedPages = <int>[];
        final result = await VideoRepository.resolveThaiMhungGalleryPhotoPages(
          photoId: 'p4',
          limit: 3,
          loadPage: (page, limit) async {
            requestedPages.add(page);
            if (page == 1) {
              return List.generate(
                limit,
                (index) => <String, dynamic>{'id': 'p${index + 1}'},
              );
            }
            return [
              <String, dynamic>{'id': 'p4'},
            ];
          },
        );

        expect(result.found, isTrue);
        expect(result.page, 2);
        expect(result.index, 3);
        expect(result.pagesFetched, 2);
        expect(result.photos.last['id'], 'p4');
        expect(requestedPages, [1, 2]);
      },
    );

    test('stops at maxPages when the target cannot be resolved', () async {
      final requestedPages = <int>[];
      final result = await VideoRepository.resolveThaiMhungGalleryPhotoPages(
        photoId: 'missing',
        limit: 2,
        maxPages: 2,
        loadPage: (page, limit) async {
          requestedPages.add(page);
          return List.generate(
            limit,
            (index) => <String, dynamic>{'id': '$page-$index'},
          );
        },
      );

      expect(result.found, isFalse);
      expect(result.index, isNull);
      expect(result.pagesFetched, 2);
      expect(result.photos, hasLength(4));
      expect(result.hasMore, isTrue);
      expect(requestedPages, [1, 2]);
    });
  });

  group('IncidentMapBounds', () {
    test('thailand bounds ครอบคลุมประเทศและ serialize ตรง format', () {
      expect(IncidentMapBounds.thailand.contains(13.7, 100.5), isTrue);
      expect(IncidentMapBounds.thailand.contains(5.0, 100.0), isFalse);
      expect(IncidentMapBounds.thailand.toQueryParam(), '5.5,97.5,20.5,105.5');
    });
  });

  group('resolveIncidentPointTap — แตะหมุดโฟกัสวงภาพก่อน (§22.3.4)', () {
    IncidentPointTapAction call({
      int photoCount = 3,
      double? cameraZoom = 11,
      bool ringPlaced = false,
      double? anchorCenterDistance = 300,
      double viewportShortestSide = 390,
    }) => resolveIncidentPointTap(
      photoCount: photoCount,
      cameraZoom: cameraZoom,
      ringPlaced: ringPlaced,
      anchorCenterDistance: anchorCenterDistance,
      viewportShortestSide: viewportShortestSide,
    );

    test('หมุดไม่มีภาพ → เล่นทันที ไม่ว่าสถานะกล้องไหน', () {
      expect(call(photoCount: 0), IncidentPointTapAction.playIncident);
      expect(
        call(photoCount: 0, cameraZoom: null, anchorCenterDistance: null),
        IncidentPointTapAction.playIncident,
      );
    });

    test('วงภาพถูกวางครบบนจอแล้ว → เล่นทันที', () {
      expect(
        call(ringPlaced: true, cameraZoom: 14),
        IncidentPointTapAction.playIncident,
      );
    });

    test('zoom ต่ำกว่า threshold + มีภาพ → focus วงภาพ', () {
      expect(call(cameraZoom: 11), IncidentPointTapAction.focusPhotoRing);
      expect(
        call(cameraZoom: 12.9),
        IncidentPointTapAction.focusPhotoRing,
      );
    });

    test('zoom ผ่าน threshold แต่หมุดชิดขอบจอ (วงยังไม่ลง) → focus', () {
      expect(
        call(cameraZoom: 14, anchorCenterDistance: 300),
        IncidentPointTapAction.focusPhotoRing,
      );
    });

    test('หมุดกลางจอ + zoom ผ่านแล้วแต่วงยังวางไม่ลง → เล่น (escape)', () {
      expect(
        call(
          cameraZoom: 15,
          anchorCenterDistance: 390 * 0.2, // ใต้เพดาน 0.25 × shortestSide
        ),
        IncidentPointTapAction.playIncident,
      );
    });

    test('zoom ผ่านแล้วแต่ projector ยังไม่พร้อม (anchor null) → focus', () {
      expect(
        call(cameraZoom: 14, anchorCenterDistance: null),
        IncidentPointTapAction.focusPhotoRing,
      );
    });

    test('photoFocusZoom ไม่ซูมออกเมื่ออยู่ลึกกว่า overview', () {
      expect(
        IncidentMapZoomPolicy.photoFocusZoom(11),
        IncidentMapZoomPolicy.photoOverviewZoom,
      );
      expect(IncidentMapZoomPolicy.photoFocusZoom(18), 18);
    });
  });

  group('IncidentMapBounds.clamped — กัน 400 จาก viewport เกินช่วง (§22.20)', () {
    test('ค่าในช่วง → คงเดิม', () {
      const b = IncidentMapBounds(
        south: 5,
        west: 97,
        north: 20,
        east: 105,
      );
      final c = b.clamped();
      expect(c.south, 5);
      expect(c.west, 97);
      expect(c.north, 20);
      expect(c.east, 105);
    });

    test('lat/lng เกินช่วง → clamp เป็น ±90/±180', () {
      final c = const IncidentMapBounds(
        south: -95,
        west: -200,
        north: 95,
        east: 200,
      ).clamped();
      expect(c.south, -90);
      expect(c.west, -180);
      expect(c.north, 90);
      expect(c.east, 180);
    });

    test('คร่อม antimeridian (west > east) → กว้างเต็มแกน lng', () {
      final c = const IncidentMapBounds(
        south: 10,
        west: 170,
        north: 20,
        east: -170,
      ).clamped();
      expect(c.west, -180);
      expect(c.east, 180);
      expect(c.south, 10);
      expect(c.north, 20);
    });

    test('south > north → สลับให้ถูกลำดับ', () {
      final c = const IncidentMapBounds(
        south: 20,
        west: 97,
        north: 10,
        east: 105,
      ).clamped();
      expect(c.south, 10);
      expect(c.north, 20);
    });
  });
}
