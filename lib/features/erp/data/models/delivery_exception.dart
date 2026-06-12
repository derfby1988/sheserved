/// Model สำหรับ delivery_exceptions (Delivery Extension)
class DeliveryException {
  final String id;
  final String professionId;
  final String deliveryOrderId;
  final String? routeStopId;
  final String exceptionType; // recipient_not_available, address_incorrect, package_damaged, refused_by_recipient, vehicle_breakdown, weather_delay, traffic_delay, other
  final String severity; // low, medium, high, critical
  final String? description;
  final String? photoUrl;
  final double? gpsLat;
  final double? gpsLng;
  final DateTime? resolvedAt;
  final String? resolution;
  final DateTime createdAt;

  const DeliveryException({
    required this.id,
    required this.professionId,
    required this.deliveryOrderId,
    this.routeStopId,
    required this.exceptionType,
    this.severity = 'medium',
    this.description,
    this.photoUrl,
    this.gpsLat,
    this.gpsLng,
    this.resolvedAt,
    this.resolution,
    required this.createdAt,
  });

  factory DeliveryException.fromJson(Map<String, dynamic> json) {
    return DeliveryException(
      id: json['id'] as String,
      professionId: json['profession_id'] as String,
      deliveryOrderId: json['delivery_order_id'] as String,
      routeStopId: json['route_stop_id'] as String?,
      exceptionType: json['exception_type'] as String,
      severity: json['severity'] as String? ?? 'medium',
      description: json['description'] as String?,
      photoUrl: json['photo_url'] as String?,
      gpsLat: (json['gps_lat'] as num?)?.toDouble(),
      gpsLng: (json['gps_lng'] as num?)?.toDouble(),
      resolvedAt: json['resolved_at'] != null
          ? DateTime.parse(json['resolved_at'] as String)
          : null,
      resolution: json['resolution'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'profession_id': professionId,
      'delivery_order_id': deliveryOrderId,
      'route_stop_id': routeStopId,
      'exception_type': exceptionType,
      'severity': severity,
      'description': description,
      'photo_url': photoUrl,
      'gps_lat': gpsLat,
      'gps_lng': gpsLng,
      'resolved_at': resolvedAt?.toIso8601String(),
      'resolution': resolution,
      'created_at': createdAt.toIso8601String(),
    };
  }
}
