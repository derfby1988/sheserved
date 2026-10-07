import 'package:flutter/material.dart';

/// Incident Overview Map models (VIDEO_SYSTEM_PLAN.md §22)
///
/// Contract mirror of `websocket-server/services/incident-map.js`:
///   * age buckets are contiguous — red ≤24h, orange >24h–7d, gold >7d–35d,
///     gray >35d–365d, black >365d (elapsed from `created_at`, UTC)
///   * future/invalid timestamps are never bucketed (excluded counters)
///   * zoom ≥ 12 → points, zoom < 12 → clusters (server decides)

/// Age bucket of an incident, keyed exactly like the server payload.
enum IncidentAgeBucket { red, orange, gold, gray, black }

extension IncidentAgeBucketX on IncidentAgeBucket {
  static IncidentAgeBucket? fromName(String? name) => switch (name) {
    'red' => IncidentAgeBucket.red,
    'orange' => IncidentAgeBucket.orange,
    'gold' => IncidentAgeBucket.gold,
    'gray' => IncidentAgeBucket.gray,
    'black' => IncidentAgeBucket.black,
    _ => null,
  };

  /// Marker fill — ขอบขาวเสมอเพื่อคุม contrast บน tile เข้ม (§22.3.7)
  Color get color => switch (this) {
    IncidentAgeBucket.red => const Color(0xFFE53935),
    IncidentAgeBucket.orange => const Color(0xFFFF6B35),
    IncidentAgeBucket.gold => const Color(0xFFD4A017),
    IncidentAgeBucket.gray => const Color(0xFF8E8E93),
    IncidentAgeBucket.black => const Color(0xFF1C1C1E),
  };

  /// Legend label — อ่านอายุได้โดยไม่พึ่งสีเดียว (§22.3.7)
  String get labelTh => switch (this) {
    IncidentAgeBucket.red => 'ไม่เกิน 24 ชม.',
    IncidentAgeBucket.orange => '1–7 วัน',
    IncidentAgeBucket.gold => '1–5 สัปดาห์',
    IncidentAgeBucket.gray => '1–12 เดือน',
    IncidentAgeBucket.black => 'เกิน 1 ปี',
  };

  /// Relative-time text for preview cards / semantics (§22.3.7)
  String relativeAgeTh(Duration age) {
    if (age.inMinutes < 60) return '${age.inMinutes.clamp(0, 59)} นาที';
    if (age.inHours < 24) return '${age.inHours} ชั่วโมง';
    if (age.inDays < 7) return '${age.inDays} วัน';
    if (age.inDays < 35) return '${(age.inDays / 7).floor()} สัปดาห์';
    if (age.inDays < 365) return '${(age.inDays / 30).floor()} เดือน';
    return '${(age.inDays / 365).floor()} ปี';
  }
}

/// Bucket boundaries in ms — single source for tests and the legend.
class IncidentAgeBucketPolicy {
  static const int hourMs = 3_600_000;
  static const int dayMs = 24 * hourMs;

  /// Upper bound (inclusive) of each bucket in age-ms order
  /// [red, orange, gold, gray]; beyond the last → black.
  static const List<int> boundsMs = [
    24 * hourMs,
    7 * dayMs,
    35 * dayMs,
    365 * dayMs,
  ];

  static IncidentAgeBucket? bucketForAge(Duration age) {
    if (age.inMilliseconds < 0) return null;
    final ms = age.inMilliseconds;
    for (var i = 0; i < boundsMs.length; i++) {
      if (ms <= boundsMs[i]) return IncidentAgeBucket.values[i];
    }
    return IncidentAgeBucket.black;
  }

  /// null when the timestamp is missing/unparseable/in the future.
  static IncidentAgeBucket? bucketForCreatedAt(
    DateTime? createdAt,
    DateTime now,
  ) {
    if (createdAt == null) return null;
    final age = now.difference(createdAt);
    if (age.isNegative) return null;
    return bucketForAge(age);
  }
}

/// Viewport bounds — `south,west,north,east` on the wire.
class IncidentMapBounds {
  final double south;
  final double west;
  final double north;
  final double east;

  const IncidentMapBounds({
    required this.south,
    required this.west,
    required this.north,
    required this.east,
  });

  /// ครอบคลุมประเทศไทยทั้งประเทศ (มุมมองแรกของโหมดแผนที่ — §22.1)
  static const IncidentMapBounds thailand = IncidentMapBounds(
    south: 5.5,
    west: 97.5,
    north: 20.5,
    east: 105.5,
  );

