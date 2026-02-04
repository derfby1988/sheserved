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
}

/// ประเภทผู้ใช้งาน
enum UserType {
  consumer, // ผู้ซื้อ/ผู้รับบริการ
  expert, // ผู้เชี่ยวชาญ/ผู้ขาย/สถานบริการ/ร้านค้า
  clinic, // คลินิก/ศูนย์ฯ
}

extension UserTypeExtension on UserType {
  String get title {
    switch (this) {
      case UserType.consumer:
        return 'ผู้ซื้อ/ผู้รับบริการ';
      case UserType.expert:
        return 'ผู้เชี่ยวชาญ/ผู้ขาย/ร้านค้า';
      case UserType.clinic:
        return 'คลินิก/ศูนย์ฯ';
    }
  }

  String get shortTitle {
    switch (this) {
      case UserType.consumer:
        return 'ผู้ซื้อ';
      case UserType.expert:
        return 'ผู้เชี่ยวชาญ';
      case UserType.clinic:
        return 'คลินิก';
    }
  }
}

/// Model สำหรับกำหนดค่า Field แต่ละตัว
class RegistrationFieldConfig {
  final String id;
  final String label;
  final String? hint;
  final FieldType fieldType;
  final bool isRequired;
  final int order;
  final String? iconName;
  final List<String>? dropdownOptions; // สำหรับ dropdown
  final String? validationRegex;
  final String? validationMessage;

  const RegistrationFieldConfig({
    required this.id,
    required this.label,
    this.hint,
    required this.fieldType,
    this.isRequired = false,
    this.order = 0,
    this.iconName,
    this.dropdownOptions,
    this.validationRegex,
    this.validationMessage,
  });

  RegistrationFieldConfig copyWith({
    String? id,
    String? label,
    String? hint,
    FieldType? fieldType,
    bool? isRequired,
    int? order,
    String? iconName,
    List<String>? dropdownOptions,
    String? validationRegex,
    String? validationMessage,
  }) {
    return RegistrationFieldConfig(
      id: id ?? this.id,
      label: label ?? this.label,
      hint: hint ?? this.hint,
      fieldType: fieldType ?? this.fieldType,
      isRequired: isRequired ?? this.isRequired,
      order: order ?? this.order,
      iconName: iconName ?? this.iconName,
      dropdownOptions: dropdownOptions ?? this.dropdownOptions,
      validationRegex: validationRegex ?? this.validationRegex,
      validationMessage: validationMessage ?? this.validationMessage,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'label': label,
      'hint': hint,
      'fieldType': fieldType.name,
      'isRequired': isRequired,
      'order': order,
      'iconName': iconName,
      'dropdownOptions': dropdownOptions,
      'validationRegex': validationRegex,
      'validationMessage': validationMessage,
    };
  }

  factory RegistrationFieldConfig.fromJson(Map<String, dynamic> json) {
    return RegistrationFieldConfig(
      id: json['id'],
      label: json['label'],
      hint: json['hint'],
      fieldType: FieldType.values.firstWhere(
        (e) => e.name == json['fieldType'],
        orElse: () => FieldType.text,
      ),
      isRequired: json['isRequired'] ?? false,
      order: json['order'] ?? 0,
      iconName: json['iconName'],
      dropdownOptions: json['dropdownOptions'] != null
          ? List<String>.from(json['dropdownOptions'])
          : null,
      validationRegex: json['validationRegex'],
      validationMessage: json['validationMessage'],
    );
  }
}

/// Service สำหรับจัดการ Field Config
class RegistrationFieldConfigService {
  // Singleton pattern
  static final RegistrationFieldConfigService _instance =
      RegistrationFieldConfigService._internal();
  factory RegistrationFieldConfigService() => _instance;
  RegistrationFieldConfigService._internal() {
    _initDefaultConfigs();
  }

  // เก็บ config ของแต่ละ UserType
  final Map<UserType, List<RegistrationFieldConfig>> _configs = {};

  /// ดึง config ของ UserType
  List<RegistrationFieldConfig> getConfigsForUserType(UserType userType) {
    return List.from(_configs[userType] ?? []);
  }

  /// บันทึก config ของ UserType
  void setConfigsForUserType(
      UserType userType, List<RegistrationFieldConfig> configs) {
    _configs[userType] = configs;
  }

