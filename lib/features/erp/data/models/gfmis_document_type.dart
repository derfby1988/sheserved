/// Model สำหรับ gfmis_document_types (GFMIS Lookup Table)
class GfmisDocumentType {
  final String code;
  final String nameTh;
  final String? nameEn;
  final String sapTransactionCode;
  final String? formNumber;
  final String category;
  final String? description;
  final bool isActive;
  final DateTime createdAt;

  const GfmisDocumentType({
    required this.code,
    required this.nameTh,
    this.nameEn,
    required this.sapTransactionCode,
    this.formNumber,
    required this.category,
    this.description,
    this.isActive = true,
    required this.createdAt,
  });

  factory GfmisDocumentType.fromJson(Map<String, dynamic> json) {
    return GfmisDocumentType(
      code: json['code'] as String,
      nameTh: json['name_th'] as String,
      nameEn: json['name_en'] as String?,
      sapTransactionCode: json['sap_transaction_code'] as String,
      formNumber: json['form_number'] as String?,
      category: json['category'] as String,
      description: json['description'] as String?,
      isActive: json['is_active'] as bool? ?? true,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'code': code,
      'name_th': nameTh,
      'name_en': nameEn,
      'sap_transaction_code': sapTransactionCode,
      'form_number': formNumber,
      'category': category,
      'description': description,
      'is_active': isActive,
      'created_at': createdAt.toIso8601String(),
    };
  }

  String get categoryLabel {
    switch (category) {
      case 'general_ledger': return 'บัญชีแยกประเภท';
      case 'adjustment': return 'ปรับปรุง';
      case 'accounts_receivable': return 'ลูกหนี้';
      case 'accounts_payable': return 'เจ้าหนี้';
      case 'internal_transfer': return 'โอนภายใน';
      case 'special_funds': return 'เงินพิเศษ';
      case 'revenue': return 'รายได้';
      case 'expense': return 'ค่าใช้จ่าย';
      case 'other': return 'อื่น ๆ';
      default: return category;
    }
  }
}
