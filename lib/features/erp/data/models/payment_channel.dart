/// Model สำหรับ payment_channels (Payment Gateway Configuration)
class PaymentChannel {
  final String id;
  final String professionId;
  final String channelCode;
  final String channelName;
  final String channelType;
  final bool isEnabled;
  final bool isDefault;
  final Map<String, dynamic> config;
  final double feePercent;
  final int displayOrder;
  final String? iconName;
  final DateTime createdAt;
  final DateTime updatedAt;

  const PaymentChannel({
    required this.id,
    required this.professionId,
    required this.channelCode,
    required this.channelName,
    this.channelType = 'other',
    this.isEnabled = true,
    this.isDefault = false,
    this.config = const {},
    this.feePercent = 0,
    this.displayOrder = 0,
    this.iconName,
    required this.createdAt,
    required this.updatedAt,
  });

  factory PaymentChannel.fromJson(Map<String, dynamic> json) {
    return PaymentChannel(
      id: json['id'] as String,
      professionId: json['profession_id'] as String,
      channelCode: json['channel_code'] as String,
      channelName: json['channel_name'] as String,
      channelType: json['channel_type'] as String? ?? 'other',
      isEnabled: json['is_enabled'] as bool? ?? true,
      isDefault: json['is_default'] as bool? ?? false,
      config: (json['config'] as Map<String, dynamic>?) ?? const {},
      feePercent: (json['fee_percent'] as num?)?.toDouble() ?? 0,
      displayOrder: json['display_order'] as int? ?? 0,
      iconName: json['icon_name'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'profession_id': professionId,
      'channel_code': channelCode,
      'channel_name': channelName,
      'channel_type': channelType,
      'is_enabled': isEnabled,
      'is_default': isDefault,
      'config': config,
      'fee_percent': feePercent,
      'display_order': displayOrder,
      'icon_name': iconName,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  PaymentChannel copyWith({
    String? id,
    String? professionId,
    String? channelCode,
    String? channelName,
    String? channelType,
    bool? isEnabled,
    bool? isDefault,
    Map<String, dynamic>? config,
    double? feePercent,
    int? displayOrder,
    String? iconName,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return PaymentChannel(
      id: id ?? this.id,
      professionId: professionId ?? this.professionId,
      channelCode: channelCode ?? this.channelCode,
      channelName: channelName ?? this.channelName,
      channelType: channelType ?? this.channelType,
      isEnabled: isEnabled ?? this.isEnabled,
      isDefault: isDefault ?? this.isDefault,
      config: config ?? this.config,
      feePercent: feePercent ?? this.feePercent,
      displayOrder: displayOrder ?? this.displayOrder,
      iconName: iconName ?? this.iconName,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Map icon_name to Flutter IconData (fallback mapping)
  static const Map<String, String> iconMap = {
    'money': 'Icons.money',
    'qr_code': 'Icons.qr_code',
    'credit_card': 'Icons.credit_card',
    'account_balance': 'Icons.account_balance',
    'wallet': 'Icons.account_balance_wallet',
    'phone': 'Icons.phone_android',
  };
}
