import 'package:flutter/material.dart';
import 'package:thai_buddhist_date/thai_buddhist_date.dart';
import 'package:thai_buddhist_date_pickers/thai_buddhist_date_pickers.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../config/app_config.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../../shared/widgets/otp_verification_dialog.dart';
import '../../../admin/models/profession.dart' hide VerificationStatus;
import '../../../admin/models/registration_field_config.dart';
import '../../../../features/admin/data/repositories/profession_repository.dart';
import '../../data/repositories/user_repository.dart';
import '../../data/models/user_model.dart' as auth;

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

  // OTP Verification
  bool _isPhoneVerified = false;
  String? _verifiedPhoneNumber;

  @override
  void initState() {
    super.initState();
    _loadProfessions();
  }

  Future<void> _loadProfessions() async {
    setState(() => _isLoadingProfessions = true);

    try {
      if (AppConfig.isSupabaseConfigured) {
        final repository = ProfessionRepository(Supabase.instance.client);
        final professions = await repository.getAllProfessions();
        
        setState(() {
          _professions = professions;
          _isLoadingProfessions = false;
        });
      } else {
        // Fallback for local testing
        await Future.delayed(const Duration(milliseconds: 300));
        setState(() {
          _professions = Profession.defaultProfessions;
          _isLoadingProfessions = false;
        });
      }

      // Default: Consumer / ผู้ซื้อ
      if (_selectedProfession == null && _professions.isNotEmpty) {
        try {
          final consumer = _professions.firstWhere(
            (p) => p.id == Profession.consumerProfessionId,
            orElse: () => _professions.first,
          );
          _selectedProfession = consumer;
          _loadFieldsForProfession(consumer);
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('Error loading professions: $e');
      setState(() => _isLoadingProfessions = false);
    }
  }

  void _loadFieldsForProfession(Profession profession) {
    setState(() {
      _professionFields = _getDefaultFieldsForProfession(profession.id);
      _dynamicFieldValues.clear();
    });
  }

  // Helper method for icon mapping (moved from build)
  IconData _getIconForProfession(String? iconName) {
    if (iconName == null) return Icons.work;
    
    // Simple mapping for demo/defaults
    switch (iconName) {
      case 'shopping_cart': return Icons.shopping_cart;
      case 'store': return Icons.store;
      case 'local_hospital': return Icons.local_hospital;
      case 'medical_services': return Icons.medical_services;
      case 'delivery_dining': return Icons.delivery_dining;
      case 'engineering': return Icons.engineering;
      case 'gavel': return Icons.gavel;
      default: return Icons.work;
    }
  }

  // ... (getDefaultFieldsForProfession remains same or can be updated if we had real field config loading, but sticking to hardcoded for fields as per current scope unless requested)
  List<RegistrationFieldConfig> _getDefaultFieldsForProfession(String professionId) {
    switch (professionId) {
      case Profession.consumerProfessionId:
        return [
          RegistrationFieldConfig(
            id: '1',
            professionId: professionId,
            fieldId: 'phone',
            label: 'เบอร์โทรศัพท์',
            hint: 'กรอกเบอร์โทรศัพท์ (ใช้สำหรับยืนยันตัวตน)',
            fieldType: FieldType.phone,
            isRequired: true,  // Primary identifier
            order: 0,
          ),
          RegistrationFieldConfig(
            id: '2',
            professionId: professionId,
            fieldId: 'email',
            label: 'อีเมล (ไม่บังคับ)',
            hint: 'กรอกอีเมลของคุณ',
            fieldType: FieldType.email,
            isRequired: false,  // Optional
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
        child: CustomScrollView(
          slivers: [
            SliverFillRemaining(
              hasScrollBody: false,
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

                  // Spacer to push content down (Maximize green area)
                  const Spacer(),

                  // Bottom Card - Form
                  Container(
                    width: double.infinity,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(32),
                        topRight: Radius.circular(32),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 32, 24, 16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min, // Shrink vertically
                        children: [
                          _buildCurrentStep(),
                          const SizedBox(height: 24),
                          _buildBottomSection(),
                        ],
                      ),
                    ),
                  ),
                ],
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
            color: AppColors.primary, // Green title
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 28),

        // ชื่อ (จริง)
        _buildInputField(
          controller: _firstNameController,
          hintText: 'ชื่อจริง (ไม่ต้องใช้คำนำหน้า)',
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

        // เลือกประเภท/อาชีพ (Dropdown)
        if (_isLoadingProfessions)
          const Center(child: CircularProgressIndicator())
        else
          _buildProfessionSelector(),
      ],
    );
  }

  Widget _buildProfessionSelector() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: AppColors.primary,
          width: 1.5,
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<Profession>(
          value: _selectedProfession,
          hint: Text(
            'เลือกประเภทการลงทะเบียน',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textHint),
          ),
          icon: const Icon(Icons.arrow_drop_down, color: AppColors.primary),
          isExpanded: true,
          onChanged: (Profession? newValue) {
            if (newValue != null) {
              setState(() {
                _selectedProfession = newValue;
              });
              _loadFieldsForProfession(newValue);
            }
          },
          items: _professions.map<DropdownMenuItem<Profession>>((Profession value) {
            return DropdownMenuItem<Profession>(
              value: value,
              child: Row(
                children: [
                  Icon(
                    _getIconForProfession(value.iconName),
                    color: AppColors.primary,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    value.name,
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
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
          hintText: 'ชื่อในระบบ',
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
    
    // Check if this is a verified phone field
    final isVerifiedPhone = field.fieldType == FieldType.phone && 
        _isPhoneVerified && 
        _verifiedPhoneNumber == controller.text.replaceAll(RegExp(r'[^0-9]'), '');
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildInputField(
          controller: controller,
          hintText: '${field.label}${field.isRequired ? " *" : ""}',
          prefixIcon: _getIconForFieldType(field.fieldType),
          keyboardType: keyboardType,
          maxLines: maxLines,
          suffixIcon: isVerifiedPhone 
              ? const Icon(Icons.verified, color: Colors.green, size: 20)
              : null,
          onChanged: field.fieldType == FieldType.phone ? (_) {
            // Reset verification if phone number changes
            final currentPhone = controller.text.replaceAll(RegExp(r'[^0-9]'), '');
            if (_verifiedPhoneNumber != currentPhone) {
              setState(() {
                _isPhoneVerified = false;
              });
            }
          } : null,
        ),
        if (isVerifiedPhone)
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 4),
            child: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green, size: 14),
                const SizedBox(width: 4),
                Text(
                  'ยืนยันเบอร์โทรศัพท์แล้ว',
                  style: TextStyle(
                    color: Colors.green,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
  
  Widget _buildDynamicDateField(RegistrationFieldConfig field) {
    if (!_dynamicFieldValues.containsKey('${field.fieldId}_controller')) {
      _dynamicFieldValues['${field.fieldId}_controller'] = TextEditingController();
    }
    final controller = _dynamicFieldValues['${field.fieldId}_controller'] as TextEditingController;
    final DateTime initialDate = _dynamicFieldValues['${field.fieldId}_date'] as DateTime? ?? 
                               DateTime.now().subtract(const Duration(days: 6570));
    
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: AppColors.primary,
          width: 1.5,
        ),
      ),
      child: Row(
        children: [
          // Day/Month Selection
          Expanded(
            child: InkWell(
              onTap: () => _selectDateForField(field.fieldId, controller),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(28),
                bottomLeft: Radius.circular(28),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.calendar_today_outlined, color: AppColors.primary, size: 24),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        controller.text.isEmpty 
                          ? '${field.label}${field.isRequired ? " *" : ""}'
                          : controller.text.substring(0, controller.text.lastIndexOf(' ') - 4),
                        textAlign: TextAlign.center,
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: controller.text.isEmpty ? AppColors.textHint : AppColors.primary,
                          decoration: controller.text.isEmpty ? null : TextDecoration.underline,
                          decorationStyle: controller.text.isEmpty ? null : TextDecorationStyle.dashed,
                          fontWeight: controller.text.isEmpty ? null : FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Container(width: 1, height: 30, color: AppColors.primary.withOpacity(0.3)),
          // Year Selection
          InkWell(
            onTap: () async {
              final int? selectedYear = await _showThaiYearPicker(context, initialDate.year);
              if (selectedYear != null) {
                setState(() {
                  final newDate = DateTime(selectedYear, initialDate.month, initialDate.day);
                  _dynamicFieldValues['${field.fieldId}_date'] = newDate;
                  controller.text = '${newDate.day} ${_getThaiShortMonth(newDate.month)} ${newDate.year + 543}';
                });
              }
            },
            borderRadius: const BorderRadius.only(
              topRight: Radius.circular(28),
              bottomRight: Radius.circular(28),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              child: Text(
                controller.text.isEmpty ? 'พ.ศ.' : controller.text.substring(controller.text.lastIndexOf(' ') + 1),
                style: AppTextStyles.bodyMedium.copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                  decoration: TextDecoration.underline,
                  decorationStyle: TextDecorationStyle.dashed,
                ),
              ),
            ),
          ),
        ],
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

  Future<int?> _showThaiYearPicker(BuildContext context, int initialYear) async {
    final int currentYearBE = DateTime.now().year + 543;
    final int startYearBE = initialYear + 543;
    final int selectedIndex = currentYearBE - startYearBE;
    
    // Calculate initial scroll offset (roughly 3 items per row, row height ~50)
    final double initialOffset = (selectedIndex ~/ 3) * 50.0;
    final ScrollController scrollController = ScrollController(initialScrollOffset: initialOffset);
    
    return showDialog<int>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('เลือกปี พ.ศ.', style: TextStyle(fontWeight: FontWeight.bold)),
          content: SizedBox(
            width: double.maxFinite,
            height: 300,
            child: Scrollbar(
              controller: scrollController,
              thumbVisibility: true,
              child: GridView.builder(
                controller: scrollController,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  childAspectRatio: 2,
                ),
                itemCount: currentYearBE - (1900 + 543) + 1,
                itemBuilder: (context, index) {
                  final yearBE = currentYearBE - index;
                  final bool isSelected = yearBE == startYearBE;
                  return InkWell(
                    onTap: () => Navigator.pop(context, yearBE - 543),
                    child: Container(
                      margin: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: isSelected ? AppColors.primary : null,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.primary.withOpacity(0.3)),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '$yearBE',
                        style: TextStyle(
                          color: isSelected ? Colors.white : Colors.black,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                scrollController.dispose();
                Navigator.pop(context);
              },
              child: const Text('ยกเลิก'),
            ),
          ],
        );
      },
    );
  }
  
  Future<void> _selectDateForField(String fieldId, TextEditingController controller) async {
    final DateTime initialDate = _dynamicFieldValues['${fieldId}_date'] as DateTime? ?? 
                               DateTime.now().subtract(const Duration(days: 6570));
    
    // Show Thai Date Picker directly with the existing/default value
    final DateTime? picked = await showThaiDatePicker(
      context,
      initialDate: initialDate,
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
      era: Era.be,
      locale: 'th_TH',
    );

    if (picked != null) {
      setState(() {
        _dynamicFieldValues['${fieldId}_date'] = picked;
        controller.text = '${picked.day} ${_getThaiShortMonth(picked.month)} ${picked.year + 543}';
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
    ValueChanged<String>? onChanged,
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
        onChanged: onChanged,
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
      if (Navigator.of(context).canPop()) {
        Navigator.pop(context);
      } else {
        Navigator.pushReplacementNamed(context, '/');
      }
    }
  }

  void _handleNext() async {
    if (!_validateCurrentStep()) return;

    setState(() => _isLoading = true);

    try {
      final supabase = Supabase.instance.client;
      final userRepo = UserRepository(supabase);

      // Validate Username Uniqueness (Step 1 - Login Info)
      if (_currentStep == 1) {
        final username = _usernameController.text;
        final exists = await userRepo.isUsernameExists(username);
        if (exists) {
          _showSnackBar('ชื่อผู้ใช้นี้ถูกใช้งานแล้ว กรุณาใช้ชื่ออื่น');
          setState(() => _isLoading = false);
          return;
        }
      }

      // Validate Phone Uniqueness (Step 2 - Specific Info)
      if (_currentStep == 2) {
        // Only check for Consumers who have 'phone_controller'
        // If other professions use phone as ID later, add checking here
        final phoneController = _dynamicFieldValues['phone_controller'] as TextEditingController?;
        final phoneNumber = phoneController?.text.replaceAll(RegExp(r'[^0-9]'), '') ?? '';
        
        if (phoneNumber.isNotEmpty) {
           final exists = await userRepo.isPhoneExists(phoneNumber);
           if (exists) {
             _showSnackBar('เบอร์โทรศัพท์นี้ถูกใช้งานแล้ว กรุณาใช้เบอร์อื่น');
             setState(() => _isLoading = false);
             return;
           }

           // OTP Verification Logic
           if (AppConfig.enableOtpVerification) {
              // Check if phone number changed from previously verified
              if (_verifiedPhoneNumber != phoneNumber) {
                _isPhoneVerified = false;
              }
              
              if (!_isPhoneVerified) {
                // Show OTP verification dialog
                // Ensure we hide loading before showing dialog?
                // Dialog might be pushed on top.
                
                final verified = await OtpVerificationDialog.show(context, phoneNumber);
                
                if (!verified) {
                  _showSnackBar('กรุณายืนยันเบอร์โทรศัพท์');
                  setState(() => _isLoading = false);
                  return;
                }
                
                // Mark as verified
                setState(() {
                  _isPhoneVerified = true;
                  _verifiedPhoneNumber = phoneNumber;
                });
              }
           }
        }
      }

      setState(() => _isLoading = false);

      if (_currentStep < _totalSteps - 1) {
        setState(() {
          _currentStep++;
        });
      } else {
        _handleSubmit();
      }
    } catch (e) {
      debugPrint('Error validating step: $e');
       _showSnackBar('เกิดข้อผิดพลาดในการตรวจสอบข้อมูล');
      setState(() => _isLoading = false);
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
            
            // Validate phone format
            if (field.fieldType == FieldType.phone) {
              final phone = controller.text.replaceAll(RegExp(r'[^0-9]'), '');
              final phoneRegex = RegExp(r'^0[0-9]{8,9}$');
              if (!phoneRegex.hasMatch(phone)) {
                _showSnackBar('รูปแบบเบอร์โทรศัพท์ไม่ถูกต้อง');
                return false;
              }
            }
            
            // Validate email format (if provided)
            if (field.fieldType == FieldType.email && controller.text.isNotEmpty) {
              final emailRegex = RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$');
              if (!emailRegex.hasMatch(controller.text)) {
                _showSnackBar('รูปแบบอีเมลไม่ถูกต้อง');
                return false;
              }
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

    try {
      final supabase = Supabase.instance.client;
      final userRepo = UserRepository(supabase);
      
      // 1. Check if username already exists
      final usernameExists = await userRepo.isUsernameExists(_usernameController.text);
      if (usernameExists) {
        throw Exception('ชื่อผู้ใช้นี้ถูกใช้งานแล้ว');
      }
      
      // 2. Get phone from dynamic fields
      final phoneController = _dynamicFieldValues['phone_controller'] as TextEditingController?;
      final phone = phoneController?.text.replaceAll(RegExp(r'[^0-9]'), '');
      
      // Check if phone already exists
      if (phone != null && phone.isNotEmpty) {
        final phoneExists = await userRepo.isPhoneExists(phone);
        if (phoneExists) {
          throw Exception('เบอร์โทรศัพท์นี้ถูกใช้งานแล้ว');
        }
      }
      
      // 3. Determine user type based on profession category
      auth.UserType userType;
      if (_selectedProfession?.category == UserCategory.consumer) {
        userType = auth.UserType.consumer;
      } else if (_selectedProfession?.nameEn?.toLowerCase().contains('clinic') == true) {
        userType = auth.UserType.clinic;
      } else {
        userType = auth.UserType.expert;
      }
      
      // 4. Create user in database
      final user = await userRepo.createUser(
        userType: userType,
        professionId: _selectedProfession?.id,
        firstName: _firstNameController.text,
        lastName: _lastNameController.text,
        username: _usernameController.text,
        password: _passwordController.text, // TODO: Hash password
        phone: phone,
      );
      
      debugPrint('✅ User created with ID: ${user.id}');
      
      // 5. Create profile based on user type
      if (userType == auth.UserType.consumer) {
        // Get email and birthday from dynamic fields
        final emailController = _dynamicFieldValues['email_controller'] as TextEditingController?;
        final birthday = _dynamicFieldValues['birthday_date'] as DateTime?;
        
        await userRepo.createConsumerProfile(
          userId: user.id,
          birthday: birthday,
        );
        debugPrint('✅ Consumer profile created');
      } else if (userType == auth.UserType.expert) {
        // Get expert-specific fields
        final businessNameController = _dynamicFieldValues['business_name_controller'] as TextEditingController?;
        final specialtyController = _dynamicFieldValues['specialty_controller'] as TextEditingController?;
        final businessPhoneController = _dynamicFieldValues['business_phone_controller'] as TextEditingController?;
        final businessEmailController = _dynamicFieldValues['business_email_controller'] as TextEditingController?;
        final businessAddressController = _dynamicFieldValues['business_address_controller'] as TextEditingController?;
        final experienceController = _dynamicFieldValues['experience_controller'] as TextEditingController?;
        final descriptionController = _dynamicFieldValues['description_controller'] as TextEditingController?;
        
        await userRepo.createExpertProfile(
          userId: user.id,
          businessName: businessNameController?.text,
          specialty: specialtyController?.text,
          businessPhone: businessPhoneController?.text,
          businessEmail: businessEmailController?.text,
          businessAddress: businessAddressController?.text,
          experienceYears: int.tryParse(experienceController?.text ?? ''),
          description: descriptionController?.text,
        );
        debugPrint('✅ Expert profile created');
      } else if (userType == auth.UserType.clinic) {
        // Get clinic-specific fields
        final clinicNameController = _dynamicFieldValues['clinic_name_controller'] as TextEditingController?;
        final licenseNumberController = _dynamicFieldValues['license_number_controller'] as TextEditingController?;
        final serviceTypeController = _dynamicFieldValues['service_type_controller'] as TextEditingController?;
        final businessPhoneController = _dynamicFieldValues['business_phone_controller'] as TextEditingController?;
        final businessEmailController = _dynamicFieldValues['business_email_controller'] as TextEditingController?;
        final businessAddressController = _dynamicFieldValues['business_address_controller'] as TextEditingController?;
        final descriptionController = _dynamicFieldValues['description_controller'] as TextEditingController?;
        
        await userRepo.createClinicProfile(
          userId: user.id,
          clinicName: clinicNameController?.text,
          licenseNumber: licenseNumberController?.text,
          serviceType: serviceTypeController?.text,
          businessPhone: businessPhoneController?.text,
          businessEmail: businessEmailController?.text,
          businessAddress: businessAddressController?.text,
          description: descriptionController?.text,
        );
        debugPrint('✅ Clinic profile created');
      }
      
      // 6. Save dynamic field values
      final Map<String, String> fieldValues = {};
      for (final field in _professionFields) {
        final controller = _dynamicFieldValues['${field.fieldId}_controller'] as TextEditingController?;
        if (controller != null && controller.text.isNotEmpty) {
          fieldValues[field.fieldId] = controller.text;
        }
        // Handle date fields
        final dateValue = _dynamicFieldValues['${field.fieldId}_date'] as DateTime?;
        if (dateValue != null) {
          fieldValues[field.fieldId] = dateValue.toIso8601String();
        }
      }
      
      if (fieldValues.isNotEmpty) {
        await userRepo.saveRegistrationData(user.id, fieldValues);
        debugPrint('✅ Registration data saved: ${fieldValues.length} fields');
      }
      
      // 7. Update verification status based on profession
      if (_selectedProfession?.requiresVerification == true) {
        await userRepo.updateVerificationStatus(user.id, auth.VerificationStatus.pending);
        debugPrint('✅ User set to pending verification');
      } else {
        await userRepo.updateVerificationStatus(user.id, auth.VerificationStatus.verified);
        debugPrint('✅ User verified (no verification required)');
      }

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
    } catch (e) {
      debugPrint('❌ Registration error: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        _showSnackBar('เกิดข้อผิดพลาด: ${e.toString().replaceAll('Exception: ', '')}');
      }
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

  String _getThaiShortMonth(int month) {
    const months = ['ม.ค.', 'ก.พ.', 'มี.ค.', 'เม.ย.', 'พ.ค.', 'มิ.ย.', 'ก.ค.', 'ส.ค.', 'ก.ย.', 'ต.ค.', 'พ.ย.', 'ธ.ค.'];
    return months[month - 1];
  }
}
