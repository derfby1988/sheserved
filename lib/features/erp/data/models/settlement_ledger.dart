/// Model สำหรับ settlement_ledgers (Settlement Core)
class SettlementLedger {
  final String id;
  final String professionId;
  final String vendorContractId;
  final DateTime periodStart;
  final DateTime periodEnd;
  final double totalGross;
  final double totalFee;
  final double totalNet;
  final double totalPlatformFee;
  final double totalMerchantPayout;
  final String status; // open, processing, paid, failed
  final DateTime? paidAt;
  final String? payoutReference;
  final DateTime createdAt;
  final DateTime updatedAt;

  const SettlementLedger({
    required this.id,
    required this.professionId,
    required this.vendorContractId,
    required this.periodStart,
    required this.periodEnd,
    this.totalGross = 0,
    this.totalFee = 0,
    this.totalNet = 0,
    this.totalPlatformFee = 0,
    this.totalMerchantPayout = 0,
    this.status = 'open',
    this.paidAt,
    this.payoutReference,
    required this.createdAt,
    required this.updatedAt,
  });

  factory SettlementLedger.fromJson(Map<String, dynamic> json) {
    return SettlementLedger(
      id: json['id'] as String,
      professionId: json['profession_id'] as String,
      vendorContractId: json['vendor_contract_id'] as String,
      periodStart: DateTime.parse(json['period_start'] as String),
      periodEnd: DateTime.parse(json['period_end'] as String),
      totalGross: (json['total_gross'] as num?)?.toDouble() ?? 0,
      totalFee: (json['total_fee'] as num?)?.toDouble() ?? 0,
      totalNet: (json['total_net'] as num?)?.toDouble() ?? 0,
      totalPlatformFee: (json['total_platform_fee'] as num?)?.toDouble() ?? 0,
      totalMerchantPayout: (json['total_merchant_payout'] as num?)?.toDouble() ?? 0,
      status: json['status'] as String? ?? 'open',
      paidAt: json['paid_at'] != null
          ? DateTime.parse(json['paid_at'] as String)
          : null,
      payoutReference: json['payout_reference'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'profession_id': professionId,
      'vendor_contract_id': vendorContractId,
      'period_start': periodStart.toIso8601String(),
      'period_end': periodEnd.toIso8601String(),
      'total_gross': totalGross,
      'total_fee': totalFee,
      'total_net': totalNet,
      'total_platform_fee': totalPlatformFee,
      'total_merchant_payout': totalMerchantPayout,
      'status': status,
      'paid_at': paidAt?.toIso8601String(),
      'payout_reference': payoutReference,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}
