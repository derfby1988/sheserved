/// Model สำหรับ stocktake_lines (รายการตรวจนับแต่ละสินค้า)
class StocktakeLine {
  final String id;
  final String stocktakeSessionId;
  final String inventoryItemId;
  final int systemQuantity;
  final int countedQuantity;
  final int variance;
  final String? reason;
  final DateTime createdAt;

  const StocktakeLine({
    required this.id,
    required this.stocktakeSessionId,
    required this.inventoryItemId,
    this.systemQuantity = 0,
    this.countedQuantity = 0,
    this.variance = 0,
    this.reason,
    required this.createdAt,
  });

  factory StocktakeLine.fromJson(Map<String, dynamic> json) {
    return StocktakeLine(
      id: json['id'] as String,
      stocktakeSessionId: json['stocktake_session_id'] as String,
      inventoryItemId: json['inventory_item_id'] as String,
      systemQuantity: (json['system_quantity'] as num?)?.toInt() ?? 0,
      countedQuantity: (json['counted_quantity'] as num?)?.toInt() ?? 0,
      variance: (json['variance'] as num?)?.toInt() ?? 0,
      reason: json['reason'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'stocktake_session_id': stocktakeSessionId,
      'inventory_item_id': inventoryItemId,
      'system_quantity': systemQuantity,
      'counted_quantity': countedQuantity,
      'variance': variance,
      'reason': reason,
      'created_at': createdAt.toIso8601String(),
    };
  }

  bool get hasVariance => variance != 0;
}
