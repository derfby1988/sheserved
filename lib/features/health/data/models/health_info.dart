/// Health Info Model - ข้อมูลสุขภาพของผู้ใช้
class HealthInfo {
  final String gender;
  final int age;
  final double height; // cm
  final double weight; // kg
  final double bmi;
  final int? healthScore; // 0-100

  const HealthInfo({
    required this.gender,
    required this.age,
    required this.height,
    required this.weight,
    required this.bmi,
    this.healthScore,
  });

  /// คำนวณ BMI จากส่วนสูงและน้ำหนัก
  static double calculateBMI(double heightCm, double weightKg) {
    final heightM = heightCm / 100;
    return weightKg / (heightM * heightM);
  }

  /// คำนวณ Health Score (simplified algorithm)
  /// Based on BMI, age, and other factors
  static int calculateHealthScore({
    required double bmi,
    required int age,
    required String gender,
  }) {
    int score = 100;
    
    // BMI Score (optimal: 18.5-24.9)
    if (bmi < 18.5) {
      // Underweight
      score -= ((18.5 - bmi) * 3).round();
    } else if (bmi >= 25 && bmi < 30) {
      // Overweight
      score -= ((bmi - 24.9) * 3).round();
    } else if (bmi >= 30) {
      // Obese
      score -= ((bmi - 24.9) * 5).round();
    }
    
    // Age factor (slight reduction for older ages)
    if (age > 40) {
      score -= ((age - 40) * 0.2).round();
    }
    
    // Ensure score is within bounds
    return score.clamp(0, 100);
  }

  /// Get BMI Category
  String get bmiCategory {
    if (bmi < 18.5) return 'น้ำหนักต่ำกว่าเกณฑ์';
    if (bmi < 23) return 'น้ำหนักปกติ';
    if (bmi < 25) return 'น้ำหนักเกิน';
    if (bmi < 30) return 'อ้วนระดับ 1';
    return 'อ้วนระดับ 2';
  }

  /// Get BMI Category Color
  String get bmiCategoryColor {
    if (bmi < 18.5) return 'warning';
    if (bmi < 23) return 'success';
    if (bmi < 25) return 'warning';
    return 'danger';
  }

  factory HealthInfo.fromJson(Map<String, dynamic> json) {
    final height = (json['height'] as num?)?.toDouble() ?? 165.0;
    final weight = (json['weight'] as num?)?.toDouble() ?? 65.0;
    final bmi = json['bmi'] != null 
        ? (json['bmi'] as num).toDouble()
        : calculateBMI(height, weight);

    return HealthInfo(
      gender: json['gender'] ?? 'female',
      age: json['age'] ?? 25,
      height: height,
      weight: weight,
      bmi: bmi,
      healthScore: json['health_score'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'gender': gender,
      'age': age,
      'height': height,
      'weight': weight,
      'bmi': bmi,
      'health_score': healthScore,
    };
  }

  HealthInfo copyWith({
    String? gender,
    int? age,
    double? height,
    double? weight,
    double? bmi,
    int? healthScore,
  }) {
    return HealthInfo(
      gender: gender ?? this.gender,
      age: age ?? this.age,
      height: height ?? this.height,
      weight: weight ?? this.weight,
      bmi: bmi ?? this.bmi,
      healthScore: healthScore ?? this.healthScore,
    );
  }

  /// Default health info for new users
  static HealthInfo get defaultInfo => const HealthInfo(
    gender: 'female',
    age: 25,
    height: 160,
    weight: 55,
    bmi: 21.48,
    healthScore: 85,
  );
}

/// Connected Device Model
class ConnectedDevice {
  final String id;
  final String name;
  final DeviceType type;
  final bool isConnected;
  final DateTime? lastSyncAt;

  const ConnectedDevice({
    required this.id,
    required this.name,
    required this.type,
    this.isConnected = false,
    this.lastSyncAt,
  });

  factory ConnectedDevice.fromJson(Map<String, dynamic> json) {
    return ConnectedDevice(
      id: json['id'],
      name: json['name'],
      type: DeviceTypeExtension.fromString(json['type']),
      isConnected: json['is_connected'] ?? false,
      lastSyncAt: json['last_sync_at'] != null 
          ? DateTime.parse(json['last_sync_at']) 
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'type': type.value,
      'is_connected': isConnected,
      'last_sync_at': lastSyncAt?.toIso8601String(),
    };
  }
}

enum DeviceType {
  scale,
  watch,
  treadmill,
  shoes,
  heartRateMonitor,
  bloodPressure,
}

extension DeviceTypeExtension on DeviceType {
  String get value {
    switch (this) {
      case DeviceType.scale:
        return 'scale';
      case DeviceType.watch:
        return 'watch';
      case DeviceType.treadmill:
        return 'treadmill';
      case DeviceType.shoes:
        return 'shoes';
      case DeviceType.heartRateMonitor:
        return 'heart_rate_monitor';
      case DeviceType.bloodPressure:
        return 'blood_pressure';
    }
  }

  String get displayName {
    switch (this) {
      case DeviceType.scale:
        return 'เครื่องชั่ง';
      case DeviceType.watch:
        return 'นาฬิกา';
      case DeviceType.treadmill:
        return 'ลู่วิ่ง';
      case DeviceType.shoes:
        return 'รองเท้า';
      case DeviceType.heartRateMonitor:
        return 'วัดชีพจร';
      case DeviceType.bloodPressure:
        return 'วัดความดัน';
    }
  }

  static DeviceType fromString(String value) {
    switch (value) {
      case 'scale':
        return DeviceType.scale;
      case 'watch':
        return DeviceType.watch;
      case 'treadmill':
        return DeviceType.treadmill;
      case 'shoes':
        return DeviceType.shoes;
      case 'heart_rate_monitor':
        return DeviceType.heartRateMonitor;
      case 'blood_pressure':
        return DeviceType.bloodPressure;
      default:
        return DeviceType.scale;
    }
  }
}
