/// Model สำหรับ merchant_accounts (Settlement Core)
class MerchantAccount {
  final String id;
  final String professionId;
  final String accountName;
  final String accountNumber;
  final String bankCode;
  final String bankName;
  final String accountType; // savings, current, corporate
  final bool isPrimary;
  final bool isVerified;
  final DateTime? verifiedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  const MerchantAccount({
    required this.id,
    required this.professionId,
    required this.accountName,
    required this.accountNumber,
    required this.bankCode,
    required this.bankName,
    this.accountType = 'savings',
    this.isPrimary = false,
    this.isVerified = false,
    this.verifiedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  factory MerchantAccount.fromJson(Map<String, dynamic> json) {
    return MerchantAccount(
      id: json['id'] as String,
      professionId: json['profession_id'] as String,
      accountName: json['account_name'] as String,
      accountNumber: json['account_number'] as String,
      bankCode: json['bank_code'] as String,
      bankName: json['bank_name'] as String,
      accountType: json['account_type'] as String? ?? 'savings',
      isPrimary: json['is_primary'] as bool? ?? false,
      isVerified: json['is_verified'] as bool? ?? false,
      verifiedAt: json['verified_at'] != null
          ? DateTime.parse(json['verified_at'] as String)
          : null,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'profession_id': professionId,
      'account_name': accountName,
      'account_number': accountNumber,
      'bank_code': bankCode,
      'bank_name': bankName,
      'account_type': accountType,
      'is_primary': isPrimary,
      'is_verified': isVerified,
      'verified_at': verifiedAt?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}
