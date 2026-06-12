/// Model สำหรับ proof_of_deliveries (Delivery Extension)
class ProofOfDelivery {
  final String id;
  final String professionId;
  final String deliveryOrderId;
  final String? routeStopId;
  final String proofType; // photo, signature, qr_scan, otp, id_card, note
  final String? proofUrl;
  final Map<String, dynamic> metadata;
  final String? verifiedBy;
  final DateTime? verifiedAt;
  final DateTime createdAt;

  const ProofOfDelivery({
    required this.id,
    required this.professionId,
    required this.deliveryOrderId,
    this.routeStopId,
    required this.proofType,
    this.proofUrl,
    this.metadata = const {},
    this.verifiedBy,
    this.verifiedAt,
    required this.createdAt,
  });

  factory ProofOfDelivery.fromJson(Map<String, dynamic> json) {
    return ProofOfDelivery(
      id: json['id'] as String,
      professionId: json['profession_id'] as String,
      deliveryOrderId: json['delivery_order_id'] as String,
      routeStopId: json['route_stop_id'] as String?,
      proofType: json['proof_type'] as String,
      proofUrl: json['proof_url'] as String?,
      metadata: json['metadata'] as Map<String, dynamic>? ?? {},
      verifiedBy: json['verified_by'] as String?,
      verifiedAt: json['verified_at'] != null
          ? DateTime.parse(json['verified_at'] as String)
          : null,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'profession_id': professionId,
      'delivery_order_id': deliveryOrderId,
      'route_stop_id': routeStopId,
      'proof_type': proofType,
      'proof_url': proofUrl,
      'metadata': metadata,
      'verified_by': verifiedBy,
      'verified_at': verifiedAt?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
    };
  }
}
