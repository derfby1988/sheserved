/// Model สำหรับ products (Shared Master)
class Product {
  final String id;
  final String professionId;
  final String? categoryId;
  final String name;
  final String? description;
  final String? sku;
  final String? barcode;
  final String unitOfMeasure;
  final double costPrice;
  final double salePrice;
  final bool isVatable;
  final bool isActive;
  final bool isStockable;
  final bool hasLotTracking;
  final int? shelfLifeDays;
  final int reorderPoint;
  final int reorderQty;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Product({
    required this.id,
    required this.professionId,
    this.categoryId,
    required this.name,
    this.description,
    this.sku,
    this.barcode,
    this.unitOfMeasure = 'piece',
    this.costPrice = 0,
    this.salePrice = 0,
    this.isVatable = false,
    this.isActive = true,
    this.isStockable = true,
    this.hasLotTracking = false,
    this.shelfLifeDays,
    this.reorderPoint = 0,
    this.reorderQty = 0,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Product.fromJson(Map<String, dynamic> json) {
    return Product(
      id: json['id'] as String,
      professionId: json['profession_id'] as String,
      categoryId: json['category_id'] as String?,
      name: json['name'] as String,
      description: json['description'] as String?,
      sku: json['sku'] as String?,
      barcode: json['barcode'] as String?,
      unitOfMeasure: json['unit_of_measure'] as String? ?? 'piece',
      costPrice: (json['cost_price'] as num?)?.toDouble() ?? 0,
      salePrice: (json['sale_price'] as num?)?.toDouble() ?? 0,
      isVatable: json['is_vatable'] as bool? ?? false,
      isActive: json['is_active'] as bool? ?? true,
      isStockable: json['is_stockable'] as bool? ?? true,
      hasLotTracking: json['has_lot_tracking'] as bool? ?? false,
      shelfLifeDays: json['shelf_life_days'] as int?,
      reorderPoint: json['reorder_point'] as int? ?? 0,
      reorderQty: json['reorder_qty'] as int? ?? 0,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'profession_id': professionId,
      'category_id': categoryId,
      'name': name,
      'description': description,
      'sku': sku,
      'barcode': barcode,
      'unit_of_measure': unitOfMeasure,
      'cost_price': costPrice,
      'sale_price': salePrice,
      'is_vatable': isVatable,
      'is_active': isActive,
      'is_stockable': isStockable,
      'has_lot_tracking': hasLotTracking,
      'shelf_life_days': shelfLifeDays,
      'reorder_point': reorderPoint,
      'reorder_qty': reorderQty,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  double get profitMargin => salePrice > 0 ? ((salePrice - costPrice) / salePrice) * 100 : 0;
  bool get needsReorder => isStockable && reorderPoint > 0; // logic จริงต้องเทียบกับ stock จริง
}
