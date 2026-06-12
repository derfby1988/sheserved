/// Model สำหรับ cart_items (Cart Core)
class CartItem {
  final String id;
  final String cartSessionId;
  final String productId;
  final String productName;
  final String? productImageUrl;
  final int quantity;
  final double unitPrice;
  final double discountAmount;
  final double lineTotal;
  final DateTime createdAt;
  final DateTime updatedAt;

  const CartItem({
    required this.id,
    required this.cartSessionId,
    required this.productId,
    required this.productName,
    this.productImageUrl,
    this.quantity = 1,
    this.unitPrice = 0,
    this.discountAmount = 0,
    this.lineTotal = 0,
    required this.createdAt,
    required this.updatedAt,
  });

  factory CartItem.fromJson(Map<String, dynamic> json) {
    return CartItem(
      id: json['id'] as String,
      cartSessionId: json['cart_session_id'] as String,
      productId: json['product_id'] as String,
      productName: json['product_name'] as String? ?? json['name'] as String? ?? '',
      productImageUrl: json['product_image_url'] as String?,
      quantity: json['quantity'] as int? ?? 1,
      unitPrice: (json['unit_price'] as num?)?.toDouble() ?? 0,
      discountAmount: (json['discount_amount'] as num?)?.toDouble() ?? 0,
      lineTotal: (json['line_total'] as num?)?.toDouble() ?? 0,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'cart_session_id': cartSessionId,
      'product_id': productId,
      'product_name': productName,
      'product_image_url': productImageUrl,
      'quantity': quantity,
      'unit_price': unitPrice,
      'discount_amount': discountAmount,
      'line_total': lineTotal,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  double get total => unitPrice * quantity;
}
