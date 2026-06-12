/// Model สำหรับ route_stops (Logistics Core)
class RouteStop {
  final String id;
  final String deliveryRunId;
  final String deliveryOrderId;
  final int stopSequence;
  final String status; // pending, arrived, delivered, failed, skipped
  final DateTime? estimatedArrival;
  final DateTime? actualArrival;
  final String? deliveryPhotoUrl;
  final String? signatureUrl;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  const RouteStop({
    required this.id,
    required this.deliveryRunId,
    required this.deliveryOrderId,
    this.stopSequence = 1,
    this.status = 'pending',
    this.estimatedArrival,
    this.actualArrival,
    this.deliveryPhotoUrl,
    this.signatureUrl,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
  });

  factory RouteStop.fromJson(Map<String, dynamic> json) {
    return RouteStop(
      id: json['id'] as String,
      deliveryRunId: json['delivery_run_id'] as String,
      deliveryOrderId: json['delivery_order_id'] as String,
      stopSequence: json['stop_sequence'] as int? ?? 1,
      status: json['status'] as String? ?? 'pending',
      estimatedArrival: json['estimated_arrival'] != null
          ? DateTime.parse(json['estimated_arrival'] as String)
          : null,
      actualArrival: json['actual_arrival'] != null
          ? DateTime.parse(json['actual_arrival'] as String)
          : null,
      deliveryPhotoUrl: json['delivery_photo_url'] as String?,
      signatureUrl: json['signature_url'] as String?,
      notes: json['notes'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'delivery_run_id': deliveryRunId,
      'delivery_order_id': deliveryOrderId,
      'stop_sequence': stopSequence,
      'status': status,
      'estimated_arrival': estimatedArrival?.toIso8601String(),
      'actual_arrival': actualArrival?.toIso8601String(),
      'delivery_photo_url': deliveryPhotoUrl,
      'signature_url': signatureUrl,
      'notes': notes,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}
