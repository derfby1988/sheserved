/// Model สำหรับ payment_allocations (Settlement Core)
class PaymentAllocation {
  final String id;
  final String professionId;
  final String orderId;
  final String paymentTxnId;
  final String? vendorContractId;
  final double grossAmount;
  final double feeAmount;
  final double netAmount;
  final double platformFee;
  final double merchantPayout;
  final String allocationStatus; // pending, calculated, paid_out, failed
  final DateTime? paidOutAt;
  final String? payoutReference;
  final DateTime createdAt;

  const PaymentAllocation({
    required this.id,
    required this.professionId,
    required this.orderId,
    required this.paymentTxnId,
    this.vendorContractId,
    this.grossAmount = 0,
    this.feeAmount = 0,
    this.netAmount = 0,
    this.platformFee = 0,
    this.merchantPayout = 0,
    this.allocationStatus = 'pending',
    this.paidOutAt,
    this.payoutReference,
    required this.createdAt,
  });

  factory PaymentAllocation.fromJson(Map<String, dynamic> json) {
    return PaymentAllocation(
      id: json['id'] as String,
      professionId: json['profession_id'] as String,
      orderId: json['order_id'] as String,
      paymentTxnId: json['payment_txn_id'] as String,
      vendorContractId: json['vendor_contract_id'] as String?,
      grossAmount: (json['gross_amount'] as num?)?.toDouble() ?? 0,
      feeAmount: (json['fee_amount'] as num?)?.toDouble() ?? 0,
      netAmount: (json['net_amount'] as num?)?.toDouble() ?? 0,
      platformFee: (json['platform_fee'] as num?)?.toDouble() ?? 0,
      merchantPayout: (json['merchant_payout'] as num?)?.toDouble() ?? 0,
      allocationStatus: json['allocation_status'] as String? ?? 'pending',
      paidOutAt: json['paid_out_at'] != null
          ? DateTime.parse(json['paid_out_at'] as String)
          : null,
      payoutReference: json['payout_reference'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'profession_id': professionId,
      'order_id': orderId,
      'payment_txn_id': paymentTxnId,
      'vendor_contract_id': vendorContractId,
      'gross_amount': grossAmount,
      'fee_amount': feeAmount,
      'net_amount': netAmount,
      'platform_fee': platformFee,
      'merchant_payout': merchantPayout,
      'allocation_status': allocationStatus,
      'paid_out_at': paidOutAt?.toIso8601String(),
      'payout_reference': payoutReference,
      'created_at': createdAt.toIso8601String(),
    };
  }
}
