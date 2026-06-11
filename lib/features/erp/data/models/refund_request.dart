/// Model สำหรับ refund_requests (POS Step 5)
class RefundRequest {
  final String id;
  final String professionId;
  final String orderId;
  final String orderNumber;
  final String? customerId;
  final String? requestedBy;
  final String? reviewedBy;
  final double amount;
  final String reason;
  final String status; // pending, approved, rejected, completed, cancelled
  final String? notes;
  final DateTime? requestedAt;
  final DateTime? reviewedAt;
  final DateTime? completedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  const RefundRequest({
    required this.id,
    required this.professionId,
    required this.orderId,
    required this.orderNumber,
    this.customerId,
    this.requestedBy,
    this.reviewedBy,
    required this.amount,
    required this.reason,
    this.status = 'pending',
    this.notes,
    this.requestedAt,
    this.reviewedAt,
    this.completedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  factory RefundRequest.fromJson(Map<String, dynamic> json) {
    return RefundRequest(
      id: json['id'] as String,
      professionId: json['profession_id'] as String,
      orderId: json['order_id'] as String,
      orderNumber: json['order_number'] as String,
      customerId: json['customer_id'] as String?,
      requestedBy: json['requested_by'] as String?,
      reviewedBy: json['reviewed_by'] as String?,
      amount: (json['amount'] as num).toDouble(),
      reason: json['reason'] as String,
      status: json['status'] as String? ?? 'pending',
      notes: json['notes'] as String?,
      requestedAt: json['requested_at'] != null ? DateTime.parse(json['requested_at'] as String) : null,
      reviewedAt: json['reviewed_at'] != null ? DateTime.parse(json['reviewed_at'] as String) : null,
      completedAt: json['completed_at'] != null ? DateTime.parse(json['completed_at'] as String) : null,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  String get statusLabel {
    switch (status) {
      case 'pending': return 'รออนุมัติ';
      case 'approved': return 'อนุมัติแล้ว';
      case 'rejected': return 'ปฏิเสธ';
      case 'completed': return 'เสร็จสิ้น';
      case 'cancelled': return 'ยกเลิก';
      default: return status;
    }
  }
}
