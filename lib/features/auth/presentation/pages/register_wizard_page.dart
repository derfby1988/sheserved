import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../admin/models/registration_field_config.dart';

/// Register Wizard Page - ลงทะเบียนแบบ 4 ขั้นตอน
class RegisterWizardPage extends StatefulWidget {
  const RegisterWizardPage({super.key});

  @override
  State<RegisterWizardPage> createState() => _RegisterWizardPageState();
}

class _RegisterWizardPageState extends State<RegisterWizardPage> {
  int _currentStep = 0;
  final int _totalSteps = 4;
  final _configService = RegistrationFieldConfigService();
  
  // Dynamic field values storage
  final Map<String, dynamic> _dynamicFieldValues = {};

  // Step 1 - ข้อมูลทั่วไป
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  UserType? _selectedUserType;

  // Step 2 - ข้อมูลสำหรับเข้าสู่ระบบ
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  // Step 3 - ข้อมูลจำเพาะ (Consumer)
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _birthdayController = TextEditingController();
  DateTime? _selectedBirthday;

  // Step 3 - ข้อมูลจำเพาะ (Expert/Clinic)
  final _businessNameController = TextEditingController();
  final _licenseNumberController = TextEditingController();
  final _businessAddressController = TextEditingController();
  final _businessPhoneController = TextEditingController();
  final _businessEmailController = TextEditingController();
  final _specialtyController = TextEditingController();
  final _experienceController = TextEditingController();
  final _descriptionController = TextEditingController();
  String? _idCardImagePath;
  String? _licenseImagePath;
  String? _profileImagePath;
  String? _businessImagePath;

  // Step 4 - ยืนยัน
  bool _acceptTerms = false;
  bool _isLoading = false;

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _birthdayController.dispose();
    _businessNameController.dispose();
    _licenseNumberController.dispose();
    _businessAddressController.dispose();
    _businessPhoneController.dispose();
    _businessEmailController.dispose();
    _specialtyController.dispose();
    _experienceController.dispose();
    _descriptionController.dispose();
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

  /// Step 1: ข้อมูลทั่วไป
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

