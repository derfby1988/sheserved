/// A single anatomical landmark for multi-point body region calibration.
///
/// Maps a point on the 2D silhouette (y2d, x2d) to its corresponding
/// position on the 3D model viewport (y3d, x3d).
///
/// Landmarks are stored as JSONB and are expandable (not fixed to 7 points).
class BodyLandmark {
  final int id;
  final String name;
  final String? nameEn;

  /// 2D silhouette vertical ratio (0.0 = top, 1.0 = bottom)
  final double y2d;

  /// 3D model viewport vertical ratio (0.0 = top, 1.0 = bottom)
  final double y3d;

  /// 2D silhouette horizontal ratio (0.0 = left, 1.0 = right, 0.5 = center)
  final double x2d;

  /// 3D model viewport horizontal ratio (0.0 = left, 1.0 = right, 0.5 = center)
  final double x3d;

  /// Whether this landmark was auto-detected from the 3D model
  /// (admin may want to review/tune these).
  final bool autoDetected;

  const BodyLandmark({
    required this.id,
    required this.name,
    this.nameEn,
    required this.y2d,
    required this.y3d,
    this.x2d = 0.5,
    this.x3d = 0.5,
    this.autoDetected = false,
  });

  factory BodyLandmark.fromJson(Map<String, dynamic> json) {
    double parseDouble(dynamic value, [double defaultValue = 0.0]) {
      if (value == null) return defaultValue;
      if (value is num) return value.toDouble();
      if (value is String) return double.tryParse(value) ?? defaultValue;
      return defaultValue;
    }

    int parseInt(dynamic value, [int defaultValue = 0]) {
      if (value == null) return defaultValue;
      if (value is int) return value;
      if (value is double) return value.toInt();
      if (value is String) return int.tryParse(value) ?? defaultValue;
      return defaultValue;
    }

    return BodyLandmark(
      id: parseInt(json['id']),
      name: json['name'] as String? ?? '',
      nameEn: json['nameEn'] as String? ?? json['name_en'] as String?,
      y2d: parseDouble(json['y2d'], 0.0),
      y3d: parseDouble(json['y3d'], 0.0),
      x2d: parseDouble(json['x2d'], 0.5),
      x3d: parseDouble(json['x3d'], 0.5),
      autoDetected: json['autoDetected'] == true || json['auto_detected'] == true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      if (nameEn != null) 'nameEn': nameEn,
      'y2d': y2d,
      'y3d': y3d,
      'x2d': x2d,
      'x3d': x3d,
      'autoDetected': autoDetected,
    };
  }

  BodyLandmark copyWith({
    int? id,
    String? name,
    String? nameEn,
    double? y2d,
    double? y3d,
    double? x2d,
    double? x3d,
    bool? autoDetected,
  }) {
    return BodyLandmark(
      id: id ?? this.id,
      name: name ?? this.name,
      nameEn: nameEn ?? this.nameEn,
      y2d: y2d ?? this.y2d,
      y3d: y3d ?? this.y3d,
      x2d: x2d ?? this.x2d,
      x3d: x3d ?? this.x3d,
      autoDetected: autoDetected ?? this.autoDetected,
    );
  }

  @override
  String toString() =>
      'BodyLandmark(id:$id, name:$name, y2d:$y2d, y3d:$y3d, x2d:$x2d, x3d:$x3d)';
}
