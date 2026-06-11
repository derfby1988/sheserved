/// Model สำหรับ riders (Logistics Core)
class Rider {
  final String id;
  final String professionId;
  final String? userId;
  final String riderCode;
  final String fullName;
  final String phone;
  final String? email;
  final String vehicleType; // motorcycle, car, bicycle, van
  final String? licensePlate;
  final bool isActive;
  final bool isAvailable;
  final double? currentLat;
  final double? currentLng;
  final DateTime? currentLocationUpdatedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Rider({
    required this.id,
    required this.professionId,
    this.userId,
    required this.riderCode,
    required this.fullName,
    required this.phone,
    this.email,
    this.vehicleType = 'motorcycle',
    this.licensePlate,
    this.isActive = true,
    this.isAvailable = true,
    this.currentLat,
    this.currentLng,
    this.currentLocationUpdatedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Rider.fromJson(Map<String, dynamic> json) {
    return Rider(
      id: json['id'] as String,
      professionId: json['profession_id'] as String,
      userId: json['user_id'] as String?,
      riderCode: json['rider_code'] as String,
      fullName: json['full_name'] as String,
      phone: json['phone'] as String,
      email: json['email'] as String?,
      vehicleType: json['vehicle_type'] as String? ?? 'motorcycle',
      licensePlate: json['license_plate'] as String?,
      isActive: json['is_active'] as bool? ?? true,
      isAvailable: json['is_available'] as bool? ?? true,
      currentLat: (json['current_lat'] as num?)?.toDouble(),
      currentLng: (json['current_lng'] as num?)?.toDouble(),
      currentLocationUpdatedAt: json['current_location_updated_at'] != null
          ? DateTime.parse(json['current_location_updated_at'] as String)
          : null,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'profession_id': professionId,
      'user_id': userId,
      'rider_code': riderCode,
      'full_name': fullName,
      'phone': phone,
      'email': email,
      'vehicle_type': vehicleType,
      'license_plate': licensePlate,
      'is_active': isActive,
      'is_available': isAvailable,
      'current_lat': currentLat,
      'current_lng': currentLng,
      'current_location_updated_at': currentLocationUpdatedAt?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  String get vehicleLabel {
    switch (vehicleType) {
      case 'motorcycle': return 'มอเตอร์ไซค์';
      case 'car': return 'รถยนต์';
      case 'bicycle': return 'จักรยาน';
      case 'van': return 'รถตู้';
      default: return vehicleType;
    }
  }
}
