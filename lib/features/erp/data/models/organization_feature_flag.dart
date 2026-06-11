/// Model สำหรับ organization_feature_flags
class OrganizationFeatureFlag {
  final String id;
  final String professionId;
  final String featureName;
  final String status; // enabled, disabled, beta, deprecated
  final String? updatedBy;
  final DateTime updatedAt;
  final DateTime createdAt;

  const OrganizationFeatureFlag({
    required this.id,
    required this.professionId,
    required this.featureName,
    required this.status,
    this.updatedBy,
    required this.updatedAt,
    required this.createdAt,
  });

  factory OrganizationFeatureFlag.fromJson(Map<String, dynamic> json) {
    return OrganizationFeatureFlag(
      id: json['id'] as String,
      professionId: json['profession_id'] as String,
      featureName: json['feature_name'] as String,
      status: json['status'] as String,
      updatedBy: json['updated_by'] as String?,
      updatedAt: DateTime.parse(json['updated_at'] as String),
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'profession_id': professionId,
      'feature_name': featureName,
      'status': status,
      'updated_by': updatedBy,
      'updated_at': updatedAt.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
    };
  }

  bool get isEnabled => status == 'enabled';
  bool get isDisabled => status == 'disabled';
  bool get isBeta => status == 'beta';

  OrganizationFeatureFlag copyWith({
    String? id,
    String? professionId,
    String? featureName,
    String? status,
    String? updatedBy,
    DateTime? updatedAt,
    DateTime? createdAt,
  }) {
    return OrganizationFeatureFlag(
      id: id ?? this.id,
      professionId: professionId ?? this.professionId,
      featureName: featureName ?? this.featureName,
      status: status ?? this.status,
      updatedBy: updatedBy ?? this.updatedBy,
      updatedAt: updatedAt ?? this.updatedAt,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
