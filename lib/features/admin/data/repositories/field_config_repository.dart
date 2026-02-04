import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/registration_field_config.dart';

/// Field Config Repository - จัดการ Field Config ใน Database
class FieldConfigRepository {
  final SupabaseClient _client;

  FieldConfigRepository(this._client);

  /// ดึง Field Configs ทั้งหมดของ UserType
  Future<List<RegistrationFieldConfig>> getFieldConfigs(UserType userType) async {
    final response = await _client
        .from('registration_field_configs')
        .select()
        .eq('user_type', userType.name)
        .eq('is_active', true)
        .order('field_order', ascending: true);

    return (response as List)
        .map((e) => _mapToFieldConfig(e))
        .toList();
  }

  /// ดึง Field Configs ทั้งหมด
  Future<Map<UserType, List<RegistrationFieldConfig>>> getAllFieldConfigs() async {
    final response = await _client
        .from('registration_field_configs')
        .select()
        .eq('is_active', true)
        .order('field_order', ascending: true);

    final Map<UserType, List<RegistrationFieldConfig>> result = {
      UserType.consumer: [],
      UserType.expert: [],
      UserType.clinic: [],
    };

    for (final record in response) {
      final userType = UserType.values.firstWhere(
        (e) => e.name == record['user_type'],
        orElse: () => UserType.consumer,
      );
      result[userType]!.add(_mapToFieldConfig(record));
    }

    return result;
  }

  /// สร้าง Field Config ใหม่
  Future<RegistrationFieldConfig> createFieldConfig(
    UserType userType,
    RegistrationFieldConfig config,
  ) async {
    final data = {
      'user_type': userType.name,
      'field_id': config.id,
      'label': config.label,
      'hint': config.hint,
      'field_type': config.fieldType.name,
      'is_required': config.isRequired,
      'field_order': config.order,
      'icon_name': config.iconName,
      'dropdown_options': config.dropdownOptions,
      'validation_regex': config.validationRegex,
      'validation_message': config.validationMessage,
      'is_active': true,
    };

    final response = await _client
        .from('registration_field_configs')
        .insert(data)
        .select()
        .single();

    return _mapToFieldConfig(response);
  }

  /// อัพเดท Field Config
  Future<RegistrationFieldConfig> updateFieldConfig(
    UserType userType,
    RegistrationFieldConfig config,
  ) async {
    final data = {
      'label': config.label,
      'hint': config.hint,
      'field_type': config.fieldType.name,
      'is_required': config.isRequired,
      'field_order': config.order,
      'icon_name': config.iconName,
      'dropdown_options': config.dropdownOptions,
      'validation_regex': config.validationRegex,
      'validation_message': config.validationMessage,
    };

    final response = await _client
        .from('registration_field_configs')
        .update(data)
        .eq('user_type', userType.name)
        .eq('field_id', config.id)
        .select()
        .single();

    return _mapToFieldConfig(response);
  }

  /// ลบ Field Config (soft delete)
  Future<void> deleteFieldConfig(UserType userType, String fieldId) async {
    await _client
        .from('registration_field_configs')
        .update({'is_active': false})
        .eq('user_type', userType.name)
        .eq('field_id', fieldId);
  }

  /// ลบ Field Config (hard delete)
  Future<void> hardDeleteFieldConfig(UserType userType, String fieldId) async {
    await _client
        .from('registration_field_configs')
        .delete()
        .eq('user_type', userType.name)
        .eq('field_id', fieldId);
  }

  /// อัพเดทลำดับ Fields ทั้งหมด
  Future<void> reorderFields(
    UserType userType,
    List<RegistrationFieldConfig> configs,
  ) async {
    for (int i = 0; i < configs.length; i++) {
      await _client
          .from('registration_field_configs')
          .update({'field_order': i})
          .eq('user_type', userType.name)
          .eq('field_id', configs[i].id);
    }
  }

  /// รีเซ็ตเป็นค่าเริ่มต้น
  Future<void> resetToDefaults(UserType userType) async {
    // ลบ configs เดิมทั้งหมด
    await _client
        .from('registration_field_configs')
        .delete()
        .eq('user_type', userType.name);

    // เพิ่ม default configs
    final defaultConfigs = _getDefaultConfigs(userType);
    for (final config in defaultConfigs) {
      await createFieldConfig(userType, config);
    }
  }