        // ประเภทผู้ใช้
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: UserType.values.map((type) {
            final isSelected = _selectedUserType == type;
            return GestureDetector(
              onTap: () {
                setState(() {
                  _selectedUserType = type;
                });
              },
              child: Column(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppColors.primary,
                        width: 2,
                      ),
                      color: isSelected ? AppColors.primary : Colors.white,
                    ),
                    child: isSelected
                        ? const Icon(
                            Icons.check,
                            color: Colors.white,
                            size: 16,
                          )
                        : null,
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: 80,
                    child: Text(
                      type.shortTitle,
                      textAlign: TextAlign.center,
                      style: AppTextStyles.caption.copyWith(
                        color: isSelected
                            ? AppColors.primary
                            : AppColors.textSecondary,
                        fontWeight:
                            isSelected ? FontWeight.w600 : FontWeight.normal,
                        fontSize: 10,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ],
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

  /// Step 3: ข้อมูลจำเพาะ - สร้างแบบ Dynamic จาก Config
  Widget _buildStep3SpecificInfo() {
    final userType = _selectedUserType ?? UserType.consumer;
    final fields = _configService.getConfigsForUserType(userType);
    
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
          'สำหรับ ${userType.title}',
          textAlign: TextAlign.center,
          style: AppTextStyles.bodySmall.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 28),
        
        // Dynamic fields from config
        ...fields.map((field) => Padding(
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
    if (!_dynamicFieldValues.containsKey('${field.id}_controller')) {
      _dynamicFieldValues['${field.id}_controller'] = TextEditingController();
    }
    final controller = _dynamicFieldValues['${field.id}_controller'] as TextEditingController;
    
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
      hintText: field.hint ?? field.label,
      prefixIcon: _getIconForFieldType(field.fieldType),
      keyboardType: keyboardType,
      maxLines: maxLines,
    );
  }
  
  Widget _buildDynamicDateField(RegistrationFieldConfig field) {
    if (!_dynamicFieldValues.containsKey('${field.id}_controller')) {
      _dynamicFieldValues['${field.id}_controller'] = TextEditingController();
    }
    final controller = _dynamicFieldValues['${field.id}_controller'] as TextEditingController;
    
    return GestureDetector(
      onTap: () => _selectDateForField(field.id, controller),
      child: AbsorbPointer(
        child: _buildInputField(
          controller: controller,
          hintText: field.hint ?? field.label,
          prefixIcon: Icons.calendar_today_outlined,
        ),
      ),
    );
  }
  
  Widget _buildDynamicImageField(RegistrationFieldConfig field) {
    final imagePath = _dynamicFieldValues['${field.id}_image'] as String?;
    
    return _buildImageUploadField(
      label: field.label,
      imagePath: imagePath,
      onTap: () => _selectImageForField(field.id),
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
              _buildSummaryItem('ประเภทผู้ใช้', _selectedUserType?.title ?? '-'),
              const Divider(height: 24),
              _buildSummaryItem('ชื่อ-นามสกุล',
                  '${_firstNameController.text} ${_lastNameController.text}'),
              _buildSummaryItem('ชื่อผู้ใช้', _usernameController.text),
              if (_selectedUserType == UserType.consumer) ...[
                _buildSummaryItem('อีเมล', _emailController.text),
                _buildSummaryItem('เบอร์โทร', _phoneController.text),
                _buildSummaryItem('วันเกิด', _birthdayController.text),
              ] else ...[
                _buildSummaryItem(
                    'ชื่อธุรกิจ/คลินิก', _businessNameController.text),
                _buildSummaryItem('เบอร์โทร', _businessPhoneController.text),
                _buildSummaryItem('อีเมล', _businessEmailController.text),
              ],
            ],
          ),
        ),
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
            style: BorderStyle.solid,
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
    // Validate current step
    if (!_validateCurrentStep()) return;

    if (_currentStep < _totalSteps - 1) {
      setState(() {
        _currentStep++;
      });
    } else {
      // Submit registration
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
        if (_selectedUserType == null) {
          _showSnackBar('กรุณาเลือกประเภทผู้ใช้');
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
        if (_selectedUserType == UserType.consumer) {
          if (_emailController.text.isEmpty) {
            _showSnackBar('กรุณากรอกอีเมล');
            return false;
          }
          if (_phoneController.text.isEmpty) {
            _showSnackBar('กรุณากรอกเบอร์โทร');
            return false;
          }
        } else {
          if (_businessNameController.text.isEmpty) {
            _showSnackBar('กรุณากรอกชื่อธุรกิจ/คลินิก');
            return false;
          }
          if (_businessPhoneController.text.isEmpty) {
            _showSnackBar('กรุณากรอกเบอร์โทรติดต่อ');
            return false;
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
    await Future.delayed(const Duration(seconds: 2));

    if (mounted) {
      setState(() {
        _isLoading = false;
      });

      _showSnackBar('ลงทะเบียนสำเร็จ!');
      Navigator.pushReplacementNamed(context, '/login');
    }
  }

  Future<void> _selectBirthday() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now().subtract(const Duration(days: 6570)), // 18 years ago
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
      locale: const Locale('th', 'TH'),
    );

    if (picked != null) {
      setState(() {
        _selectedBirthday = picked;
        _birthdayController.text =
            '${picked.day}/${picked.month}/${picked.year + 543}'; // Buddhist era
      });
    }
  }

  void _selectImage(String type) {
    // TODO: Implement image picker
    _showSnackBar('เลือกรูปภาพจะเปิดใช้งานเร็วๆ นี้');
    
    // Simulate image selection for now
    setState(() {
      switch (type) {
        case 'profile':
          _profileImagePath = 'selected';
          break;
        case 'idCard':
          _idCardImagePath = 'selected';
          break;
        case 'license':
          _licenseImagePath = 'selected';
          break;
        case 'business':
          _businessImagePath = 'selected';
          break;
      }
    });
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
