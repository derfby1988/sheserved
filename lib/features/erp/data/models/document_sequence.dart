/// Model สำหรับ document_sequences (ลำดับเลขที่เอกสาร)
class DocumentSequence {
  final String id;
  final String professionId;
  final String? branchId;
  final String prefix; // PR, PO, GR
  final int year;
  final int lastNumber;
  final DateTime createdAt;
  final DateTime updatedAt;

  const DocumentSequence({
    required this.id,
    required this.professionId,
    this.branchId,
    required this.prefix,
    required this.year,
    required this.lastNumber,
    required this.createdAt,
    required this.updatedAt,
  });

  factory DocumentSequence.fromJson(Map<String, dynamic> json) {
    return DocumentSequence(
      id: json['id'] as String,
      professionId: json['profession_id'] as String,
      branchId: json['branch_id'] as String?,
      prefix: json['prefix'] as String,
      year: json['year'] as int? ?? DateTime.now().year,
      lastNumber: json['last_number'] as int? ?? 0,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'profession_id': professionId,
      'branch_id': branchId,
      'prefix': prefix,
      'year': year,
      'last_number': lastNumber,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  String get nextDocumentNumber =>
      '$prefix-$year-${lastNumber.toString().padLeft(5, '0')}';
}