  /// Sync local configs to database
  Future<void> syncToDatabase(
    UserType userType,
    List<RegistrationFieldConfig> configs,
  ) async {
    // ลบ configs เดิมทั้งหมด
    await _client
        .from('registration_field_configs')
        .delete()
        .eq('user_type', userType.name);

    // เพิ่ม configs ใหม่
    for (int i = 0; i < configs.length; i++) {
      final config = configs[i].copyWith(order: i);
      await createFieldConfig(userType, config);
    }
  }

  /// Map database record to FieldConfig
  RegistrationFieldConfig _mapToFieldConfig(Map<String, dynamic> record) {
    return RegistrationFieldConfig(
      id: record['field_id'],
      label: record['label'],
      hint: record['hint'],
      fieldType: FieldType.values.firstWhere(
        (e) => e.name == record['field_type'],
        orElse: () => FieldType.text,
      ),
      isRequired: record['is_required'] ?? false,
      order: record['field_order'] ?? 0,
      iconName: record['icon_name'],
      dropdownOptions: record['dropdown_options'] != null
          ? List<String>.from(record['dropdown_options'])
          : null,
      validationRegex: record['validation_regex'],
      validationMessage: record['validation_message'],
    );
  }

  /// Get default configs for user type
  List<RegistrationFieldConfig> _getDefaultConfigs(UserType userType) {
    switch (userType) {
      case UserType.consumer:
        return const [
          RegistrationFieldConfig(
            id: 'email',
            label: 'อีเมล',
            hint: 'กรอกอีเมลของคุณ',
            fieldType: FieldType.email,
            isRequired: true,
            order: 0,
            iconName: 'email_outlined',
          ),
          RegistrationFieldConfig(
            id: 'phone',
            label: 'เบอร์โทร',
            hint: 'กรอกเบอร์โทรศัพท์',
            fieldType: FieldType.phone,
            isRequired: true,
            order: 1,
            iconName: 'phone_outlined',
          ),
          RegistrationFieldConfig(
            id: 'birthday',
            label: 'วันเกิด',
            hint: 'เลือกวันเกิด',
            fieldType: FieldType.date,
            isRequired: false,
            order: 2,
            iconName: 'calendar_today_outlined',
          ),
        ];

      case UserType.expert:
        return const [
          RegistrationFieldConfig(
            id: 'profile_image',
            label: 'รูปโปรไฟล์',
            hint: 'อัพโหลดรูปโปรไฟล์',
            fieldType: FieldType.image,
            isRequired: false,
            order: 0,
            iconName: 'person',
          ),
          RegistrationFieldConfig(
            id: 'business_name',
            label: 'ชื่อร้าน/ชื่อธุรกิจ',
            hint: 'กรอกชื่อร้านหรือธุรกิจของคุณ',
            fieldType: FieldType.text,
            isRequired: true,
            order: 1,
            iconName: 'store_outlined',
          ),
          RegistrationFieldConfig(
            id: 'specialty',
            label: 'ความเชี่ยวชาญ/ประเภทสินค้า',
            hint: 'ระบุความเชี่ยวชาญหรือประเภทสินค้า',
            fieldType: FieldType.text,
            isRequired: false,
            order: 2,
            iconName: 'category_outlined',
          ),
          RegistrationFieldConfig(
            id: 'business_phone',
            label: 'เบอร์โทรติดต่อ',
            hint: 'กรอกเบอร์โทรสำหรับติดต่อ',
            fieldType: FieldType.phone,
            isRequired: true,
            order: 3,
            iconName: 'phone_outlined',
          ),
          RegistrationFieldConfig(
            id: 'business_email',
            label: 'อีเมลธุรกิจ',
            hint: 'กรอกอีเมลสำหรับติดต่อธุรกิจ',
            fieldType: FieldType.email,
            isRequired: false,
            order: 4,
            iconName: 'email_outlined',
          ),
          RegistrationFieldConfig(
            id: 'business_address',
            label: 'ที่อยู่ร้าน/สถานที่ให้บริการ',
            hint: 'กรอกที่อยู่',
            fieldType: FieldType.multilineText,
            isRequired: false,
            order: 5,
            iconName: 'location_on_outlined',
          ),
          RegistrationFieldConfig(
            id: 'experience',
            label: 'ประสบการณ์ (ปี)',
            hint: 'กรอกจำนวนปีประสบการณ์',
            fieldType: FieldType.number,
            isRequired: false,
            order: 6,
            iconName: 'work_outline',
          ),
          RegistrationFieldConfig(
            id: 'id_card_image',
            label: 'รูปบัตรประชาชน',
            hint: 'อัพโหลดรูปบัตรประชาชน',
            fieldType: FieldType.image,
            isRequired: true,
            order: 7,
            iconName: 'credit_card',
          ),
          RegistrationFieldConfig(
            id: 'description',
            label: 'แนะนำตัว/ธุรกิจ',
            hint: 'เขียนแนะนำตัวหรือธุรกิจของคุณ',
            fieldType: FieldType.multilineText,
            isRequired: false,
            order: 8,
            iconName: 'description_outlined',
          ),
        ];

      case UserType.clinic:
        return const [
          RegistrationFieldConfig(
            id: 'business_image',
            label: 'รูปสถานประกอบการ',
            hint: 'อัพโหลดรูปสถานประกอบการ',
            fieldType: FieldType.image,
            isRequired: false,
            order: 0,
            iconName: 'business',
          ),
          RegistrationFieldConfig(
            id: 'clinic_name',
            label: 'ชื่อคลินิก/ศูนย์',
            hint: 'กรอกชื่อคลินิกหรือศูนย์',
            fieldType: FieldType.text,
            isRequired: true,
            order: 1,
            iconName: 'local_hospital_outlined',
          ),
          RegistrationFieldConfig(
            id: 'license_number',
            label: 'เลขใบอนุญาตประกอบกิจการ',
            hint: 'กรอกเลขใบอนุญาต',
            fieldType: FieldType.text,
            isRequired: true,
            order: 2,
            iconName: 'verified_outlined',
          ),
          RegistrationFieldConfig(
            id: 'service_type',
            label: 'ประเภทบริการ',
            hint: 'เช่น คลินิกผิวหนัง, ฟิตเนส',
            fieldType: FieldType.text,
            isRequired: false,
            order: 3,
            iconName: 'medical_services_outlined',
          ),
          RegistrationFieldConfig(
            id: 'business_phone',
            label: 'เบอร์โทรติดต่อ',
            hint: 'กรอกเบอร์โทรสำหรับติดต่อ',
            fieldType: FieldType.phone,
            isRequired: true,
            order: 4,
            iconName: 'phone_outlined',
          ),
          RegistrationFieldConfig(
            id: 'business_email',
            label: 'อีเมลธุรกิจ',
            hint: 'กรอกอีเมลสำหรับติดต่อ',
            fieldType: FieldType.email,
            isRequired: false,
            order: 5,
            iconName: 'email_outlined',
          ),
          RegistrationFieldConfig(
            id: 'business_address',
            label: 'ที่อยู่สถานประกอบการ',
            hint: 'กรอกที่อยู่',
            fieldType: FieldType.multilineText,
            isRequired: false,
            order: 6,
            iconName: 'location_on_outlined',
          ),
          RegistrationFieldConfig(
            id: 'license_image',
            label: 'รูปใบอนุญาตประกอบกิจการ',
            hint: 'อัพโหลดรูปใบอนุญาต',
            fieldType: FieldType.image,
            isRequired: true,
            order: 7,
            iconName: 'document_scanner',
          ),
          RegistrationFieldConfig(
            id: 'id_card_image',
            label: 'รูปบัตรประชาชนผู้จดทะเบียน',
            hint: 'อัพโหลดรูปบัตรประชาชน',
            fieldType: FieldType.image,
            isRequired: true,
            order: 8,
            iconName: 'credit_card',
          ),
          RegistrationFieldConfig(
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
  }
}
