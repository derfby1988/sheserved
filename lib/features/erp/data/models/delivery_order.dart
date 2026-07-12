/// Model สำหรับ delivery_orders (Logistics Core)
class DeliveryOrder {
  final String id;
  final String professionId;
  final String orderId;
  final String? customerId;
  final String deliveryStatus; // pending, preparing, ready_for_pickup, picked_up, in_transit, arrived, delivered, failed, cancelled, returned
  final String recipientName;
  final String recipientPhone;
  final String deliveryAddress;
  final String? deliveryNotes;
  final String deliveryType; // standard, express, same_day, pickup
  final DateTime? scheduledDeliveryAt;
  final DateTime? deliveredAt;
  final Map<String, dynamic> proofOfDelivery;
  final String? trackingNumber;
  /// Metadata เพิ่มเติม — รวม `drug_risk_flags` สำหรับแจ้งเตือนไรเดอร์/คลังยา
  /// เมื่อรายการมียาที่มี Override หรือยาควบคุมพิเศษ (ดู DRUG_RISK_OVERRIDE_PLAN.md ข้อ 5.2)
  final Map<String, dynamic> metadata;
  final DateTime createdAt;
  final DateTime updatedAt;

  const DeliveryOrder({
    required this.id,
    required this.professionId,
    required this.orderId,
    this.customerId,
    this.deliveryStatus = 'pending',
    required this.recipientName,
    required this.recipientPhone,
    required this.deliveryAddress,
    this.deliveryNotes,
    this.deliveryType = 'standard',
    this.scheduledDeliveryAt,
    this.deliveredAt,
    this.proofOfDelivery = const {},
    this.trackingNumber,
    this.metadata = const {},
    required this.createdAt,
    required this.updatedAt,
  });

  factory DeliveryOrder.fromJson(Map<String, dynamic> json) {
    return DeliveryOrder(
      id: json['id'] as String,
      professionId: json['profession_id'] as String,
      orderId: json['order_id'] as String,
      customerId: json['customer_id'] as String?,
      deliveryStatus: json['delivery_status'] as String? ?? 'pending',
      recipientName: json['recipient_name'] as String,
      recipientPhone: json['recipient_phone'] as String,
      deliveryAddress: json['delivery_address'] as String,
      deliveryNotes: json['delivery_notes'] as String?,
      deliveryType: json['delivery_type'] as String? ?? 'standard',
      scheduledDeliveryAt: json['scheduled_delivery_at'] != null ? DateTime.parse(json['scheduled_delivery_at'] as String) : null,
      deliveredAt: json['delivered_at'] != null ? DateTime.parse(json['delivered_at'] as String) : null,
      proofOfDelivery: json['proof_of_delivery'] != null
          ? Map<String, dynamic>.from(json['proof_of_delivery'] as Map)
          : {},
      trackingNumber: json['tracking_number'] as String?,
      metadata: json['metadata'] != null
          ? Map<String, dynamic>.from(json['metadata'] as Map)
          : {},
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'profession_id': professionId,
      'order_id': orderId,
      'customer_id': customerId,
      'delivery_status': deliveryStatus,
      'recipient_name': recipientName,
      'recipient_phone': recipientPhone,
      'delivery_address': deliveryAddress,
      'delivery_notes': deliveryNotes,
      'delivery_type': deliveryType,
      'scheduled_delivery_at': scheduledDeliveryAt?.toIso8601String(),
      'delivered_at': deliveredAt?.toIso8601String(),
      'proof_of_delivery': proofOfDelivery,
      'tracking_number': trackingNumber,
      'metadata': metadata,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  /// Drug risk flags จาก metadata (DRUG_RISK_OVERRIDE_PLAN.md ข้อ 5.2)
  Map<String, dynamic>? get drugRiskFlags {
    final value = metadata['drug_risk_flags'];
    if (value == null) return null;
    return Map<String, dynamic>.from(value as Map);
  }

  /// มียาที่มี Override หรือยาควบคุมพิเศษในรายการจัดส่งนี้หรือไม่
  bool get hasDrugRiskFlags => drugRiskFlags != null;

  /// ต้องยืนยันตัวตนผู้รับก่อนส่งมอบ (ยาควบคุมพิเศษ/เสพติด/วัตถุออกฤทธิ์)
  bool get requiresIdVerification =>
      drugRiskFlags?['requires_id_verification'] == true;

  /// ห้ามฝากไว้ในตู้ล็อกเกอร์ ต้องส่งมอบให้ผู้รับโดยตรง
  bool get noSafeBoxAllowed => drugRiskFlags?['no_safe_box_allowed'] == true;

  bool get isDelivered => deliveryStatus == 'delivered';
  bool get isActive => deliveryStatus != 'delivered' && deliveryStatus != 'cancelled' && deliveryStatus != 'returned';
  String get statusLabel {
    switch (deliveryStatus) {
      case 'pending': return 'รอจัดส่ง';
      case 'preparing': return 'เตรียมสินค้า';
      case 'ready_for_pickup': return 'พร้อมให้รับ';
      case 'picked_up': return 'ไรเดอร์รับแล้ว';
      case 'in_transit': return 'กำลังส่ง';
      case 'arrived': return 'ถึงจุดหมาย';
      case 'delivered': return 'ส่งสำเร็จ';
      case 'failed': return 'ส่งไม่สำเร็จ';
      case 'cancelled': return 'ยกเลิก';
      case 'returned': return 'คืนสินค้า';
      default: return deliveryStatus;
    }
  }
}
