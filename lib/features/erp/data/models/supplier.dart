/// Model สำหรับ suppliers (Procurement)
class Supplier {
  final String id;
  final String professionId;
  final String supplierName;
  final String? contactName;
  final String? phone;
  final String? email;
  final String? address;
  final String? taxId;
  final String paymentTerms;
  final int leadTimeDays;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Supplier({
    required this.id,
    required this.professionId,
    required this.supplierName,
    this.contactName,
    this.phone,
    this.email,
    this.address,
    this.taxId,
    this.paymentTerms = 'net_30',
    this.leadTimeDays = 7,
    this.isActive = true,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Supplier.fromJson(Map<String, dynamic> json) {
    return Supplier(
      id: json['id'] as String,
      professionId: json['profession_id'] as String,
      supplierName: json['supplier_name'] as String,
      contactName: json['contact_name'] as String?,
      phone: json['phone'] as String?,
      email: json['email'] as String?,
      address: json['address'] as String?,
      taxId: json['tax_id'] as String?,
      paymentTerms: json['payment_terms'] as String? ?? 'net_30',
      leadTimeDays: json['lead_time_days'] as int? ?? 7,
      isActive: json['is_active'] as bool? ?? true,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'profession_id': professionId,
      'supplier_name': supplierName,
      'contact_name': contactName,
      'phone': phone,
      'email': email,
      'address': address,
      'tax_id': taxId,
      'payment_terms': paymentTerms,
      'lead_time_days': leadTimeDays,
      'is_active': isActive,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}
