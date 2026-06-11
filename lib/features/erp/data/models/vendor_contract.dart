/// Model สำหรับ vendor_contracts (Settlement Core)
class VendorContract {
  final String id;
  final String professionId;
  final String vendorName;
  final String vendorType; // merchant, delivery_partner, payment_provider, platform
  final String? contractCode;
  final double feePercent;
  final double fixedFeePerTxn;
  final double minFee;
  final double maxFee;
  final int payoutCycleDays;
  final bool isActive;
  final DateTime effectiveFrom;
  final DateTime? effectiveUntil;
  final DateTime createdAt;
  final DateTime updatedAt;

  const VendorContract({
    required this.id,
    required this.professionId,
    required this.vendorName,
    this.vendorType = 'merchant',
    this.contractCode,
    this.feePercent = 0,
    this.fixedFeePerTxn = 0,
    this.minFee = 0,
    this.maxFee = 0,
    this.payoutCycleDays = 7,
    this.isActive = true,
    required this.effectiveFrom,
    this.effectiveUntil,
    required this.createdAt,
    required this.updatedAt,
  });

  factory VendorContract.fromJson(Map<String, dynamic> json) {
    return VendorContract(
      id: json['id'] as String,
      professionId: json['profession_id'] as String,
      vendorName: json['vendor_name'] as String,
      vendorType: json['vendor_type'] as String? ?? 'merchant',
      contractCode: json['contract_code'] as String?,
      feePercent: (json['fee_percent'] as num?)?.toDouble() ?? 0,
      fixedFeePerTxn: (json['fixed_fee_per_txn'] as num?)?.toDouble() ?? 0,
      minFee: (json['min_fee'] as num?)?.toDouble() ?? 0,
      maxFee: (json['max_fee'] as num?)?.toDouble() ?? 0,
      payoutCycleDays: json['payout_cycle_days'] as int? ?? 7,
      isActive: json['is_active'] as bool? ?? true,
      effectiveFrom: DateTime.parse(json['effective_from'] as String),
      effectiveUntil: json['effective_until'] != null ? DateTime.parse(json['effective_until'] as String) : null,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'profession_id': professionId,
      'vendor_name': vendorName,
      'vendor_type': vendorType,
      'contract_code': contractCode,
      'fee_percent': feePercent,
      'fixed_fee_per_txn': fixedFeePerTxn,
      'min_fee': minFee,
      'max_fee': maxFee,
      'payout_cycle_days': payoutCycleDays,
      'is_active': isActive,
      'effective_from': effectiveFrom.toIso8601String(),
      'effective_until': effectiveUntil?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}
