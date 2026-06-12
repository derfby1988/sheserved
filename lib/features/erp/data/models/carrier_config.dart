/// Model สำหรับ carrier_configs (Delivery Extension — 3PL settings)
class CarrierConfig {
  final String id;
  final String professionId;
  final String carrierCode; // kerry, flash, j&t, etc.
  final String carrierName;
  final String carrierType; // 3pl, own_fleet, platform, drop_off
  final String? apiEndpoint;
  final String? apiKey;
  final bool isActive;
  final double baseRate;
  final double perKgRate;
  final double codFeeRate;
  final String? contactPhone;
  final String? contactEmail;
  final DateTime createdAt;
  final DateTime updatedAt;

  const CarrierConfig({
    required this.id,
    required this.professionId,
    required this.carrierCode,
    required this.carrierName,
    this.carrierType = '3pl',
    this.apiEndpoint,
    this.apiKey,
    this.isActive = true,
    this.baseRate = 0,
    this.perKgRate = 0,
    this.codFeeRate = 0,
    this.contactPhone,
    this.contactEmail,
    required this.createdAt,
    required this.updatedAt,
  });

  factory CarrierConfig.fromJson(Map<String, dynamic> json) {
    return CarrierConfig(
      id: json['id'] as String,
      professionId: json['profession_id'] as String,
      carrierCode: json['carrier_code'] as String,
      carrierName: json['carrier_name'] as String,
      carrierType: json['carrier_type'] as String? ?? '3pl',
      apiEndpoint: json['api_endpoint'] as String?,
      apiKey: json['api_key'] as String?,
      isActive: json['is_active'] as bool? ?? true,
      baseRate: (json['base_rate'] as num?)?.toDouble() ?? 0,
      perKgRate: (json['per_kg_rate'] as num?)?.toDouble() ?? 0,
      codFeeRate: (json['cod_fee_rate'] as num?)?.toDouble() ?? 0,
      contactPhone: json['contact_phone'] as String?,
      contactEmail: json['contact_email'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'profession_id': professionId,
      'carrier_code': carrierCode,
      'carrier_name': carrierName,
      'carrier_type': carrierType,
      'api_endpoint': apiEndpoint,
      'api_key': apiKey,
      'is_active': isActive,
      'base_rate': baseRate,
      'per_kg_rate': perKgRate,
      'cod_fee_rate': codFeeRate,
      'contact_phone': contactPhone,
      'contact_email': contactEmail,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}
