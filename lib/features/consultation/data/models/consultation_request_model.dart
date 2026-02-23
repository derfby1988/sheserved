class ConsultationRequestModel {
  final String id;
  final String userId;
  final String? packageId;
  final String packageName;
  final double price;
  final Map<String, dynamic> bodyArea;
  final Map<String, dynamic> symptomsChart;
  final String status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<SymptomPoint> symptoms; // Normalized child list

  ConsultationRequestModel({
    required this.id,
    required this.userId,
    this.packageId,
    required this.packageName,
    required this.price,
    this.bodyArea = const {},
    this.symptomsChart = const {},
    this.status = 'pending',
    required this.createdAt,
    required this.updatedAt,
    this.symptoms = const [],
  });

  factory ConsultationRequestModel.fromJson(Map<String, dynamic> json) {
    return ConsultationRequestModel(
      id: json['id'],
      userId: json['user_id'],
      packageId: json['package_id'],
      packageName: json['package_name'],
      price: (json['price'] is num) ? json['price'].toDouble() : 0.0,
      bodyArea: json['body_area'] ?? {},
      symptomsChart: json['symptoms_chart'] ?? {},
      status: json['status'] ?? 'pending',
      createdAt: json['created_at'] != null 
          ? DateTime.parse(json['created_at']) 
          : DateTime.now(),
      updatedAt: json['updated_at'] != null 
          ? DateTime.parse(json['updated_at']) 
          : DateTime.now(),
      symptoms: (json['symptoms'] as List?)
              ?.map((e) => SymptomPoint.fromJson(e))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'package_id': packageId,
      'package_name': packageName,
      'price': price,
      'body_area': bodyArea,
      'symptoms_chart': symptomsChart,
      'status': status,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      // symptoms usually handled separately for inserts
    };
  }

  ConsultationRequestModel copyWith({
    Map<String, dynamic>? bodyArea,
    List<SymptomPoint>? symptoms,
  }) {
    return ConsultationRequestModel(
      id: id,
      userId: userId,
      packageId: packageId,
      packageName: packageName,
      price: price,
      bodyArea: bodyArea ?? this.bodyArea,
      symptomsChart: symptomsChart,
      status: status,
      createdAt: createdAt,
      updatedAt: updatedAt,
      symptoms: symptoms ?? this.symptoms,
    );
  }
}

class SymptomPoint {
  final String? id;
  final String regionId;
  final String side;
  final String symptom;
  final String displayLabel;

  SymptomPoint({
    this.id,
    required this.regionId,
    required this.side,
    required this.symptom,
    required this.displayLabel,
  });

  factory SymptomPoint.fromJson(Map<String, dynamic> json) {
    return SymptomPoint(
      id: json['id'],
      regionId: json['region_id'] ?? '',
      side: json['side'] ?? '',
      symptom: json['symptom'] ?? '',
      displayLabel: json['display_label'] ?? '',
    );
  }

  Map<String, dynamic> toJson(String requestId) {
    return {
      'request_id': requestId,
      'region_id': regionId,
      'side': side,
      'symptom': symptom,
      'display_label': displayLabel,
    };
  }
}