  bool contains(double lat, double lng) =>
      lat >= south && lat <= north && lng >= west && lng <= east;

  String toQueryParam() => '$south,$west,$north,$east';

  @override
  String toString() => 'IncidentMapBounds($toQueryParam)';
}

class IncidentMapPhoto {
  final String id;
  final String url;
  final DateTime? createdAt;

  const IncidentMapPhoto({required this.id, required this.url, this.createdAt});

  factory IncidentMapPhoto.fromJson(Map<String, dynamic> json) =>
      IncidentMapPhoto(
        id: json['id']?.toString() ?? '',
        url: json['url']?.toString() ?? '',
        createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? ''),
      );
}

/// One marker on the map — a server cluster (zoom < 12) or a single incident
/// point (zoom ≥ 12). Sealed so the renderer can switch exhaustively.
sealed class IncidentMapItem {
  final double lat;
  final double lng;

  const IncidentMapItem({required this.lat, required this.lng});
}

class IncidentMapClusterItem extends IncidentMapItem {
  final int count;
  final int zoom;
  final Map<IncidentAgeBucket, int> byBucket;

  const IncidentMapClusterItem({
    required super.lat,
    required super.lng,
    required this.count,
    required this.zoom,
    required this.byBucket,
  });

  IncidentMapBounds get gridBounds {
    const maxMercatorLatitude = 85.05112878;
    final safeZoom = zoom.clamp(0, 22).toInt();
    final cellSize = 180 / (1 << safeZoom);
    final south = (lat / cellSize).floor() * cellSize;
    final west = (lng / cellSize).floor() * cellSize;
    return IncidentMapBounds(
      south: south.clamp(-maxMercatorLatitude, maxMercatorLatitude).toDouble(),
      west: west.clamp(-180.0, 180.0).toDouble(),
      north: (south + cellSize)
          .clamp(-maxMercatorLatitude, maxMercatorLatitude)
          .toDouble(),
      east: (west + cellSize).clamp(-180.0, 180.0).toDouble(),
    );
  }
}

class IncidentMapPointItem extends IncidentMapItem {
  final String id;
  final String categoryId;
  final DateTime createdAt;
  final IncidentAgeBucket bucket;
  final List<IncidentMapPhoto> photos;

  const IncidentMapPointItem({
    required super.lat,
    required super.lng,
    required this.id,
    required this.categoryId,
    required this.createdAt,
    required this.bucket,
    this.photos = const [],
  });

  /// Relative age text for semantics/preview (§22.3.7)
  String relativeAgeTh(DateTime now) =>
      bucket.relativeAgeTh(now.difference(createdAt));
}

class IncidentMapCameraFocus {
  final String incidentId;
  final double latitude;
  final double longitude;
  final double zoom;

  const IncidentMapCameraFocus({
    required this.incidentId,
    required this.latitude,
    required this.longitude,
    required this.zoom,
  });

  factory IncidentMapCameraFocus.forPoint(IncidentMapPointItem point) =>
      IncidentMapCameraFocus(
        incidentId: point.id,
        latitude: point.lat,
        longitude: point.lng,
        zoom: IncidentMapZoomPolicy.photoOverviewZoom,
      );
}

class IncidentMapLegend {
  final int red;
  final int orange;
  final int gold;
  final int gray;
  final int black;

  const IncidentMapLegend({
    this.red = 0,
    this.orange = 0,
    this.gold = 0,
    this.gray = 0,
    this.black = 0,
  });

  int get total => red + orange + gold + gray + black;

  int countOf(IncidentAgeBucket bucket) => switch (bucket) {
    IncidentAgeBucket.red => red,
    IncidentAgeBucket.orange => orange,
    IncidentAgeBucket.gold => gold,
    IncidentAgeBucket.gray => gray,
    IncidentAgeBucket.black => black,
  };

  factory IncidentMapLegend.fromJson(Map<String, dynamic> json) {
    int n(dynamic v) => (v is num) ? v.toInt() : 0;
    return IncidentMapLegend(
      red: n(json['red']),
      orange: n(json['orange']),
      gold: n(json['gold']),
      gray: n(json['gray']),
      black: n(json['black']),
    );
  }
}

class IncidentMapExcluded {
  final int noUsableCoordinate;
  final int invalidTime;

  const IncidentMapExcluded({
    this.noUsableCoordinate = 0,
    this.invalidTime = 0,
  });

  int get total => noUsableCoordinate + invalidTime;

