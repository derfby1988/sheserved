/// Model สำหรับ payout_batch_lines (Settlement Core)
class PayoutBatchLine {
  final String id;
  final String payoutBatchId;
  final String allocationId;
  final String? merchantAccountId;
  final double amount;
  final String status; // pending, processing, completed, failed
  final String? failureReason;
  final DateTime createdAt;

  const PayoutBatchLine({
    required this.id,
    required this.payoutBatchId,
    required this.allocationId,
    this.merchantAccountId,
    this.amount = 0,
    this.status = 'pending',
    this.failureReason,
    required this.createdAt,
  });

  factory PayoutBatchLine.fromJson(Map<String, dynamic> json) {
    return PayoutBatchLine(
      id: json['id'] as String,
      payoutBatchId: json['payout_batch_id'] as String,
      allocationId: json['allocation_id'] as String,
      merchantAccountId: json['merchant_account_id'] as String?,
      amount: (json['amount'] as num?)?.toDouble() ?? 0,
      status: json['status'] as String? ?? 'pending',
      failureReason: json['failure_reason'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'payout_batch_id': payoutBatchId,
      'allocation_id': allocationId,
      'merchant_account_id': merchantAccountId,
      'amount': amount,
      'status': status,
      'failure_reason': failureReason,
      'created_at': createdAt.toIso8601String(),
    };
  }
}
