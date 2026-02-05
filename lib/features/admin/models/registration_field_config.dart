/// ประเภทของ Input Field
enum FieldType {
  text,
  email,
  phone,
  number,
  date,
  image,
  multilineText,
  dropdown,
}

extension FieldTypeExtension on FieldType {
  String get displayName {
    switch (this) {
      case FieldType.text:
        return 'ข้อความ';
      case FieldType.email:
        return 'อีเมล';
      case FieldType.phone:
        return 'เบอร์โทรศัพท์';
      case FieldType.number:
        return 'ตัวเลข';
      case FieldType.date:
        return 'วันที่';
      case FieldType.image:
        return 'รูปภาพ';
      case FieldType.multilineText:
        return 'ข้อความหลายบรรทัด';
      case FieldType.dropdown:
        return 'ตัวเลือก (Dropdown)';
    }
  }

  String get iconName {
    switch (this) {
      case FieldType.text:
        return 'text_fields';
      case FieldType.email:
        return 'email';
      case FieldType.phone:
        return 'phone';
      case FieldType.number:
        return 'numbers';
      case FieldType.date:
        return 'calendar_today';
      case FieldType.image:
        return 'image';
      case FieldType.multilineText:
        return 'notes';
      case FieldType.dropdown:
        return 'arrow_drop_down_circle';
    }
  }

  static FieldType fromString(String value) {
    switch (value) {
      case 'text':
        return FieldType.text;
      case 'email':
        return FieldType.email;
      case 'phone':
        return FieldType.phone;
      case 'number':
        return FieldType.number;
      case 'date':
        return FieldType.date;
      case 'image':
        return FieldType.image;
      case 'multilineText':
        return FieldType.multilineText;
      case 'dropdown':
        return FieldType.dropdown;
      default:
        return FieldType.text;
    }
  }
}

/// Model สำหรับกำหนดค่า Field แต่ละตัว
class RegistrationFieldConfig {
  final String id;
  final String professionId;
  final String fieldId;
  final String label;
  final String? hint;
  final FieldType fieldType;
  final bool isRequired;
  final int order;
  final String? iconName;
  final List<String>? dropdownOptions; // สำหรับ dropdown
  final String? validationRegex;
  final String? validationMessage;
  final bool isActive;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const RegistrationFieldConfig({
    required this.id,
    required this.professionId,
    required this.fieldId,
    required this.label,
    this.hint,
    required this.fieldType,
    this.isRequired = false,
    this.order = 0,
    this.iconName,
    this.dropdownOptions,
    this.validationRegex,
    this.validationMessage,
    this.isActive = true,
    this.createdAt,
    this.updatedAt,
  });

  RegistrationFieldConfig copyWith({
    String? id,
    String? professionId,
    String? fieldId,
    String? label,
    String? hint,
    FieldType? fieldType,
    bool? isRequired,
    int? order,
    String? iconName,
    List<String>? dropdownOptions,
    String? validationRegex,
    String? validationMessage,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return RegistrationFieldConfig(
      id: id ?? this.id,
      professionId: professionId ?? this.professionId,
      fieldId: fieldId ?? this.fieldId,
      label: label ?? this.label,
      hint: hint ?? this.hint,
      fieldType: fieldType ?? this.fieldType,
      isRequired: isRequired ?? this.isRequired,
      order: order ?? this.order,
      iconName: iconName ?? this.iconName,
      dropdownOptions: dropdownOptions ?? this.dropdownOptions,
      validationRegex: validationRegex ?? this.validationRegex,
      validationMessage: validationMessage ?? this.validationMessage,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'profession_id': professionId,
      'field_id': fieldId,
      'label': label,
      'hint': hint,
      'field_type': fieldType.name,
      'is_required': isRequired,
      'field_order': order,
      'icon_name': iconName,
      'dropdown_options': dropdownOptions,
      'validation_regex': validationRegex,
      'validation_message': validationMessage,
      'is_active': isActive,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  factory RegistrationFieldConfig.fromJson(Map<String, dynamic> json) {
    return RegistrationFieldConfig(
      id: json['id'] ?? '',
      professionId: json['profession_id'] ?? '',
      fieldId: json['field_id'] ?? json['id'] ?? '',
      label: json['label'] ?? '',
      hint: json['hint'],
      fieldType: FieldTypeExtension.fromString(json['field_type'] ?? 'text'),
      isRequired: json['is_required'] ?? false,
      order: json['field_order'] ?? json['order'] ?? 0,
      iconName: json['icon_name'],
      dropdownOptions: json['dropdown_options'] != null
          ? List<String>.from(json['dropdown_options'])
          : null,
      validationRegex: json['validation_regex'],
      validationMessage: json['validation_message'],
      isActive: json['is_active'] ?? true,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'])
          : null,
    );
  }
}
