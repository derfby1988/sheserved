/// Model สำหรับ payment_transactions
class PaymentTransaction {
  final String id;
  final String professionId;
  final String orderId;
  final String? checkoutSessionId;
  final String userId;
  final double amount;
  final String currency;
  final String paymentMethod;
  final String? provider;
  final String? providerTxnId;
  final String status; // pending, processing, completed, failed, refunded, partially_refunded
  final String? errorCode;
  final String? errorMessage;
  final Map<String, dynamic> metadata;
  final DateTime? processedAt;
  final DateTime? refundedAt;
  final DateTime createdAt;

  const PaymentTransaction({
    required this.id,
    required this.professionId,
    required this.orderId,
    this.checkoutSessionId,
    required this.userId,
    this.amount = 0,
    this.currency = 'THB',
    required this.paymentMethod,
    this.provider,
    this.providerTxnId,
    this.status = 'pending',
    this.errorCode,
    this.errorMessage,
    this.metadata = const {},
    this.processedAt,
    this.refundedAt,
    required this.createdAt,
  });

  factory PaymentTransaction.fromJson(Map<String, dynamic> json) {
    return PaymentTransaction(
      id: json['id'] as String,
      professionId: json['profession_id'] as String,
      orderId: json['order_id'] as String,
      checkoutSessionId: json['checkout_session_id'] as String?,
      userId: json['user_id'] as String,
      amount: (json['amount'] as num?)?.toDouble() ?? 0,
      currency: json['currency'] as String? ?? 'THB',
      paymentMethod: json['payment_method'] as String,
      provider: json['provider'] as String?,
      providerTxnId: json['provider_txn_id'] as String?,
      status: json['status'] as String? ?? 'pending',
      errorCode: json['error_code'] as String?,
      errorMessage: json['error_message'] as String?,
      metadata: json['metadata'] as Map<String, dynamic>? ?? {},
      processedAt: json['processed_at'] != null ? DateTime.parse(json['processed_at'] as String) : null,
      refundedAt: json['refunded_at'] != null ? DateTime.parse(json['refunded_at'] as String) : null,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'profession_id': professionId,
      'order_id': orderId,
      'checkout_session_id': checkoutSessionId,
      'user_id': userId,
      'amount': amount,
      'currency': currency,
      'payment_method': paymentMethod,
      'provider': provider,
      'provider_txn_id': providerTxnId,
      'status': status,
      'error_code': errorCode,
      'error_message': errorMessage,
      'metadata': metadata,
      'processed_at': processedAt?.toIso8601String(),
      'refunded_at': refundedAt?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
    };
  }

  bool get isCompleted => status == 'completed';
  bool get isFailed => status == 'failed';
}
