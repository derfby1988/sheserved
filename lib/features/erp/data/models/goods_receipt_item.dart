/// Model สำหรับ goods_receipt_items
class GoodsReceiptItem {
  final String id;
  final String professionId;
  final String goodsReceiptId;
  final String purchaseOrderItemId;
  final int quantityReceived;
  final int quantityAccepted;
  final int quantityRejected;
  final String? lotNumber;
  final DateTime? expiryDate;
  final double? unitCost;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  // Joined fields
  final String? productName;
  final int? poQuantityOrdered;
  final int? poQuantityReceived;

  const GoodsReceiptItem({
    required this.id,
    required this.professionId,
    required this.goodsReceiptId,
    required this.purchaseOrderItemId,
    required this.quantityReceived,
    required this.quantityAccepted,
    required this.quantityRejected,
    this.lotNumber,
    this.expiryDate,
    this.unitCost,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
    this.productName,
    this.poQuantityOrdered,
    this.poQuantityReceived,
  });

  factory GoodsReceiptItem.fromJson(Map<String, dynamic> json) {
    String? prodName;
    int? poQtyOrdered;
    int? poQtyReceived;
    if (json['purchase_order_item'] != null) {
      poQtyOrdered = json['purchase_order_item']['quantity_ordered'] as int?;
      poQtyReceived = json['purchase_order_item']['quantity_received'] as int?;
      if (json['purchase_order_item']['product'] != null) {
        prodName = json['purchase_order_item']['product']['name'] as String?;
      }
    }

    return GoodsReceiptItem(
      id: json['id'] as String,
      professionId: json['profession_id'] as String,
      goodsReceiptId: json['goods_receipt_id'] as String,
      purchaseOrderItemId: json['purchase_order_item_id'] as String,
      quantityReceived: json['quantity_received'] as int? ?? 0,
      quantityAccepted: json['quantity_accepted'] as int? ?? 0,
      quantityRejected: json['quantity_rejected'] as int? ?? 0,
      lotNumber: json['lot_number'] as String?,
      expiryDate: json['expiry_date'] != null
          ? DateTime.parse(json['expiry_date'] as String)
          : null,
      unitCost: (json['unit_cost'] as num?)?.toDouble(),
      notes: json['notes'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      productName: prodName ?? json['product_name'] as String?,
      poQuantityOrdered: poQtyOrdered ?? json['po_quantity_ordered'] as int?,
      poQuantityReceived: poQtyReceived ?? json['po_quantity_received'] as int?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'profession_id': professionId,
      'goods_receipt_id': goodsReceiptId,
      'purchase_order_item_id': purchaseOrderItemId,
      'quantity_received': quantityReceived,
      'quantity_accepted': quantityAccepted,
      'quantity_rejected': quantityRejected,
      'lot_number': lotNumber,
      'expiry_date': expiryDate?.toIso8601String().split('T')[0],
      'unit_cost': unitCost,
      'notes': notes,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  int get remainingQuantity =>
      (poQuantityOrdered ?? 0) - (poQuantityReceived ?? 0);
}
