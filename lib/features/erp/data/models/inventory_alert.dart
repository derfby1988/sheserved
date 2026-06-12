/// Model สำหรับ inventory_alerts (แจ้งเตือนสต็อก)
class InventoryAlert {
  final String id;
  final String professionId;
  final String? inventoryItemId;
  final String alertType; // low_stock, expiry_warning, expired, reorder, overstock
  final String severity; // low, medium, high, critical
  final String message;
  final bool isResolved;
  final String? resolvedBy;
  final DateTime? resolvedAt;
  final DateTime createdAt;

  const InventoryAlert({
    required this.id,
    required this.professionId,
    this.inventoryItemId,
    required this.alertType,
    required this.severity,
    required this.message,
    this.isResolved = false,
    this.resolvedBy,
    this.resolvedAt,
    required this.createdAt,
  });

  factory InventoryAlert.fromJson(Map<String, dynamic> json) {
    return InventoryAlert(
      id: json['id'] as String,
      professionId: json['profession_id'] as String,
      inventoryItemId: json['inventory_item_id'] as String?,
      alertType: json['alert_type'] as String,
      severity: json['severity'] as String,
      message: json['message'] as String,
      isResolved: json['is_resolved'] as bool? ?? false,
      resolvedBy: json['resolved_by'] as String?,
      resolvedAt: json['resolved_at'] != null
          ? DateTime.parse(json['resolved_at'] as String)
          : null,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'profession_id': professionId,
      'inventory_item_id': inventoryItemId,
      'alert_type': alertType,
      'severity': severity,
      'message': message,
      'is_resolved': isResolved,
      'resolved_by': resolvedBy,
      'resolved_at': resolvedAt?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
    };
  }

  String get typeLabel {
    switch (alertType) {
      case 'low_stock': return 'สต็อกต่ำ';
      case 'expiry_warning': return 'ใกล้หมดอายุ';
      case 'expired': return 'หมดอายุ';
      case 'reorder': return 'ถึงจุดสั่งซื้อ';
      case 'overstock': return 'สต็อกเกิน';
      default: return alertType;
    }
  }

  String get severityLabel {
    switch (severity) {
      case 'low': return 'ต่ำ';
      case 'medium': return 'ปานกลาง';
      case 'high': return 'สูง';
      case 'critical': return 'วิกฤต';
      default: return severity;
    }
  }
}