  /// เพิ่ม field ใหม่
  void addField(UserType userType, RegistrationFieldConfig field) {
    final configs = _configs[userType] ?? [];
    configs.add(field);
    _configs[userType] = configs;
  }

  /// อัพเดท field
  void updateField(UserType userType, RegistrationFieldConfig field) {
    final configs = _configs[userType] ?? [];
    final index = configs.indexWhere((f) => f.id == field.id);
    if (index != -1) {
      configs[index] = field;
      _configs[userType] = configs;
    }
  }

  /// ลบ field
  void removeField(UserType userType, String fieldId) {
    final configs = _configs[userType] ?? [];
    configs.removeWhere((f) => f.id == fieldId);
    _configs[userType] = configs;
  }

  /// สลับลำดับ field
  void reorderFields(UserType userType, int oldIndex, int newIndex) {
    final configs = _configs[userType] ?? [];
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }
    final item = configs.removeAt(oldIndex);
    configs.insert(newIndex, item);
    // Update order values
    for (int i = 0; i < configs.length; i++) {
      configs[i] = configs[i].copyWith(order: i);
    }
    _configs[userType] = configs;
  }

  /// Initialize default configurations
  void _initDefaultConfigs() {
    // Consumer defaults
    _configs[UserType.consumer] = [
      const RegistrationFieldConfig(
        id: 'email',
        label: 'อีเมล',
        hint: 'กรอกอีเมลของคุณ',
        fieldType: FieldType.email,
        isRequired: true,
        order: 0,
        iconName: 'email_outlined',
      ),
      const RegistrationFieldConfig(
        id: 'phone',
        label: 'เบอร์โทร',
        hint: 'กรอกเบอร์โทรศัพท์',
        fieldType: FieldType.phone,
        isRequired: true,
        order: 1,
        iconName: 'phone_outlined',
      ),
      const RegistrationFieldConfig(
        id: 'birthday',
        label: 'วันเกิด',
        hint: 'เลือกวันเกิด',
        fieldType: FieldType.date,
        isRequired: false,
        order: 2,
        iconName: 'calendar_today_outlined',
      ),
    ];

    // Expert defaults
    _configs[UserType.expert] = [
      const RegistrationFieldConfig(
        id: 'profile_image',
        label: 'รูปโปรไฟล์',
        hint: 'อัพโหลดรูปโปรไฟล์',
        fieldType: FieldType.image,
        isRequired: false,
        order: 0,
        iconName: 'person',
      ),
      const RegistrationFieldConfig(
        id: 'business_name',
        label: 'ชื่อร้าน/ชื่อธุรกิจ',
        hint: 'กรอกชื่อร้านหรือธุรกิจของคุณ',
        fieldType: FieldType.text,
        isRequired: true,
        order: 1,
        iconName: 'store_outlined',
      ),
      const RegistrationFieldConfig(
        id: 'specialty',
        label: 'ความเชี่ยวชาญ/ประเภทสินค้า',
        hint: 'ระบุความเชี่ยวชาญหรือประเภทสินค้า',
        fieldType: FieldType.text,
        isRequired: false,
        order: 2,
        iconName: 'category_outlined',
      ),
      const RegistrationFieldConfig(
        id: 'business_phone',
        label: 'เบอร์โทรติดต่อ',
        hint: 'กรอกเบอร์โทรสำหรับติดต่อ',
        fieldType: FieldType.phone,
        isRequired: true,
        order: 3,
        iconName: 'phone_outlined',
      ),
      const RegistrationFieldConfig(
        id: 'business_email',
        label: 'อีเมลธุรกิจ',
        hint: 'กรอกอีเมลสำหรับติดต่อธุรกิจ',
        fieldType: FieldType.email,
        isRequired: false,
        order: 4,
        iconName: 'email_outlined',
      ),
      const RegistrationFieldConfig(
        id: 'business_address',
        label: 'ที่อยู่ร้าน/สถานที่ให้บริการ',
        hint: 'กรอกที่อยู่',
        fieldType: FieldType.multilineText,
        isRequired: false,
        order: 5,
        iconName: 'location_on_outlined',
      ),
      const RegistrationFieldConfig(
        id: 'experience',
        label: 'ประสบการณ์ (ปี)',
        hint: 'กรอกจำนวนปีประสบการณ์',
        fieldType: FieldType.number,
        isRequired: false,
        order: 6,
        iconName: 'work_outline',
      ),
      const RegistrationFieldConfig(
        id: 'id_card_image',
        label: 'รูปบัตรประชาชน',
        hint: 'อัพโหลดรูปบัตรประชาชน',
        fieldType: FieldType.image,
        isRequired: true,
        order: 7,
        iconName: 'credit_card',
      ),
      const RegistrationFieldConfig(
        id: 'description',
        label: 'แนะนำตัว/ธุรกิจ',
        hint: 'เขียนแนะนำตัวหรือธุรกิจของคุณ',
        fieldType: FieldType.multilineText,
        isRequired: false,
        order: 8,
        iconName: 'description_outlined',
      ),
    ];

    // Clinic defaults
    _configs[UserType.clinic] = [
      const RegistrationFieldConfig(
        id: 'business_image',
        label: 'รูปสถานประกอบการ',
        hint: 'อัพโหลดรูปสถานประกอบการ',
        fieldType: FieldType.image,
        isRequired: false,
        order: 0,
        iconName: 'business',
      ),
      const RegistrationFieldConfig(
        id: 'clinic_name',
        label: 'ชื่อคลินิก/ศูนย์',
        hint: 'กรอกชื่อคลินิกหรือศูนย์',
        fieldType: FieldType.text,
        isRequired: true,
        order: 1,
        iconName: 'local_hospital_outlined',
      ),
      const RegistrationFieldConfig(
        id: 'license_number',
        label: 'เลขใบอนุญาตประกอบกิจการ',
        hint: 'กรอกเลขใบอนุญาต',
        fieldType: FieldType.text,
        isRequired: true,
        order: 2,
        iconName: 'verified_outlined',
      ),
      const RegistrationFieldConfig(
        id: 'service_type',
        label: 'ประเภทบริการ',
        hint: 'เช่น คลินิกผิวหนัง, ฟิตเนส',
        fieldType: FieldType.text,
        isRequired: false,
        order: 3,
        iconName: 'medical_services_outlined',
      ),
      const RegistrationFieldConfig(
        id: 'business_phone',
        label: 'เบอร์โทรติดต่อ',
        hint: 'กรอกเบอร์โทรสำหรับติดต่อ',
        fieldType: FieldType.phone,
        isRequired: true,
        order: 4,
        iconName: 'phone_outlined',
      ),
      const RegistrationFieldConfig(
        id: 'business_email',
        label: 'อีเมลธุรกิจ',
        hint: 'กรอกอีเมลสำหรับติดต่อ',
        fieldType: FieldType.email,
        isRequired: false,
        order: 5,
        iconName: 'email_outlined',
      ),
      const RegistrationFieldConfig(
        id: 'business_address',
        label: 'ที่อยู่สถานประกอบการ',
        hint: 'กรอกที่อยู่',
        fieldType: FieldType.multilineText,
        isRequired: false,
        order: 6,
        iconName: 'location_on_outlined',
      ),
      const RegistrationFieldConfig(
        id: 'license_image',
        label: 'รูปใบอนุญาตประกอบกิจการ',
        hint: 'อัพโหลดรูปใบอนุญาต',
        fieldType: FieldType.image,
        isRequired: true,
        order: 7,
        iconName: 'document_scanner',
      ),
      const RegistrationFieldConfig(
        id: 'id_card_image',
        label: 'รูปบัตรประชาชนผู้จดทะเบียน',
        hint: 'อัพโหลดรูปบัตรประชาชน',
        fieldType: FieldType.image,
        isRequired: true,
        order: 8,
        iconName: 'credit_card',
      ),
      const RegistrationFieldConfig(
        id: 'description',
        label: 'รายละเอียดบริการ',
        hint: 'เขียนรายละเอียดบริการ',
        fieldType: FieldType.multilineText,
        isRequired: false,
        order: 9,
        iconName: 'description_outlined',
      ),
    ];
  }

  /// Reset to defaults
  void resetToDefaults() {
    _configs.clear();
    _initDefaultConfigs();
  }
}
