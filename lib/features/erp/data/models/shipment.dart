/// Model สำหรับ shipments (Delivery Extension)
class Shipment {
  final String id;
  final String professionId;
  final String deliveryOrderId;
  final String? carrierConfigId;
  final String? trackingNumber;
  final String shipmentStatus; // pending, label_created, picked_up, in_transit, out_for_delivery, delivered, failed, returned
  final double weightKg;
  final Map<String, dynamic> dimensionsCm;
  final double shippingCost;
  final String? labelUrl;
  final DateTime? pickedUpAt;
  final DateTime? deliveredAt;
  final Map<String, dynamic> carrierRawResponse;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Shipment({
    required this.id,
    required this.professionId,
    required this.deliveryOrderId,
    this.carrierConfigId,
    this.trackingNumber,
    this.shipmentStatus = 'pending',
    this.weightKg = 0,
    this.dimensionsCm = const {},
    this.shippingCost = 0,
    this.labelUrl,
    this.pickedUpAt,
    this.deliveredAt,
    this.carrierRawResponse = const {},
    required this.createdAt,
    required this.updatedAt,
  });

  factory Shipment.fromJson(Map<String, dynamic> json) {
    return Shipment(
      id: json['id'] as String,
      professionId: json['profession_id'] as String,
      deliveryOrderId: json['delivery_order_id'] as String,
      carrierConfigId: json['carrier_config_id'] as String?,
      trackingNumber: json['tracking_number'] as String?,
      shipmentStatus: json['shipment_status'] as String? ?? 'pending',
      weightKg: (json['weight_kg'] as num?)?.toDouble() ?? 0,
      dimensionsCm: json['dimensions_cm'] as Map<String, dynamic>? ?? {},
      shippingCost: (json['shipping_cost'] as num?)?.toDouble() ?? 0,
      labelUrl: json['label_url'] as String?,
      pickedUpAt: json['picked_up_at'] != null
          ? DateTime.parse(json['picked_up_at'] as String)
          : null,
      deliveredAt: json['delivered_at'] != null
          ? DateTime.parse(json['delivered_at'] as String)
          : null,
      carrierRawResponse: json['carrier_raw_response'] as Map<String, dynamic>? ?? {},
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'profession_id': professionId,
      'delivery_order_id': deliveryOrderId,
      'carrier_config_id': carrierConfigId,
      'tracking_number': trackingNumber,
      'shipment_status': shipmentStatus,
      'weight_kg': weightKg,
      'dimensions_cm': dimensionsCm,
      'shipping_cost': shippingCost,
      'label_url': labelUrl,
      'picked_up_at': pickedUpAt?.toIso8601String(),
      'delivered_at': deliveredAt?.toIso8601String(),
      'carrier_raw_response': carrierRawResponse,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}
