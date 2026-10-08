/// Admin-tunable 3D visual parameters for the Court Card glass slab.
///
/// These values are presented as sliders and toggles on the "รูปแบบการ์ด" tab
/// and persisted alongside the card style in `app_settings`.
class CourtCard3DParams {
  /// Card Y-axis rotation in radians (องศาการ์ด).  Negative = rotated left (right edge recedes).
  final double rotateY;

  /// Card X-axis rotation in radians (ความเอียง).  Positive = tilted back.
  final double rotateX;

  /// Slab extrusion thickness in logical pixels (ความหนา).
  final double thickness;

  /// Front-face opacity 0..1 (ความโปร่งใส).  Lower = more translucent/glassy.
  final double opacity;

  /// Light angle in radians controlling specular sheen direction (มุมแสง).
  final double lightAngle;

  /// Whether to show the 3D cube icon (เปิด/ปิด ไอคอน 3 มิติ).
  final bool show3dIcon;

  /// Custom replacement image URL, file path, base64 or preset key (รูปภาพที่เลือกแทน).
  final String? customImageUrl;

  /// Shadow horizontal spread/width multiplier (รัศมีความกว้างเงาแนวนอน).
  /// 1.0 = standard width.
  final double shadowWidthFactor;

  /// Shadow vertical spread/height multiplier (ความยาวเงาแนวตั้ง).
  /// 1.0 = standard length.
  final double shadowHeightFactor;

  /// Shadow overall intensity / opacity multiplier (ความเข้มเงา).
  /// 1.0 = standard opacity.
  final double shadowOpacity;

  const CourtCard3DParams({
    this.rotateY = -0.10,
    this.rotateX = 0.05,
    this.thickness = 12.0,
    this.opacity = 0.38,
    this.lightAngle = 0.75,
    this.show3dIcon = true,
    this.customImageUrl,
    this.shadowWidthFactor = 1.0,
    this.shadowHeightFactor = 1.0,
    this.shadowOpacity = 1.0,
  });

  static const CourtCard3DParams defaults = CourtCard3DParams();

  CourtCard3DParams copyWith({
    double? rotateY,
    double? rotateX,
    double? thickness,
    double? opacity,
    double? lightAngle,
    bool? show3dIcon,
    String? customImageUrl,
    bool clearCustomImage = false,
    double? shadowWidthFactor,
    double? shadowHeightFactor,
    double? shadowOpacity,
  }) {
    return CourtCard3DParams(
      rotateY: rotateY ?? this.rotateY,
      rotateX: rotateX ?? this.rotateX,
      thickness: thickness ?? this.thickness,
      opacity: opacity ?? this.opacity,
      lightAngle: lightAngle ?? this.lightAngle,
      show3dIcon: show3dIcon ?? this.show3dIcon,
      customImageUrl: clearCustomImage
          ? null
          : (customImageUrl ?? this.customImageUrl),
      shadowWidthFactor: shadowWidthFactor ?? this.shadowWidthFactor,
      shadowHeightFactor: shadowHeightFactor ?? this.shadowHeightFactor,
      shadowOpacity: shadowOpacity ?? this.shadowOpacity,
    );
  }

  Map<String, dynamic> toJson() => {
        'rotateY': rotateY,
        'rotateX': rotateX,
        'thickness': thickness,
        'opacity': opacity,
        'lightAngle': lightAngle,
        'show3dIcon': show3dIcon,
        if (customImageUrl != null) 'customImageUrl': customImageUrl,
        'shadowWidthFactor': shadowWidthFactor,
        'shadowHeightFactor': shadowHeightFactor,
        'shadowOpacity': shadowOpacity,
      };

  factory CourtCard3DParams.fromJson(Object? json) {
    if (json is! Map) return defaults;
    return CourtCard3DParams(
      rotateY: _d(json['rotateY'], defaults.rotateY),
      rotateX: _d(json['rotateX'], defaults.rotateX),
      thickness: _d(json['thickness'], defaults.thickness),
      opacity: _d(json['opacity'], defaults.opacity),
      lightAngle: _d(json['lightAngle'], defaults.lightAngle),
      show3dIcon: json['show3dIcon'] is bool
          ? json['show3dIcon'] as bool
          : defaults.show3dIcon,
      customImageUrl: json['customImageUrl']?.toString(),
      shadowWidthFactor: _d(
        json['shadowWidthFactor'],
        defaults.shadowWidthFactor,
      ),
      shadowHeightFactor: _d(
        json['shadowHeightFactor'],
        defaults.shadowHeightFactor,
      ),
      shadowOpacity: _d(
        json['shadowOpacity'],
        defaults.shadowOpacity,
      ),
    );
  }

  static double _d(Object? v, double fallback) {
    if (v is num) return v.toDouble();
    return fallback;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CourtCard3DParams &&
          rotateY == other.rotateY &&
          rotateX == other.rotateX &&
          thickness == other.thickness &&
          opacity == other.opacity &&
          lightAngle == other.lightAngle &&
          show3dIcon == other.show3dIcon &&
          customImageUrl == other.customImageUrl &&
          shadowWidthFactor == other.shadowWidthFactor &&
          shadowHeightFactor == other.shadowHeightFactor &&
          shadowOpacity == other.shadowOpacity;

  @override
  int get hashCode => Object.hash(
        rotateY,
        rotateX,
        thickness,
        opacity,
        lightAngle,
        show3dIcon,
        customImageUrl,
        shadowWidthFactor,
        shadowHeightFactor,
        shadowOpacity,
      );
}
