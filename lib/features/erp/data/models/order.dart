/// Model สำหรับ existing orders table (POS Core)
class Order {
  final String id;
  final String orderNumber;
  final String userId;
  final String professionId;
  final String? branchId;
  final String? customerId;
  final String posMode; // mode_a, mode_b_counter, mode_c_clinic
  final String status; // pending, paid, preparing, in_transit, delivered, completed, cancelled, refunded
  final double subtotal;
  final double discountTotal;
  final double vatTotal;
  final double grandTotal;
  final double amountPaid;
  final String? paymentMethod;
  final String? paymentRef;
  final String? notes;
  final String? servedBy;
  final DateTime? completedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Order({
    required this.id,
    required this.orderNumber,
    required this.userId,
    required this.professionId,
    this.branchId,
    this.customerId,
    this.posMode = 'mode_a',
    this.status = 'pending',
    this.subtotal = 0,
    this.discountTotal = 0,
    this.vatTotal = 0,
    this.grandTotal = 0,
    this.amountPaid = 0,
    this.paymentMethod,
    this.paymentRef,
    this.notes,
    this.servedBy,
    this.completedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Order.fromJson(Map<String, dynamic> json) {
    return Order(
      id: json['id'] as String,
      orderNumber: json['order_number'] as String,
      userId: json['user_id'] as String,
      professionId: json['profession_id'] as String,
      branchId: json['branch_id'] as String?,
      customerId: json['customer_id'] as String?,
      posMode: json['pos_mode'] as String? ?? 'mode_a',
      status: json['status'] as String? ?? 'pending',
      subtotal: (json['subtotal'] as num?)?.toDouble() ?? 0,
      discountTotal: (json['discount_total'] as num?)?.toDouble() ?? 0,
      vatTotal: (json['vat_total'] as num?)?.toDouble() ?? 0,
      grandTotal: (json['grand_total'] as num?)?.toDouble() ?? 0,
      amountPaid: (json['amount_paid'] as num?)?.toDouble() ?? 0,
      paymentMethod: json['payment_method'] as String?,
      paymentRef: json['payment_ref'] as String?,
      notes: json['notes'] as String?,
      servedBy: json['served_by'] as String?,
      completedAt: json['completed_at'] != null ? DateTime.parse(json['completed_at'] as String) : null,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'order_number': orderNumber,
      'user_id': userId,
      'profession_id': professionId,
      'branch_id': branchId,
      'customer_id': customerId,
      'pos_mode': posMode,
      'status': status,
      'subtotal': subtotal,
      'discount_total': discountTotal,
      'vat_total': vatTotal,
      'grand_total': grandTotal,
      'amount_paid': amountPaid,
      'payment_method': paymentMethod,
      'payment_ref': paymentRef,
      'notes': notes,
      'served_by': servedBy,
      'completed_at': completedAt?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  bool get isPaid => status == 'paid' || status == 'completed';
}

/// Model สำหรับ order_items (line items)
class OrderItem {
  final String id;
  final String orderId;
  final String itemType; // product, service, clinic_service
  final String? itemId; // product_id หรือ service_id
  final String name;
  final int quantity;
  final double unitPrice;
  final double discountAmount;
  final double vatAmount;
  final double lineTotal;
  final String? notes;
  final DateTime createdAt;

  const OrderItem({
    required this.id,
    required this.orderId,
    required this.itemType,
    this.itemId,
    required this.name,
    this.quantity = 1,
    this.unitPrice = 0,
    this.discountAmount = 0,
    this.vatAmount = 0,
    this.lineTotal = 0,
    this.notes,
    required this.createdAt,
  });

  factory OrderItem.fromJson(Map<String, dynamic> json) {
    return OrderItem(
      id: json['id'] as String,
      orderId: json['order_id'] as String,
      itemType: json['item_type'] as String,
      itemId: json['item_id'] as String?,
      name: json['name'] as String,
      quantity: json['quantity'] as int? ?? 1,
      unitPrice: (json['unit_price'] as num?)?.toDouble() ?? 0,
      discountAmount: (json['discount_amount'] as num?)?.toDouble() ?? 0,
      vatAmount: (json['vat_amount'] as num?)?.toDouble() ?? 0,
      lineTotal: (json['line_total'] as num?)?.toDouble() ?? 0,
      notes: json['notes'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'order_id': orderId,
      'item_type': itemType,
      'item_id': itemId,
      'name': name,
      'quantity': quantity,
      'unit_price': unitPrice,
      'discount_amount': discountAmount,
      'vat_amount': vatAmount,
      'line_total': lineTotal,
      'notes': notes,
    };
  }
}
