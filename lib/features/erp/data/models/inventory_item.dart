/// Model สำหรับ inventory_items (stock summary ต่อ product/branch)
class InventoryItem {
  final String id;
  final String professionId;
  final String? productId;
  final String? customMedicationId;
  final String? branchId;
  final String? warehouseLocationId;
  final int quantity;
  final double costPrice;
  final double sellingPrice;
  final bool isVatable;
  final int reorderPoint;
  final int reorderQty;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  const InventoryItem({
    required this.id,
    required this.professionId,
    this.productId,
    this.customMedicationId,
    this.branchId,
    this.warehouseLocationId,
    this.quantity = 0,
    this.costPrice = 0,
    this.sellingPrice = 0,
    this.isVatable = false,
    this.reorderPoint = 0,
    this.reorderQty = 1,
    this.isActive = true,
    required this.createdAt,
    required this.updatedAt,
  });

  factory InventoryItem.fromJson(Map<String, dynamic> json) {
    return InventoryItem(
      id: json['id'] as String,
      professionId: json['profession_id'] as String,
      productId: json['product_id'] as String?,
      customMedicationId: json['custom_medication_id'] as String?,
      branchId: json['branch_id'] as String?,
      warehouseLocationId: json['warehouse_location_id'] as String?,
      quantity: (json['quantity'] as num?)?.toInt() ?? 0,
      costPrice: (json['cost_price'] as num?)?.toDouble() ?? 0,
      sellingPrice: (json['selling_price'] as num?)?.toDouble() ?? 0,
      isVatable: json['is_vatable'] as bool? ?? false,
      reorderPoint: (json['reorder_point'] as num?)?.toInt() ?? 0,
      reorderQty: (json['reorder_qty'] as num?)?.toInt() ?? 1,
      isActive: json['is_active'] as bool? ?? true,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'profession_id': professionId,
      'product_id': productId,
      'custom_medication_id': customMedicationId,
      'branch_id': branchId,
      'warehouse_location_id': warehouseLocationId,
      'quantity': quantity,
      'cost_price': costPrice,
      'selling_price': sellingPrice,
      'is_vatable': isVatable,
      'reorder_point': reorderPoint,
      'reorder_qty': reorderQty,
      'is_active': isActive,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  bool get isLowStock => quantity <= reorderPoint && quantity > 0;
  bool get isOutOfStock => quantity <= 0;
  double get stockValue => costPrice * quantity;
}
