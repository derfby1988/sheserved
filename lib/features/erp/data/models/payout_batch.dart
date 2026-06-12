/// Model สำหรับ payout_batches (Settlement Core)
class PayoutBatch {
  final String id;
  final String professionId;
  final DateTime batchDate;
  final double totalAmount;
  final String status; // pending, processing, completed, failed
  final DateTime createdAt;

  const PayoutBatch({
    required this.id,
    required this.professionId,
    required this.batchDate,
    this.totalAmount = 0,
    this.status = 'pending',
    required this.createdAt,
  });

  factory PayoutBatch.fromJson(Map<String, dynamic> json) {
    return PayoutBatch(
      id: json['id'] as String,
      professionId: json['profession_id'] as String,
      batchDate: DateTime.parse(json['batch_date'] as String),
      totalAmount: (json['total_amount'] as num?)?.toDouble() ?? 0,
      status: json['status'] as String? ?? 'pending',
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'profession_id': professionId,
      'batch_date': batchDate.toIso8601String(),
      'total_amount': totalAmount,
      'status': status,
      'created_at': createdAt.toIso8601String(),
    };
  }
}
