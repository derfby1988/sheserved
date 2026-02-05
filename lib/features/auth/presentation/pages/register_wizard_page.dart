import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../admin/models/profession.dart';
import '../../../admin/models/registration_field_config.dart';

/// Register Wizard Page - ลงทะเบียนแบบ 4 ขั้นตอน (รองรับอาชีพแบบ Dynamic)
class RegisterWizardPage extends StatefulWidget {
  const RegisterWizardPage({super.key});

  @override
  State<RegisterWizardPage> createState() => _RegisterWizardPageState();
}

class _RegisterWizardPageState extends State<RegisterWizardPage> {
  int _currentStep = 0;
  final int _totalSteps = 4;
  
  // Dynamic field values storage
  final Map<String, dynamic> _dynamicFieldValues = {};
  
  // Available professions (loaded dynamically)
  List<Profession> _professions = [];
  bool _isLoadingProfessions = true;

  // Step 1 - ข้อมูลทั่วไป
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  Profession? _selectedProfession;

  // Step 2 - ข้อมูลสำหรับเข้าสู่ระบบ
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  // Step 3 - ข้อมูลจำเพาะ (Dynamic fields from profession)
  List<RegistrationFieldConfig> _professionFields = [];

  // Step 4 - ยืนยัน
  bool _acceptTerms = false;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadProfessions();
  }

  Future<void> _loadProfessions() async {
    setState(() => _isLoadingProfessions = true);

    // TODO: Load from ProfessionRepository
    await Future.delayed(const Duration(milliseconds: 300));

    setState(() {
      _professions = Profession.defaultProfessions;
      _isLoadingProfessions = false;
    });
  }

  void _loadFieldsForProfession(Profession profession) {
    // TODO: Load from ProfessionRepository
    // For now, use default fields
    setState(() {
      _professionFields = _getDefaultFieldsForProfession(profession.id);
      // Clear dynamic field values when profession changes
      _dynamicFieldValues.clear();
    });
  }

  List<RegistrationFieldConfig> _getDefaultFieldsForProfession(String professionId) {
    switch (professionId) {
      case Profession.consumerProfessionId:
        return [
          RegistrationFieldConfig(
            id: '1',
            professionId: professionId,
            fieldId: 'email',
            label: 'อีเมล',
            hint: 'กรอกอีเมลของคุณ',
            fieldType: FieldType.email,
            isRequired: true,
            order: 0,
          ),
          RegistrationFieldConfig(
            id: '2',
            professionId: professionId,
            fieldId: 'phone',
            label: 'เบอร์โทร',
            hint: 'กรอกเบอร์โทรศัพท์',
            fieldType: FieldType.phone,
            isRequired: true,
            order: 1,
          ),
          RegistrationFieldConfig(
            id: '3',
            professionId: professionId,
            fieldId: 'birthday',
            label: 'วันเกิด',
            hint: 'เลือกวันเกิด',
            fieldType: FieldType.date,
            isRequired: false,
            order: 2,
          ),
        ];
      case Profession.expertProfessionId:
        return [
          RegistrationFieldConfig(
            id: '4',
            professionId: professionId,
            fieldId: 'profile_image',
            label: 'รูปโปรไฟล์',
            hint: 'อัพโหลดรูปโปรไฟล์',
            fieldType: FieldType.image,
            isRequired: false,
            order: 0,
          ),
          RegistrationFieldConfig(
            id: '5',
            professionId: professionId,
            fieldId: 'business_name',
            label: 'ชื่อร้าน/ชื่อธุรกิจ',
            hint: 'กรอกชื่อร้านหรือธุรกิจของคุณ',
            fieldType: FieldType.text,
            isRequired: true,
            order: 1,
          ),
          RegistrationFieldConfig(
            id: '6',
            professionId: professionId,
            fieldId: 'specialty',
            label: 'ความเชี่ยวชาญ/ประเภทสินค้า',
            hint: 'ระบุความเชี่ยวชาญหรือประเภทสินค้า',
            fieldType: FieldType.text,
            isRequired: false,
            order: 2,
          ),
          RegistrationFieldConfig(
            id: '7',
            professionId: professionId,
            fieldId: 'business_phone',
            label: 'เบอร์โทรติดต่อ',
            hint: 'กรอกเบอร์โทรสำหรับติดต่อ',
            fieldType: FieldType.phone,
            isRequired: true,
            order: 3,
          ),
          RegistrationFieldConfig(
            id: '8',
            professionId: professionId,
            fieldId: 'id_card_image',
            label: 'รูปบัตรประชาชน',
            hint: 'อัพโหลดรูปบัตรประชาชน',
            fieldType: FieldType.image,
            isRequired: true,
            order: 4,
          ),
          RegistrationFieldConfig(
            id: '9',
            professionId: professionId,
            fieldId: 'description',
            label: 'แนะนำตัว/ธุรกิจ',
            hint: 'เขียนแนะนำตัวหรือธุรกิจของคุณ',
            fieldType: FieldType.multilineText,
            isRequired: false,
            order: 5,
          ),
        ];
      case Profession.clinicProfessionId:
        return [
          RegistrationFieldConfig(
            id: '10',
            professionId: professionId,
            fieldId: 'business_image',
            label: 'รูปสถานประกอบการ',
            hint: 'อัพโหลดรูปสถานประกอบการ',
            fieldType: FieldType.image,
            isRequired: false,
            order: 0,
          ),
          RegistrationFieldConfig(
            id: '11',
            professionId: professionId,
            fieldId: 'clinic_name',
            label: 'ชื่อคลินิก/ศูนย์',
            hint: 'กรอกชื่อคลินิกหรือศูนย์',
            fieldType: FieldType.text,
            isRequired: true,
            order: 1,
          ),
          RegistrationFieldConfig(
            id: '12',
            professionId: professionId,
            fieldId: 'license_number',
            label: 'เลขใบอนุญาตประกอบกิจการ',
            hint: 'กรอกเลขใบอนุญาต',
            fieldType: FieldType.text,
            isRequired: true,
            order: 2,
          ),
          RegistrationFieldConfig(
            id: '13',
            professionId: professionId,
            fieldId: 'business_phone',
            label: 'เบอร์โทรติดต่อ',
            hint: 'กรอกเบอร์โทรสำหรับติดต่อ',
            fieldType: FieldType.phone,
            isRequired: true,
            order: 3,
          ),
          RegistrationFieldConfig(
            id: '14',
            professionId: professionId,
            fieldId: 'license_image',
            label: 'รูปใบอนุญาตประกอบกิจการ',
            hint: 'อัพโหลดรูปใบอนุญาต',
            fieldType: FieldType.image,
            isRequired: true,
            order: 4,
          ),
          RegistrationFieldConfig(
            id: '15',
            professionId: professionId,
            fieldId: 'id_card_image',
            label: 'รูปบัตรประชาชนผู้จดทะเบียน',
            hint: 'อัพโหลดรูปบัตรประชาชน',
            fieldType: FieldType.image,
            isRequired: true,
            order: 5,
          ),
        ];
      default:
        return [];
    }
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    // Dispose dynamic controllers
    for (final entry in _dynamicFieldValues.entries) {
      if (entry.key.endsWith('_controller') && entry.value is TextEditingController) {
        (entry.value as TextEditingController).dispose();
      }
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primary,
      body: SafeArea(
        child: Column(
          children: [
            // Top Section - Back Button
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  onPressed: _handleBack,
                  icon: const Icon(
                    Icons.arrow_back_ios,
                    color: AppColors.textOnPrimary,
                    size: 24,
                  ),
                ),
              ),
            ),

            // Bottom Card - Form
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(32),
                    topRight: Radius.circular(32),
                  ),
                ),
                child: Column(
                  children: [
                    // Content
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(24, 32, 24, 16),
                        child: _buildCurrentStep(),
                      ),
                    ),

                    // Bottom Button & Progress
                    _buildBottomSection(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentStep() {
    switch (_currentStep) {
      case 0:
        return _buildStep1GeneralInfo();
      case 1:
        return _buildStep2LoginInfo();
      case 2:
        return _buildStep3SpecificInfo();
      case 3:
        return _buildStep4Confirmation();
      default:
        return const SizedBox.shrink();
    }
  }

  /// Step 1: ข้อมูลทั่วไป - เลือกอาชีพแบบ Dynamic
  Widget _buildStep1GeneralInfo() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'ข้อมูลทั่วไป',
          textAlign: TextAlign.center,
          style: AppTextStyles.heading4.copyWith(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 28),

        // ชื่อ (จริง)
        _buildInputField(
          controller: _firstNameController,
          hintText: 'ชื่อ (จริง)',
          prefixIcon: Icons.person_outline,
        ),
        const SizedBox(height: 16),

        // นามสกุล
        _buildInputField(
          controller: _lastNameController,
          hintText: 'นามสกุล',
          prefixIcon: Icons.person_outline,
        ),
        const SizedBox(height: 24),

        // เลือกประเภท/อาชีพ
        Text(
          'เลือกประเภทการลงทะเบียน',
          style: AppTextStyles.bodySmall.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 12),

        if (_isLoadingProfessions)
          const Center(child: CircularProgressIndicator())
        else
          _buildProfessionSelector(),
      ],
    );
  }

  Widget _buildProfessionSelector() {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      alignment: WrapAlignment.center,
      children: _professions.map((profession) {
        final isSelected = _selectedProfession?.id == profession.id;
        return GestureDetector(
          onTap: () {
            setState(() {
              _selectedProfession = profession;
            });
            _loadFieldsForProfession(profession);
          },
          child: Container(
            width: MediaQuery.of(context).size.width / 3 - 24,
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
            decoration: BoxDecoration(
              color: isSelected ? AppColors.primary.withOpacity(0.1) : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected ? AppColors.primary : AppColors.border,
                width: isSelected ? 2 : 1,
              ),
            ),
            child: Column(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppColors.primary
                        : AppColors.background,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _getIconForProfession(profession.iconName),
                    color: isSelected ? Colors.white : AppColors.textHint,
                    size: 20,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  profession.name,
                  textAlign: TextAlign.center,
                  style: AppTextStyles.caption.copyWith(
                    color: isSelected
                        ? AppColors.primary
                        : AppColors.textSecondary,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (profession.requiresVerification) ...[
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.verified_user,
                        size: 10,
                        color: AppColors.warning,
                      ),
                      const SizedBox(width: 2),
                      Text(
                        'ต้องตรวจสอบ',
                        style: AppTextStyles.caption.copyWith(
                          color: AppColors.warning,
                          fontSize: 8,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  IconData _getIconForProfession(String? iconName) {
    switch (iconName) {
      case 'shopping_cart':
        return Icons.shopping_cart;
      case 'store':
        return Icons.store;
      case 'local_hospital':
        return Icons.local_hospital;
      case 'medical_services':
        return Icons.medical_services;
      case 'delivery_dining':
        return Icons.delivery_dining;
      case 'engineering':
        return Icons.engineering;
      case 'gavel':
        return Icons.gavel;
      default:
        return Icons.work;
    }
  }

  /// Step 2: ข้อมูลสำหรับเข้าสู่ระบบ
  Widget _buildStep2LoginInfo() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'ข้อมูลสำหรับเข้าสู่ระบบ',
          textAlign: TextAlign.center,
          style: AppTextStyles.heading4.copyWith(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 28),

        // ชื่อผู้ใช้ (นามแฝง)
        _buildInputField(
          controller: _usernameController,
          hintText: 'ชื่อผู้ใช้ (นามแฝง)',
          prefixIcon: Icons.alternate_email,
        ),
        const SizedBox(height: 16),

        // รหัสผ่าน
        _buildInputField(
          controller: _passwordController,
          hintText: 'รหัสผ่าน',
          prefixIcon: Icons.lock_outline,
          obscureText: _obscurePassword,
          suffixIcon: IconButton(
            onPressed: () {
              setState(() {
                _obscurePassword = !_obscurePassword;
              });
            },
            icon: Icon(
              _obscurePassword
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
              color: AppColors.textHint,
              size: 22,
            ),
          ),
        ),
        const SizedBox(height: 16),

        // ยืนยันรหัสผ่าน
        _buildInputField(
          controller: _confirmPasswordController,
          hintText: 'ยืนยัน รหัสผ่าน',
          prefixIcon: Icons.lock_outline,
          obscureText: _obscureConfirmPassword,
          suffixIcon: IconButton(
            onPressed: () {
              setState(() {
                _obscureConfirmPassword = !_obscureConfirmPassword;
              });
            },
            icon: Icon(
              _obscureConfirmPassword
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
              color: AppColors.textHint,
              size: 22,
            ),
          ),
        ),
      ],
    );
  }

  /// Step 3: ข้อมูลจำเพาะ - สร้างแบบ Dynamic จาก Profession Config
  Widget _buildStep3SpecificInfo() {
    final profession = _selectedProfession;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'ข้อมูลจำเพาะ',
          textAlign: TextAlign.center,
          style: AppTextStyles.heading4.copyWith(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'สำหรับ ${profession?.name ?? ""}',
          textAlign: TextAlign.center,
          style: AppTextStyles.bodySmall.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 28),
        
        // Dynamic fields from profession config
        ..._professionFields.map((field) => Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: _buildDynamicField(field),
        )),
      ],
    );
  }
  
  /// Build dynamic field based on config
  Widget _buildDynamicField(RegistrationFieldConfig field) {
    switch (field.fieldType) {
      case FieldType.image:
        return _buildDynamicImageField(field);
      case FieldType.date:
        return _buildDynamicDateField(field);
      case FieldType.multilineText:
        return _buildDynamicTextField(field, maxLines: 3);
      default:
        return _buildDynamicTextField(field);
    }
  }
  
  Widget _buildDynamicTextField(RegistrationFieldConfig field, {int maxLines = 1}) {
    // Get or create controller for this field
    if (!_dynamicFieldValues.containsKey('${field.fieldId}_controller')) {
      _dynamicFieldValues['${field.fieldId}_controller'] = TextEditingController();
    }
    final controller = _dynamicFieldValues['${field.fieldId}_controller'] as TextEditingController;
    
    TextInputType? keyboardType;
    switch (field.fieldType) {
      case FieldType.email:
        keyboardType = TextInputType.emailAddress;
        break;
      case FieldType.phone:
        keyboardType = TextInputType.phone;
        break;
      case FieldType.number:
        keyboardType = TextInputType.number;
        break;
      default:
        keyboardType = TextInputType.text;
    }
    
    return _buildInputField(
      controller: controller,
      hintText: '${field.label}${field.isRequired ? " *" : ""}',
      prefixIcon: _getIconForFieldType(field.fieldType),
      keyboardType: keyboardType,
      maxLines: maxLines,
    );
  }
  
  Widget _buildDynamicDateField(RegistrationFieldConfig field) {
    if (!_dynamicFieldValues.containsKey('${field.fieldId}_controller')) {
      _dynamicFieldValues['${field.fieldId}_controller'] = TextEditingController();
    }
    final controller = _dynamicFieldValues['${field.fieldId}_controller'] as TextEditingController;
    
    return GestureDetector(
      onTap: () => _selectDateForField(field.fieldId, controller),
      child: AbsorbPointer(
        child: _buildInputField(
          controller: controller,
          hintText: '${field.label}${field.isRequired ? " *" : ""}',
          prefixIcon: Icons.calendar_today_outlined,
        ),
      ),
    );
  }
  
  Widget _buildDynamicImageField(RegistrationFieldConfig field) {
    final imagePath = _dynamicFieldValues['${field.fieldId}_image'] as String?;
    
    return _buildImageUploadField(
      label: field.label,
      imagePath: imagePath,
      onTap: () => _selectImageForField(field.fieldId),
      icon: _getIconForFieldType(field.fieldType),
      required: field.isRequired,
    );
  }
  
  IconData _getIconForFieldType(FieldType type) {
    switch (type) {
      case FieldType.email:
        return Icons.email_outlined;
      case FieldType.phone:
        return Icons.phone_outlined;
      case FieldType.date:
        return Icons.calendar_today_outlined;
      case FieldType.image:
        return Icons.image_outlined;
      case FieldType.number:
        return Icons.numbers;
      case FieldType.multilineText:
        return Icons.notes;
      case FieldType.dropdown:
        return Icons.arrow_drop_down_circle_outlined;
      default:
        return Icons.text_fields;
    }
  }
  
  Future<void> _selectDateForField(String fieldId, TextEditingController controller) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now().subtract(const Duration(days: 6570)),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
      locale: const Locale('th', 'TH'),
    );

    if (picked != null) {
      setState(() {
        _dynamicFieldValues['${fieldId}_date'] = picked;
        controller.text = '${picked.day}/${picked.month}/${picked.year + 543}';
      });
    }
  }
  
  void _selectImageForField(String fieldId) {
    // TODO: Implement image picker
    _showSnackBar('เลือกรูปภาพจะเปิดใช้งานเร็วๆ นี้');
    
    // Simulate image selection
    setState(() {
      _dynamicFieldValues['${fieldId}_image'] = 'selected';
    });
  }

  /// Step 4: สรุปข้อมูลและยืนยัน
  Widget _buildStep4Confirmation() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'ยืนยันข้อมูล',
          textAlign: TextAlign.center,
          style: AppTextStyles.heading4.copyWith(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'กรุณาตรวจสอบข้อมูลก่อนยืนยันการลงทะเบียน',
          textAlign: TextAlign.center,
          style: AppTextStyles.bodySmall.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 28),

        // Summary Card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSummaryItem('ประเภท', _selectedProfession?.name ?? '-'),
              const Divider(height: 24),
              _buildSummaryItem('ชื่อ-นามสกุล',
                  '${_firstNameController.text} ${_lastNameController.text}'),
              _buildSummaryItem('ชื่อผู้ใช้', _usernameController.text),
              const Divider(height: 24),
              // Dynamic fields summary
              ..._professionFields.where((f) => f.fieldType != FieldType.image).map((field) {
                final controller = _dynamicFieldValues['${field.fieldId}_controller'] as TextEditingController?;
                return _buildSummaryItem(field.label, controller?.text ?? '-');
              }),
            ],
          ),
        ),

        // Verification notice for provider professions
        if (_selectedProfession?.requiresVerification == true) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.warning.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.warning.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: AppColors.warning, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'หลังลงทะเบียน ข้อมูลของคุณจะถูกตรวจสอบโดย Admin ก่อนเปิดใช้งาน',
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.warning,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],

        const SizedBox(height: 24),

        // Terms Checkbox
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: Checkbox(
                value: _acceptTerms,
                onChanged: (value) {
                  setState(() {
                    _acceptTerms = value ?? false;
                  });
                },
                activeColor: AppColors.primary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    _acceptTerms = !_acceptTerms;
                  });
                },
                child: RichText(
                  text: TextSpan(
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.textSecondary,
                    ),
                    children: [
                      const TextSpan(text: 'ฉันยอมรับ '),
                      TextSpan(
                        text: 'ข้อกำหนดการใช้งาน',
                        style: TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const TextSpan(text: ' และ '),
                      TextSpan(
                        text: 'นโยบายความเป็นส่วนตัว',
                        style: TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSummaryItem(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value.isEmpty ? '-' : value,
              style: AppTextStyles.bodyMedium.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Build input field with green border
  Widget _buildInputField({
    required TextEditingController controller,
    required String hintText,
    required IconData prefixIcon,
    TextInputType? keyboardType,
    bool obscureText = false,
    Widget? suffixIcon,
    int maxLines = 1,
  }) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: AppColors.primary,
          width: 1.5,
        ),
      ),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        obscureText: obscureText,
        maxLines: maxLines,
        style: AppTextStyles.bodyMedium.copyWith(
          color: AppColors.textPrimary,
        ),
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: AppTextStyles.bodyMedium.copyWith(
            color: AppColors.textHint,
          ),
          prefixIcon: Icon(
            prefixIcon,
            color: AppColors.primary,
            size: 24,
          ),
          suffixIcon: suffixIcon,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 16,
          ),
        ),
      ),
    );
  }

  /// Build image upload field
  Widget _buildImageUploadField({
    required String label,
    required String? imagePath,
    required VoidCallback onTap,
    required IconData icon,
    bool required = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppColors.primary,
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: imagePath != null
                    ? AppColors.primary.withOpacity(0.1)
                    : AppColors.background,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                imagePath != null ? Icons.check_circle : icon,
                color: imagePath != null ? AppColors.primary : AppColors.textHint,
                size: 28,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        label,
                        style: AppTextStyles.bodyMedium.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (required)
                        Text(
                          ' *',
                          style: AppTextStyles.bodyMedium.copyWith(
                            color: AppColors.error,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    imagePath != null ? 'เลือกแล้ว' : 'แตะเพื่ออัพโหลด',
                    style: AppTextStyles.caption.copyWith(
                      color: imagePath != null
                          ? AppColors.success
                          : AppColors.textHint,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.cloud_upload_outlined,
              color: AppColors.primary,
              size: 24,
            ),
          ],
        ),
      ),
    );
  }

  /// Build bottom section with button and progress
  Widget _buildBottomSection() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: Column(
        children: [
          // Next/Submit Button
          SizedBox(
            height: 52,
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _handleNext,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black,
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.grey[400],
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(26),
                ),
                elevation: 0,
              ),
              child: _isLoading
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Colors.white,
                        ),
                      ),
                    )
                  : Text(
                      _currentStep == _totalSteps - 1 ? 'ยืนยันลงทะเบียน' : 'ต่อไป',
                      style: AppTextStyles.button.copyWith(
                        color: Colors.white,
                        fontSize: 18,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 12),

          // Progress indicator
          Text(
            '${_currentStep + 1}/$_totalSteps',
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.warning,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  void _handleBack() {
    if (_currentStep > 0) {
      setState(() {
        _currentStep--;
      });
    } else {
      Navigator.pop(context);
    }
  }

  void _handleNext() {
    if (!_validateCurrentStep()) return;

    if (_currentStep < _totalSteps - 1) {
      setState(() {
        _currentStep++;
      });
    } else {
      _handleSubmit();
    }
  }

  bool _validateCurrentStep() {
    switch (_currentStep) {
      case 0:
        if (_firstNameController.text.isEmpty) {
          _showSnackBar('กรุณากรอกชื่อ');
          return false;
        }
        if (_lastNameController.text.isEmpty) {
          _showSnackBar('กรุณากรอกนามสกุล');
          return false;
        }
        if (_selectedProfession == null) {
          _showSnackBar('กรุณาเลือกประเภทการลงทะเบียน');
          return false;
        }
        return true;

      case 1:
        if (_usernameController.text.isEmpty) {
          _showSnackBar('กรุณากรอกชื่อผู้ใช้');
          return false;
        }
        if (_passwordController.text.isEmpty) {
          _showSnackBar('กรุณากรอกรหัสผ่าน');
          return false;
        }
        if (_passwordController.text.length < 6) {
          _showSnackBar('รหัสผ่านต้องมีอย่างน้อย 6 ตัวอักษร');
          return false;
        }
        if (_passwordController.text != _confirmPasswordController.text) {
          _showSnackBar('รหัสผ่านไม่ตรงกัน');
          return false;
        }
        return true;

      case 2:
        // Validate required dynamic fields
        for (final field in _professionFields.where((f) => f.isRequired)) {
          if (field.fieldType == FieldType.image) {
            final imagePath = _dynamicFieldValues['${field.fieldId}_image'];
            if (imagePath == null) {
              _showSnackBar('กรุณาอัพโหลด ${field.label}');
              return false;
            }
          } else {
            final controller = _dynamicFieldValues['${field.fieldId}_controller'] as TextEditingController?;
            if (controller == null || controller.text.isEmpty) {
              _showSnackBar('กรุณากรอก ${field.label}');
              return false;
            }
          }
        }
        return true;

      case 3:
        if (!_acceptTerms) {
          _showSnackBar('กรุณายอมรับข้อกำหนดการใช้งาน');
          return false;
        }
        return true;

      default:
        return true;
    }
  }

  void _handleSubmit() async {
    setState(() {
      _isLoading = true;
    });

    // TODO: Implement registration with Supabase
    // 1. Create user
    // 2. Create registration application if requires verification
    // 3. Save dynamic field values

    await Future.delayed(const Duration(seconds: 2));

    if (mounted) {
      setState(() {
        _isLoading = false;
      });

      if (_selectedProfession?.requiresVerification == true) {
        _showSnackBar('ลงทะเบียนสำเร็จ! รอการตรวจสอบจาก Admin');
      } else {
        _showSnackBar('ลงทะเบียนสำเร็จ!');
      }
      Navigator.pushReplacementNamed(context, '/login');
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
      ),
    );
  }
}
