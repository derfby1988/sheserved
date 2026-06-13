/// Model สำหรับ purchase_order_items
class PurchaseOrderItem {
  final String id;
  final String poId;
  final String productId;
  final int quantityOrdered;
  final int quantityReceived;
  final double unitPrice;
  final double totalPrice;
  final DateTime? expectedDeliveryDate;
  final String? notes;
  final DateTime createdAt;

  // Joined fields
  final String? productName;
  final String? productUnitOfMeasure;

  const PurchaseOrderItem({
    required this.id,
    required this.poId,
    required this.productId,
    required this.quantityOrdered,
    required this.quantityReceived,
    required this.unitPrice,
    required this.totalPrice,
    this.expectedDeliveryDate,
    this.notes,
    required this.createdAt,
    this.productName,
    this.productUnitOfMeasure,
  });

  factory PurchaseOrderItem.fromJson(Map<String, dynamic> json) {
    String? prodName;
    String? prodUom;
    if (json['product'] != null) {
      prodName = json['product']['name'] as String?;
      prodUom = json['product']['unit_of_measure'] as String?;
    }

    return PurchaseOrderItem(
      id: json['id'] as String,
      poId: json['po_id'] as String,
      productId: json['product_id'] as String,
      quantityOrdered: json['quantity_ordered'] as int? ?? 1,
      quantityReceived: json['quantity_received'] as int? ?? 0,
      unitPrice: (json['unit_price'] as num?)?.toDouble() ?? 0.0,
      totalPrice: (json['total_price'] as num?)?.toDouble() ?? 0.0,
      expectedDeliveryDate: json['expected_delivery_date'] != null
          ? DateTime.parse(json['expected_delivery_date'] as String)
          : null,
      notes: json['notes'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      productName: prodName ?? json['product_name'] as String?,
      productUnitOfMeasure: prodUom ?? json['product_unit_of_measure'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'po_id': poId,
      'product_id': productId,
      'quantity_ordered': quantityOrdered,
      'quantity_received': quantityReceived,
      'unit_price': unitPrice,
      'total_price': totalPrice,
      'expected_delivery_date': expectedDeliveryDate?.toIso8601String().split('T')[0],
      'notes': notes,
      'created_at': createdAt.toIso8601String(),
    };
  }
}
