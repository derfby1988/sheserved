/// Model สำหรับ checkout_sessions (State Machine)
class CheckoutSession {
  final String id;
  final String professionId;
  final String userId;
  final String? customerId;
  final Map<String, dynamic> cartSnapshot;
  final String? orderId;
  final String status; // created, payment_pending, payment_failed, paid, confirmed, cancelled, expired
  final String? paymentMethod;
  final double totalAmount;
  final double discountAmount;
  final double vatAmount;
  final double netAmount;
  final String? couponId;
  final int loyaltyPointsUsed;
  final String? idempotencyKey;
  final DateTime? expiresAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  const CheckoutSession({
    required this.id,
    required this.professionId,
    required this.userId,
    this.customerId,
    required this.cartSnapshot,
    this.orderId,
    this.status = 'created',
    this.paymentMethod,
    this.totalAmount = 0,
    this.discountAmount = 0,
    this.vatAmount = 0,
    this.netAmount = 0,
    this.couponId,
    this.loyaltyPointsUsed = 0,
    this.idempotencyKey,
    this.expiresAt,
    required this.createdAt,
    required this.updatedAt,
  });

  factory CheckoutSession.fromJson(Map<String, dynamic> json) {
    return CheckoutSession(
      id: json['id'] as String,
      professionId: json['profession_id'] as String,
      userId: json['user_id'] as String,
      customerId: json['customer_id'] as String?,
      cartSnapshot: json['cart_snapshot'] as Map<String, dynamic>? ?? {},
      orderId: json['order_id'] as String?,
      status: json['status'] as String? ?? 'created',
      paymentMethod: json['payment_method'] as String?,
      totalAmount: (json['total_amount'] as num?)?.toDouble() ?? 0,
      discountAmount: (json['discount_amount'] as num?)?.toDouble() ?? 0,
      vatAmount: (json['vat_amount'] as num?)?.toDouble() ?? 0,
      netAmount: (json['net_amount'] as num?)?.toDouble() ?? 0,
      couponId: json['coupon_id'] as String?,
      loyaltyPointsUsed: json['loyalty_points_used'] as int? ?? 0,
      idempotencyKey: json['idempotency_key'] as String?,
      expiresAt: json['expires_at'] != null ? DateTime.parse(json['expires_at'] as String) : null,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'profession_id': professionId,
      'user_id': userId,
      'customer_id': customerId,
      'cart_snapshot': cartSnapshot,
      'order_id': orderId,
      'status': status,
      'payment_method': paymentMethod,
      'total_amount': totalAmount,
      'discount_amount': discountAmount,
      'vat_amount': vatAmount,
      'net_amount': netAmount,
      'coupon_id': couponId,
      'loyalty_points_used': loyaltyPointsUsed,
      'idempotency_key': idempotencyKey,
      'expires_at': expiresAt?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  bool get isExpired => status == 'expired' || (expiresAt?.isBefore(DateTime.now()) ?? false);
  bool get isPaid => status == 'paid' || status == 'confirmed';
  bool get isActive => status == 'created' || status == 'payment_pending';
}
