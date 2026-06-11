/// ข้อมูลสำหรับ Organization Header / Settings
/// รวม profession + branches ที่ดึงจาก RPC get_organization_header
class OrganizationSettings {
  final String professionId;
  final String professionName;
  final String? professionNameEn;
  final String? professionIconName;
  final String? professionColorHex;
  final String? logoUrl;
  final String? taxId;
  final String? phone;
  final String? email;
  final String? address;
  final String currency;
  final String language;
  final String timezone;
  final String storageMode;
  final String? selfHostApiUrl;
  final List<OrganizationBranch> branches;
  final String? mainBranchId;
  final int totalBranches;

  const OrganizationSettings({
    required this.professionId,
    required this.professionName,
    this.professionNameEn,
    this.professionIconName,
    this.professionColorHex,
    this.logoUrl,
    this.taxId,
    this.phone,
    this.email,
    this.address,
    this.currency = 'THB',
    this.language = 'th',
    this.timezone = 'Asia/Bangkok',
    this.storageMode = 'cloud',
    this.selfHostApiUrl,
    this.branches = const [],
    this.mainBranchId,
    this.totalBranches = 0,
  });

  /// สาขาที่เลือก (default = main branch)
  OrganizationBranch? get selectedBranch {
    if (mainBranchId == null) return branches.isNotEmpty ? branches.first : null;
    try {
      return branches.firstWhere((b) => b.id == mainBranchId);
    } catch (_) {
      return branches.isNotEmpty ? branches.first : null;
    }
  }

  String get displayName => professionName;

  bool get hasLogo => logoUrl != null && logoUrl!.isNotEmpty;

  bool get isSelfHosted => storageMode == 'self_host';

  factory OrganizationSettings.fromJson(Map<String, dynamic> json) {
    final profession = json['profession'] as Map<String, dynamic>? ?? {};
    final branchesList = (json['branches'] as List? ?? [])
        .map((b) => OrganizationBranch.fromJson(b as Map<String, dynamic>))
        .toList();

    return OrganizationSettings(
      professionId: profession['profession_id'] ?? json['profession_id'] ?? '',
      professionName: profession['profession_name'] ?? '',
      professionNameEn: profession['profession_name_en'],
      professionIconName: profession['icon_name'] ?? json['icon_name'],
      professionColorHex: profession['color_hex'] ?? json['color_hex'],
      logoUrl: profession['logo_url'],
      taxId: profession['tax_id'],
      phone: profession['phone'],
      email: profession['email'],
      address: profession['address'],
      currency: profession['currency'] ?? 'THB',
      language: profession['language'] ?? 'th',
      timezone: profession['timezone'] ?? 'Asia/Bangkok',
      storageMode: profession['storage_mode'] ?? 'cloud',
      selfHostApiUrl: profession['self_host_api_url'],
      branches: branchesList,
      mainBranchId: json['main_branch_id'],
      totalBranches: json['total_branches'] ?? branchesList.length,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'profession_id': professionId,
      'profession_name': professionName,
      'profession_name_en': professionNameEn,
      'logo_url': logoUrl,
      'tax_id': taxId,
      'phone': phone,
      'email': email,
      'address': address,
      'currency': currency,
      'language': language,
      'timezone': timezone,
      'storage_mode': storageMode,
      'self_host_api_url': selfHostApiUrl,
      'branches': branches.map((b) => b.toJson()).toList(),
      'main_branch_id': mainBranchId,
      'total_branches': totalBranches,
    };
  }

  OrganizationSettings copyWith({
    String? professionId,
    String? professionName,
    String? professionNameEn,
    String? professionIconName,
    String? professionColorHex,
    String? logoUrl,
    String? taxId,
    String? phone,
    String? email,
    String? address,
    String? currency,
    String? language,
    String? timezone,
    String? storageMode,
    String? selfHostApiUrl,
    List<OrganizationBranch>? branches,
    String? mainBranchId,
    int? totalBranches,
  }) {
    return OrganizationSettings(
      professionId: professionId ?? this.professionId,
      professionName: professionName ?? this.professionName,
      professionNameEn: professionNameEn ?? this.professionNameEn,
      professionIconName: professionIconName ?? this.professionIconName,
      professionColorHex: professionColorHex ?? this.professionColorHex,
      logoUrl: logoUrl ?? this.logoUrl,
      taxId: taxId ?? this.taxId,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      address: address ?? this.address,
      currency: currency ?? this.currency,
      language: language ?? this.language,
      timezone: timezone ?? this.timezone,
      storageMode: storageMode ?? this.storageMode,
      selfHostApiUrl: selfHostApiUrl ?? this.selfHostApiUrl,
      branches: branches ?? this.branches,
      mainBranchId: mainBranchId ?? this.mainBranchId,
      totalBranches: totalBranches ?? this.totalBranches,
    );
  }
}

/// สาขาขององค์กร
class OrganizationBranch {
  final String id;
  final String branchCode;
  final String branchName;
  final String? taxId;
  final String? address;
  final String? phone;
  final String? email;
  final String? branchTaxCode;
  final bool isMainBranch;
  final bool isActive;

  const OrganizationBranch({
    required this.id,
    required this.branchCode,
    required this.branchName,
    this.taxId,
    this.address,
    this.phone,
    this.email,
    this.branchTaxCode,
    this.isMainBranch = false,
    this.isActive = true,
  });

  String get displayName => '$branchName ($branchCode)';

  factory OrganizationBranch.fromJson(Map<String, dynamic> json) {
    return OrganizationBranch(
      id: json['branch_id'] ?? json['id'] ?? '',
      branchCode: json['branch_code'] ?? '',
      branchName: json['branch_name'] ?? '',
      taxId: json['tax_id'],
      address: json['address'],
      phone: json['phone'],
      email: json['email'],
      branchTaxCode: json['branch_tax_code'],
      isMainBranch: json['is_main_branch'] ?? false,
      isActive: json['is_active'] ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'branch_id': id,
      'branch_code': branchCode,
      'branch_name': branchName,
      'tax_id': taxId,
      'address': address,
      'phone': phone,
      'email': email,
      'branch_tax_code': branchTaxCode,
      'is_main_branch': isMainBranch,
      'is_active': isActive,
    };
  }

  OrganizationBranch copyWith({
    String? id,
    String? branchCode,
    String? branchName,
    String? taxId,
    String? address,
    String? phone,
    String? email,
    String? branchTaxCode,
    bool? isMainBranch,
    bool? isActive,
  }) {
    return OrganizationBranch(
      id: id ?? this.id,
      branchCode: branchCode ?? this.branchCode,
      branchName: branchName ?? this.branchName,
      taxId: taxId ?? this.taxId,
      address: address ?? this.address,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      branchTaxCode: branchTaxCode ?? this.branchTaxCode,
      isMainBranch: isMainBranch ?? this.isMainBranch,
      isActive: isActive ?? this.isActive,
    );
  }
}
