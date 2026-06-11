/// Model สำหรับ loyalty_point_rules (CRM Step 5)
class LoyaltyRule {
  final String id;
  final String professionId;
  final String ruleName;
  final double pointsPerBaht;
  final double bonusMultiplier;
  final double minPurchase;
  final String appliesTo; // all, products, services, consultation
  final bool isActive;
  final DateTime? validFrom;
  final DateTime? validUntil;
  final DateTime createdAt;
  final DateTime updatedAt;

  const LoyaltyRule({
    required this.id,
    required this.professionId,
    this.ruleName = 'Default Rule',
    required this.pointsPerBaht,
    this.bonusMultiplier = 1.0,
    this.minPurchase = 0,
    this.appliesTo = 'all',
    this.isActive = true,
    this.validFrom,
    this.validUntil,
    required this.createdAt,
    required this.updatedAt,
  });

  factory LoyaltyRule.fromJson(Map<String, dynamic> json) {
    return LoyaltyRule(
      id: json['id'] as String,
      professionId: json['profession_id'] as String,
      ruleName: json['rule_name'] as String? ?? 'Default Rule',
      pointsPerBaht: (json['points_per_baht'] as num).toDouble(),
      bonusMultiplier: (json['bonus_multiplier'] as num?)?.toDouble() ?? 1.0,
      minPurchase: (json['min_purchase'] as num?)?.toDouble() ?? 0,
      appliesTo: json['applies_to'] as String? ?? 'all',
      isActive: json['is_active'] as bool? ?? true,
      validFrom: json['valid_from'] != null ? DateTime.parse(json['valid_from'] as String) : null,
      validUntil: json['valid_until'] != null ? DateTime.parse(json['valid_until'] as String) : null,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'profession_id': professionId,
      'rule_name': ruleName,
      'points_per_baht': pointsPerBaht,
      'bonus_multiplier': bonusMultiplier,
      'min_purchase': minPurchase,
      'applies_to': appliesTo,
      'is_active': isActive,
      'valid_from': validFrom?.toIso8601String(),
      'valid_until': validUntil?.toIso8601String(),
    };
  }
}
