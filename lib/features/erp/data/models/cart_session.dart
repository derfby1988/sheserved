/// Model สำหรับ cart_sessions (Cart Core)
class CartSession {
  final String id;
  final String professionId;
  final String userId;
  final String? customerId;
  final String sessionType; // self_service, counter_pos, clinic_pos
  final String status; // active, checked_out, abandoned, expired
  final double totalAmount;
  final double discountAmount;
  final double vatAmount;
  final double netAmount;
  final int itemCount;
  final DateTime? expiresAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  const CartSession({
    required this.id,
    required this.professionId,
    required this.userId,
    this.customerId,
    this.sessionType = 'self_service',
    this.status = 'active',
    this.totalAmount = 0,
    this.discountAmount = 0,
    this.vatAmount = 0,
    this.netAmount = 0,
    this.itemCount = 0,
    this.expiresAt,
    required this.createdAt,
    required this.updatedAt,
  });

  factory CartSession.fromJson(Map<String, dynamic> json) {
    return CartSession(
      id: json['id'] as String,
      professionId: json['profession_id'] as String,
      userId: json['user_id'] as String,
      customerId: json['customer_id'] as String?,
      sessionType: json['session_type'] as String? ?? 'self_service',
      status: json['status'] as String? ?? 'active',
      totalAmount: (json['total_amount'] as num?)?.toDouble() ?? 0,
      discountAmount: (json['discount_amount'] as num?)?.toDouble() ?? 0,
      vatAmount: (json['vat_amount'] as num?)?.toDouble() ?? 0,
      netAmount: (json['net_amount'] as num?)?.toDouble() ?? 0,
      itemCount: json['item_count'] as int? ?? 0,
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
      'session_type': sessionType,
      'status': status,
      'total_amount': totalAmount,
      'discount_amount': discountAmount,
      'vat_amount': vatAmount,
      'net_amount': netAmount,
      'item_count': itemCount,
      'expires_at': expiresAt?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  bool get isActive => status == 'active';
  bool get isExpired => status == 'expired' || (expiresAt?.isBefore(DateTime.now()) ?? false);
}
