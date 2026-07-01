import 'body_landmark_model.dart';

class BodyRegionModel {
  final String id;
  final String nameTh;
  final String nameEn;
  final double yRatio;
  final double xRatio;
  final String? iconName;
  final bool hasSides;
  final String gender;
  final String? iconImageUrl; // Custom icon image URL (PNG)
  final String? image2dUrl;
  final String? model3dUrl;
  final String? colorHex; // New field for custom color
  final double modelTopRatio;    // 3D model top calibration (default 0.08)
  final double modelBottomRatio; // 3D model bottom calibration (default 0.93)
  final int displayOrder;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  // ─── v2.0 Multi-Point Calibration ──────────────────────────────────────
  /// Optional per-region landmark override. When null, global defaults
  /// from [body_region_calibration_defaults] are used.
  final List<BodyLandmark>? landmarks;

  /// Target gender for calibration lookup (male/female/both).
  final String calibrationGender;

  /// Target platform for calibration lookup (mobile/web/tablet/universal).
  final String calibrationPlatform;

  const BodyRegionModel({
    required this.id,
    required this.nameTh,
    required this.nameEn,
    required this.yRatio,
    this.xRatio = 0.50,
    this.iconName,
    this.hasSides = false,
    this.gender = 'both',
    this.iconImageUrl,
    this.image2dUrl,
    this.model3dUrl,
    this.colorHex,
    this.modelTopRatio = 0.08,
    this.modelBottomRatio = 0.93,
    this.displayOrder = 0,
    this.createdAt,
    this.updatedAt,
    this.landmarks,
    this.calibrationGender = 'both',
    this.calibrationPlatform = 'universal',
  });

  factory BodyRegionModel.fromJson(Map<String, dynamic> json) {
    double parseDouble(dynamic value, [double defaultValue = 0.0]) {
      if (value == null) return defaultValue;
      if (value is num) return value.toDouble();
      if (value is String) return double.tryParse(value) ?? defaultValue;
      return defaultValue;
    }

    int parseInt(dynamic value) {
      if (value == null) return 0;
      if (value is int) return value;
      if (value is double) return value.toInt();
      if (value is String) return int.tryParse(value) ?? 0;
      return 0;
    }

    return BodyRegionModel(
      id: json['id'] as String? ?? '',
      nameTh: json['name_th'] as String? ?? '',
      nameEn: json['name_en'] as String? ?? '',
      yRatio: parseDouble(json['y_ratio']),
      xRatio: parseDouble(json['x_ratio'], 0.50),
      iconName: json['icon_name'] as String?,
      hasSides: json['has_sides'] == true,
      gender: json['gender'] as String? ?? 'both',
      iconImageUrl: json['icon_image_url'] as String?,
      image2dUrl: json['image_2d_url'] as String?,
      model3dUrl: json['model_3d_url'] as String?,
      colorHex: json['color_hex'] as String?,
      modelTopRatio: parseDouble(json['model_top_ratio'], 0.08),
      modelBottomRatio: parseDouble(json['model_bottom_ratio'], 0.93),
      displayOrder: parseInt(json['display_order']),
      landmarks: _parseLandmarks(json['landmarks']),
      calibrationGender: json['calibration_gender'] as String? ?? 'both',
      calibrationPlatform: json['calibration_platform'] as String? ?? 'universal',
      createdAt: json['created_at'] != null ? DateTime.tryParse(json['created_at'].toString()) : null,
      updatedAt: json['updated_at'] != null ? DateTime.tryParse(json['updated_at'].toString()) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name_th': nameTh,
      'name_en': nameEn,
      'y_ratio': yRatio,
      'x_ratio': xRatio,
      'icon_name': iconName,
      'has_sides': hasSides,
      'gender': gender,
      'icon_image_url': iconImageUrl,
      'image_2d_url': image2dUrl,
      'model_3d_url': model3dUrl,
      'color_hex': colorHex,
      'model_top_ratio': modelTopRatio,
      'model_bottom_ratio': modelBottomRatio,
      'display_order': displayOrder,
      if (landmarks != null)
        'landmarks': landmarks!.map((l) => l.toJson()).toList(),
      'calibration_gender': calibrationGender,
      'calibration_platform': calibrationPlatform,
    };
  }

  BodyRegionModel copyWith({
    String? id,
    String? nameTh,
    String? nameEn,
    double? yRatio,
    double? xRatio,
    String? iconName,
    bool? hasSides,
    String? gender,
    String? iconImageUrl,
    String? image2dUrl,
    String? model3dUrl,
    String? colorHex,
    double? modelTopRatio,
    double? modelBottomRatio,
    int? displayOrder,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<BodyLandmark>? landmarks,
    String? calibrationGender,
    String? calibrationPlatform,
  }) {
    return BodyRegionModel(
      id: id ?? this.id,
      nameTh: nameTh ?? this.nameTh,
      nameEn: nameEn ?? this.nameEn,
      yRatio: yRatio ?? this.yRatio,
      xRatio: xRatio ?? this.xRatio,
      iconName: iconName ?? this.iconName,
      hasSides: hasSides ?? this.hasSides,
      gender: gender ?? this.gender,
      iconImageUrl: iconImageUrl ?? this.iconImageUrl,
      image2dUrl: image2dUrl ?? this.image2dUrl,
      model3dUrl: model3dUrl ?? this.model3dUrl,
      colorHex: colorHex ?? this.colorHex,
      modelTopRatio: modelTopRatio ?? this.modelTopRatio,
      modelBottomRatio: modelBottomRatio ?? this.modelBottomRatio,
      displayOrder: displayOrder ?? this.displayOrder,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      landmarks: landmarks ?? this.landmarks,
      calibrationGender: calibrationGender ?? this.calibrationGender,
      calibrationPlatform: calibrationPlatform ?? this.calibrationPlatform,
    );
  }

  static List<BodyLandmark>? _parseLandmarks(dynamic value) {
    if (value == null) return null;
    if (value is List) {
      return value
          .whereType<Map<String, dynamic>>()
          .map((e) => BodyLandmark.fromJson(e))
          .toList();
    }
    return null;
  }
}
