/// Model สำหรับ custom_medications (ยา/สินค้าเฉพาะของคลินิก)
class CustomMedication {
  final String id;
  final String professionId;
  final String name;
  final String? description;
  final String? categoryId;
  final double price;
  final double costPrice;
  final String? sku;
  final String? barcode;
  final String? imageUrl;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  const CustomMedication({
    required this.id,
    required this.professionId,
    required this.name,
    this.description,
    this.categoryId,
    this.price = 0,
    this.costPrice = 0,
    this.sku,
    this.barcode,
    this.imageUrl,
    this.isActive = true,
    required this.createdAt,
    required this.updatedAt,
  });

  factory CustomMedication.fromJson(Map<String, dynamic> json) {
    return CustomMedication(
      id: json['id'] as String,
      professionId: json['profession_id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      categoryId: json['category_id'] as String?,
      price: (json['price'] as num?)?.toDouble() ?? 0,
      costPrice: (json['cost_price'] as num?)?.toDouble() ?? 0,
      sku: json['sku'] as String?,
      barcode: json['barcode'] as String?,
      imageUrl: json['image_url'] as String?,
      isActive: json['is_active'] as bool? ?? true,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'profession_id': professionId,
      'name': name,
      'description': description,
      'category_id': categoryId,
      'price': price,
      'cost_price': costPrice,
      'sku': sku,
      'barcode': barcode,
      'image_url': imageUrl,
      'is_active': isActive,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}
