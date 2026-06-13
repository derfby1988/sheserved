/// Model สำหรับ chart_of_accounts (ผังบัญชี)
class ChartOfAccount {
  final String id;
  final String professionId;
  final String accountCode;
  final String accountName;
  final String accountType; // asset, liability, equity, revenue, expense
  final String? parentId;
  final String? standardAccountId;
  final bool isActive;
  final bool isCustom;
  final DateTime createdAt;
  final DateTime updatedAt;

  const ChartOfAccount({
    required this.id,
    required this.professionId,
    required this.accountCode,
    required this.accountName,
    required this.accountType,
    this.parentId,
    this.standardAccountId,
    this.isActive = true,
    this.isCustom = false,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ChartOfAccount.fromJson(Map<String, dynamic> json) {
    final rawType = json['account_type'];
    final normalizedType = switch (rawType) {
      1 || '1' => 'asset',
      2 || '2' => 'liability',
      3 || '3' => 'equity',
      4 || '4' => 'revenue',
      5 || '5' => 'expense',
      _ => rawType?.toString() ?? '',
    };

    return ChartOfAccount(
      id: json['id'] as String,
      professionId: json['profession_id'] as String,
      accountCode: json['account_code'] as String,
      accountName: json['account_name'] as String,
      accountType: normalizedType,
      parentId: json['parent_id'] as String?,
      standardAccountId: json['standard_account_id'] as String?,
      isActive: json['is_active'] as bool? ?? true,
      isCustom: json['is_custom'] as bool? ?? false,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'profession_id': professionId,
      'account_code': accountCode,
      'account_name': accountName,
      'account_type': accountType,
      'parent_id': parentId,
      'standard_account_id': standardAccountId,
      'is_active': isActive,
      'is_custom': isCustom,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  String get typeLabel {
    switch (accountType) {
      case 'asset': return 'สินทรัพย์';
      case 'liability': return 'หนี้สิน';
      case 'equity': return 'ทุน';
      case 'revenue': return 'รายได้';
      case 'expense': return 'ค่าใช้จ่าย';
      default: return accountType;
    }
  }
}
