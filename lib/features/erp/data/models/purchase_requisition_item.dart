/// Model สำหรับ purchase_requisition_items (line items ของ PR)
class PurchaseRequisitionItem {
  final String id;
  final String professionId;
  final String requisitionId;
  final String productId;
  final String itemName;
  final int quantityRequested;
  final double? estimatedUnitPrice;
  final double? estimatedTotalPrice;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  // Joined fields
  final String? productName;
  final String? productSku;

  const PurchaseRequisitionItem({
    required this.id,
    required this.professionId,
    required this.requisitionId,
    required this.productId,
    required this.itemName,
    required this.quantityRequested,
    this.estimatedUnitPrice,
    this.estimatedTotalPrice,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
    this.productName,
    this.productSku,
  });

  factory PurchaseRequisitionItem.fromJson(Map<String, dynamic> json) {
    String? prodName;
    String? prodSku;
    if (json['product'] != null) {
      prodName = json['product']['name'] as String?;
      prodSku = json['product']['sku'] as String?;
    }

    return PurchaseRequisitionItem(
      id: json['id'] as String,
      professionId: json['profession_id'] as String,
      requisitionId: json['requisition_id'] as String,
      productId: json['product_id'] as String,
      itemName: json['item_name'] as String,
      quantityRequested: json['quantity_requested'] as int? ?? 1,
      estimatedUnitPrice: (json['estimated_unit_price'] as num?)?.toDouble(),
      estimatedTotalPrice: (json['estimated_total_price'] as num?)?.toDouble(),
      notes: json['notes'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      productName: prodName ?? json['product_name'] as String?,
      productSku: prodSku ?? json['product_sku'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'profession_id': professionId,
      'requisition_id': requisitionId,
      'product_id': productId,
      'item_name': itemName,
      'quantity_requested': quantityRequested,
      'estimated_unit_price': estimatedUnitPrice,
      'estimated_total_price': estimatedTotalPrice,
      'notes': notes,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}