  factory IncidentMapExcluded.fromJson(Map<String, dynamic> json) {
    int n(dynamic v) => (v is num) ? v.toInt() : 0;
    return IncidentMapExcluded(
      noUsableCoordinate: n(json['noUsableCoordinate']),
      invalidTime: n(json['invalidTime']),
    );
  }
}

enum IncidentMapMode { points, clusters }

class IncidentMapZoomPolicy {
  static const double pointsThreshold = 12;
  static const double photoPreviewThreshold = 13;
  static const double photoOverviewZoom = photoPreviewThreshold + 1;
  static const double clusterTapStep = 2;

  static double zoomAfterClusterTap(double currentZoom) {
    final safeZoom = currentZoom.isFinite ? currentZoom : 5.5;
    return (safeZoom + clusterTapStep).clamp(0.0, pointsThreshold).toDouble();
  }
}

class IncidentMapResponse {
  final IncidentMapMode mode;
  final int zoom;
  final bool truncated;
  final IncidentMapLegend legend;
  final IncidentMapExcluded excluded;
  final List<IncidentMapItem> items;
  final String? nextCursor;

  const IncidentMapResponse({
    required this.mode,
    required this.zoom,
    this.truncated = false,
    required this.legend,
    required this.excluded,
    required this.items,
    this.nextCursor,
  });

  factory IncidentMapResponse.fromJson(Map<String, dynamic> json) {
    final zoom = (json['zoom'] is num) ? (json['zoom'] as num).toInt() : 0;
    final items = <IncidentMapItem>[];
    final rawItems = json['items'];
    if (rawItems is List) {
      for (final raw in rawItems) {
        if (raw is! Map) continue;
        final item = _parseItem(
          Map<String, dynamic>.from(raw),
          responseZoom: zoom,
        );
        if (item != null) items.add(item);
      }
    }
    return IncidentMapResponse(
      mode: json['mode'] == 'clusters'
          ? IncidentMapMode.clusters
          : IncidentMapMode.points,
      zoom: zoom,
      truncated: json['truncated'] == true,
      legend: IncidentMapLegend.fromJson(
        json['legend'] is Map
            ? Map<String, dynamic>.from(json['legend'] as Map)
            : const {},
      ),
      excluded: IncidentMapExcluded.fromJson(
        json['excluded'] is Map
            ? Map<String, dynamic>.from(json['excluded'] as Map)
            : const {},
      ),
      items: items,
      nextCursor: json['nextCursor']?.toString(),
    );
  }

  /// Rows that cannot be placed are dropped by the server — never painted at
  /// (0,0) or with a wrong bucket (§22.1 note).
  static IncidentMapItem? _parseItem(
    Map<String, dynamic> json, {
    required int responseZoom,
  }) {
    final lat = _toDouble(json['lat']);
    final lng = _toDouble(json['lng']);
    if (lat == null ||
        lng == null ||
        !lat.isFinite ||
        !lng.isFinite ||
        lat < -90 ||
        lat > 90 ||
        lng < -180 ||
        lng > 180) {
      return null;
    }
    if (json['kind'] == 'cluster') {
      final byBucket = <IncidentAgeBucket, int>{};
      final raw = json['byBucket'];
      if (raw is Map) {
        for (final e in raw.entries) {
          final bucket = IncidentAgeBucketX.fromName(e.key?.toString());
          if (bucket != null && e.value is num) {
            byBucket[bucket] = (e.value as num).toInt();
          }
        }
      }
      return IncidentMapClusterItem(
        lat: lat,
        lng: lng,
        count: (json['count'] is num) ? (json['count'] as num).toInt() : 0,
        zoom: responseZoom,
        byBucket: byBucket,
      );
    }
    final bucket = IncidentAgeBucketX.fromName(json['bucket']?.toString());
    final id = json['id']?.toString() ?? '';
    if (bucket == null || id.isEmpty) return null;
    final photos = <IncidentMapPhoto>[];
    final rawPhotos = json['photos'];
    if (rawPhotos is List) {
      for (final p in rawPhotos) {
        if (p is Map)
          photos.add(IncidentMapPhoto.fromJson(Map<String, dynamic>.from(p)));
      }
    }
    return IncidentMapPointItem(
      lat: lat,
      lng: lng,
      id: id,
      categoryId: json['categoryId']?.toString() ?? '',
      createdAt:
          DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.now(),
      bucket: bucket,
      photos: photos,
    );
  }

  static double? _toDouble(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }
}
