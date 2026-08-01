/// Model สำหรับ customer_packages (Prepaid Course Packages)
class CustomerPackage {
  final String id;
  final String professionId;
  final String customerId;
  final String packageName;
  final int totalSessions;
  final int usedSessions;
  final int remainingSessions;
  final double totalPrice;
  final DateTime? expiresAt;
  final String status;
  final DateTime createdAt;
  final DateTime updatedAt;

  const CustomerPackage({
    required this.id,
    required this.professionId,
    required this.customerId,
    required this.packageName,
    required this.totalSessions,
    this.usedSessions = 0,
    required this.remainingSessions,
    required this.totalPrice,
    this.expiresAt,
    this.status = 'active',
    required this.createdAt,
    required this.updatedAt,
  });

  factory CustomerPackage.fromJson(Map<String, dynamic> json) {
    return CustomerPackage(
      id: json['id'] as String,
      professionId: json['profession_id'] as String,
      customerId: json['customer_id'] as String,
      packageName: json['package_name'] as String,
      totalSessions: json['total_sessions'] as int? ?? 0,
      usedSessions: json['used_sessions'] as int? ?? 0,
      remainingSessions: json['remaining_sessions'] as int? ?? 0,
      totalPrice: (json['total_price'] as num?)?.toDouble() ?? 0.0,
      expiresAt: json['expires_at'] != null ? DateTime.parse(json['expires_at'] as String) : null,
      status: json['status'] as String? ?? 'active',
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'profession_id': professionId,
      'customer_id': customerId,
      'package_name': packageName,
      'total_sessions': totalSessions,
      'used_sessions': usedSessions,
      'remaining_sessions': remainingSessions,
      'total_price': totalPrice,
      'expires_at': expiresAt?.toIso8601String(),
      'status': status,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}
