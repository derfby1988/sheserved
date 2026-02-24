class BodyRegionModel {
  final String id;
  final String nameTh;
  final String nameEn;
  final double yRatio;
  final double xRatio;
  final String? iconName;
  final bool hasSides;
  final String gender;
  final String? image2dUrl;
  final String? model3dUrl;
  final String? colorHex; // New field for custom color
  final int displayOrder;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const BodyRegionModel({
    required this.id,
    required this.nameTh,
    required this.nameEn,
    required this.yRatio,
    this.xRatio = 0.50,
    this.iconName,
    this.hasSides = false,
    this.gender = 'both',
    this.image2dUrl,
    this.model3dUrl,
    this.colorHex,
    this.displayOrder = 0,
    this.createdAt,
    this.updatedAt,
  });

  factory BodyRegionModel.fromJson(Map<String, dynamic> json) {
    return BodyRegionModel(
      id: json['id'] as String,
      nameTh: json['name_th'] as String,
      nameEn: json['name_en'] as String,
      yRatio: (json['y_ratio'] as num).toDouble(),
      xRatio: (json['x_ratio'] as num?)?.toDouble() ?? 0.50,
      iconName: json['icon_name'] as String?,
      hasSides: json['has_sides'] as bool? ?? false,
      gender: json['gender'] as String? ?? 'both',
      image2dUrl: json['image_2d_url'] as String?,
      model3dUrl: json['model_3d_url'] as String?,
      colorHex: json['color_hex'] as String?,
      displayOrder: json['display_order'] as int? ?? 0,
      createdAt: json['created_at'] != null ? DateTime.parse(json['created_at']) : null,
      updatedAt: json['updated_at'] != null ? DateTime.parse(json['updated_at']) : null,
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
      'image_2d_url': image2dUrl,
      'model_3d_url': model3dUrl,
      'color_hex': colorHex,
      'display_order': displayOrder,
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
    String? image2dUrl,
    String? model3dUrl,
    String? colorHex,
    int? displayOrder,
    DateTime? createdAt,
    DateTime? updatedAt,
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
      image2dUrl: image2dUrl ?? this.image2dUrl,
      model3dUrl: model3dUrl ?? this.model3dUrl,
      colorHex: colorHex ?? this.colorHex,
      displayOrder: displayOrder ?? this.displayOrder,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
