/// Model สำหรับ procurement_settings (ตั้งค่าระบบจัดซื้อต่อองค์กร)
class ProcurementSettings {
  final String id;
  final String professionId;
  final bool enablePriceHistoryTracking;
  final String defaultPaymentTerms;
  final double autoReorderThresholdMultiplier;
  final double approvalAmountThreshold;
  final DateTime createdAt;
  final DateTime updatedAt;

  const ProcurementSettings({
    required this.id,
    required this.professionId,
    this.enablePriceHistoryTracking = false,
    this.defaultPaymentTerms = 'net_30',
    this.autoReorderThresholdMultiplier = 1.0,
    this.approvalAmountThreshold = 10000,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ProcurementSettings.fromJson(Map<String, dynamic> json) {
    return ProcurementSettings(
      id: json['id'] as String,
      professionId: json['profession_id'] as String,
      enablePriceHistoryTracking:
          json['enable_price_history_tracking'] as bool? ?? false,
      defaultPaymentTerms:
          json['default_payment_terms'] as String? ?? 'net_30',
      autoReorderThresholdMultiplier:
          (json['auto_reorder_threshold_multiplier'] as num?)?.toDouble() ??
              1.0,
      approvalAmountThreshold:
          (json['approval_amount_threshold'] as num?)?.toDouble() ?? 10000,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'profession_id': professionId,
      'enable_price_history_tracking': enablePriceHistoryTracking,
      'default_payment_terms': defaultPaymentTerms,
      'auto_reorder_threshold_multiplier': autoReorderThresholdMultiplier,
      'approval_amount_threshold': approvalAmountThreshold,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}
