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
  });

  factory ConsultationRequestModel.fromJson(Map<String, dynamic> json) {
    return ConsultationRequestModel(
      id: json['id'],
      userId: json['user_id'],
      packageId: json['package_id'],
      packageName: json['package_name'],
      price: json['price']?.toDouble() ?? 0.0,
      bodyArea: json['body_area'] ?? {},
      symptomsChart: json['symptoms_chart'] ?? {},
      status: json['status'] ?? 'pending',
      createdAt: DateTime.parse(json['created_at']),
      updatedAt: DateTime.parse(json['updated_at']),
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
    };
  }
}
