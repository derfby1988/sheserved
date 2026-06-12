/// Model สำหรับ stock_adjustments (ปรับปรุงยอดสต็อก)
class StockAdjustment {
  final String id;
  final String professionId;
  final String inventoryItemId;
  final String adjustmentType; // count, damage, expired, found, lost, other
  final int quantityBefore;
  final int quantityAfter;
  final int variance;
  final String? reason;
  final String? referenceId;
  final String? createdBy;
  final DateTime createdAt;

  const StockAdjustment({
    required this.id,
    required this.professionId,
    required this.inventoryItemId,
    required this.adjustmentType,
    this.quantityBefore = 0,
    this.quantityAfter = 0,
    this.variance = 0,
    this.reason,
    this.referenceId,
    this.createdBy,
    required this.createdAt,
  });

  factory StockAdjustment.fromJson(Map<String, dynamic> json) {
    return StockAdjustment(
      id: json['id'] as String,
      professionId: json['profession_id'] as String,
      inventoryItemId: json['inventory_item_id'] as String,
      adjustmentType: json['adjustment_type'] as String,
      quantityBefore: (json['quantity_before'] as num?)?.toInt() ?? 0,
      quantityAfter: (json['quantity_after'] as num?)?.toInt() ?? 0,
      variance: (json['variance'] as num?)?.toInt() ?? 0,
      reason: json['reason'] as String?,
      referenceId: json['reference_id'] as String?,
      createdBy: json['created_by'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'profession_id': professionId,
      'inventory_item_id': inventoryItemId,
      'adjustment_type': adjustmentType,
      'quantity_before': quantityBefore,
      'quantity_after': quantityAfter,
      'variance': variance,
      'reason': reason,
      'reference_id': referenceId,
      'created_by': createdBy,
      'created_at': createdAt.toIso8601String(),
    };
  }

  String get typeLabel {
    switch (adjustmentType) {
      case 'count': return 'ตรวจนับ';
      case 'damage': return 'เสียหาย';
      case 'expired': return 'หมดอายุ';
      case 'found': return 'พบเพิ่ม';
      case 'lost': return 'สูญหาย';
      case 'other': return 'อื่นๆ';
      default: return adjustmentType;
    }
  }
}
