import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:thai_buddhist_date/thai_buddhist_date.dart';
import 'package:thai_buddhist_date_pickers/thai_buddhist_date_pickers.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../../shared/widgets/widgets.dart';
import '../../../../shared/widgets/widgets.dart';
import '../../../../services/auth_service.dart';
import '../../../admin/models/profession.dart' as prof;
import '../../../admin/models/registration_field_config.dart';
import '../../../auth/data/models/user_model.dart' as auth;
import '../../data/repositories/profile_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  late final ProfileRepository _repository;
  final Map<String, TextEditingController> _controllers = {};
  final Map<String, dynamic> _dynamicValues = {};
  
  auth.UserModel? _user;
  prof.Profession? _profession;
  List<RegistrationFieldConfig> _fields = [];
  Map<String, String> _dynamicData = {};
  
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isEditing = false;
  File? _tempProfileImage;

  @override
  void initState() {
    super.initState();
    _repository = ProfileRepository(Supabase.instance.client);
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    setState(() => _isLoading = true);
    try {
      final userId = AuthService.instance.userId;
      if (userId == null) throw Exception('User not logged in');

      final data = await _repository.getFullProfileData(userId);
      if (mounted) {
        setState(() {
          _user = data['user'];
          _profession = data['profession'];
          _fields = data['fields'];
          _dynamicData = data['dynamicData'];
          _initControllers();
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading profile: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('โหลดข้อมูลไม่สำเร็จ: $e')),
        );
      }
    }
  }

  void _initControllers() {
    if (_user == null) return;
    
    // Core user info
    _controllers['first_name'] = TextEditingController(text: _user!.firstName);
    _controllers['last_name'] = TextEditingController(text: _user!.lastName);

    // Dynamic fields
    for (final field in _fields) {
      final value = _dynamicData[field.fieldId] ?? '';
      if (field.fieldType == FieldType.date) {
        _dynamicValues[field.fieldId] = value.isNotEmpty ? DateTime.tryParse(value) : null;
      } else if (field.fieldType == FieldType.image) {
        _dynamicValues[field.fieldId] = value; // URL
      } else {
        _controllers[field.fieldId] = TextEditingController(text: value);
      }
    }
  }

  @override
  void dispose() {
    for (var controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      drawer: const TlzDrawer(),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _user == null
              ? const Center(child: Text('ไม่พบข้อมูลผู้ใช้'))
              : _buildContent(),
    );
  }

  Widget _buildContent() {
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: TlzAppTopBar.onPrimary(
            searchHintText: 'ค้นหา...',
            leading: const TlzHamburgerMenu(),
            actions: [
              if (!_isEditing)
                IconButton(
                  icon: const Icon(Icons.edit, color: Colors.white),
                  onPressed: () => setState(() => _isEditing = true),
                )
              else
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () {
                    setState(() {
                      _isEditing = false;
                      _tempProfileImage = null;
                    });
                    _loadProfile();
                  },
                ),
            ],
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.all(16),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              _buildHeader(),
              const SizedBox(height: 24),
              _buildCoreInfo(),
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 16),
              Text(
                'ข้อมูลเพิ่มเติม (${_profession?.name ?? ""})',
                style: AppTextStyles.heading3.copyWith(color: AppColors.primary),
              ),
              const SizedBox(height: 16),
              ..._buildDynamicFields(),
              if (_isEditing) ...[
                const SizedBox(height: 32),
                TlzButton(
                  text: 'บันทึกข้อมูล',
                  onPressed: _isSaving ? null : _handleSave,
                  isLoading: _isSaving,
                ),
                const SizedBox(height: 50),
              ],
            ]),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    return Center(
      child: Column(
        children: [
          Stack(
            children: [
              CircleAvatar(
                radius: 60,
                backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                backgroundImage: _tempProfileImage != null
                    ? FileImage(_tempProfileImage!)
                    : (_user?.profileImageUrl != null
                        ? NetworkImage(_user!.profileImageUrl!)
                        : null) as ImageProvider?,
                child: _user?.profileImageUrl == null && _tempProfileImage == null
                    ? const Icon(Icons.person, size: 60, color: AppColors.primary)
                    : null,
              ),
              if (_isEditing)
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: GestureDetector(
                    onTap: _pickImage,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: const BoxDecoration(
                        color: AppColors.primary,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.camera_alt, color: Colors.white, size: 20),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            _user?.fullName ?? '',
            style: AppTextStyles.heading2,
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _user?.userType.displayName ?? '',
                  style: AppTextStyles.bodySmall.copyWith(color: AppColors.primary),
                ),
              ),
              if (_user?.verificationStatus == auth.VerificationStatus.verified) ...[
                const SizedBox(width: 8),
                const Icon(Icons.verified, color: AppColors.primary, size: 16),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCoreInfo() {
    return Column(
      children: [
        _buildFieldRow('ชื่อผู้ใช้', _user?.username ?? '', isEditable: false),
        const SizedBox(height: 12),
        if (_isEditing) ...[
          TlzTextField(
            label: 'ชื่อ',
            controller: _controllers['first_name'],
          ),
          const SizedBox(height: 12),
          TlzTextField(
            label: 'นามสกุล',
            controller: _controllers['last_name'],
          ),
        ] else ...[
          _buildFieldRow('ชื่อ', _user?.firstName ?? ''),
          const SizedBox(height: 12),
          _buildFieldRow('นามสกุล', _user?.lastName ?? ''),
        ],
      ],
    );
  }

  List<Widget> _buildDynamicFields() {
    return _fields.map((field) {
      if (_isEditing) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: _buildEditableDynamicField(field),
        );
      } else {
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _buildReadonlyDynamicField(field),
        );
      }
    }).toList();
  }

  Widget _buildReadonlyDynamicField(RegistrationFieldConfig field) {
    String value = _dynamicData[field.fieldId] ?? '';
    
    if (field.fieldType == FieldType.date && value.isNotEmpty) {
      final date = DateTime.tryParse(value);
      if (date != null) {
        value = '${date.day} ${_getThaiShortMonth(date.month)} ${date.year + 543}';
      }
    } else if (field.fieldType == FieldType.image) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(field.label, style: AppTextStyles.bodySmall.copyWith(color: Colors.grey)),
          const SizedBox(height: 8),
          if (value.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                value,
                height: 150,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Container(
                  height: 150,
                  color: Colors.grey[200],
                  child: const Icon(Icons.broken_image),
                ),
              ),
            )
          else
            const Text('ไม่มีข้อมูล'),
        ],
      );
    }

    return _buildFieldRow(field.label, value.isEmpty ? 'ไม่มีข้อมูล' : value);
  }

  Widget _buildEditableDynamicField(RegistrationFieldConfig field) {
    if (field.fieldType == FieldType.date) {
      final date = _dynamicValues[field.fieldId] as DateTime?;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(field.label, style: AppTextStyles.bodyMedium),
          const SizedBox(height: 8),
          InkWell(
            onTap: () => _selectDate(field.fieldId),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey[300]!),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    date != null 
                      ? '${date.day} ${_getThaiShortMonth(date.month)} ${date.year + 543}'
                      : field.hint ?? 'เลือกวันที่',
                    style: TextStyle(color: date != null ? Colors.black : Colors.grey),
                  ),
                  const Icon(Icons.calendar_today, size: 20),
                ],
              ),
            ),
          ),
        ],
      );
    }

    if (field.fieldType == FieldType.image) {
       final currentUrl = _dynamicValues[field.fieldId] as String?;
       return Column(
         crossAxisAlignment: CrossAxisAlignment.start,
         children: [
           Text(field.label, style: AppTextStyles.bodyMedium),
           const SizedBox(height: 8),
           if (currentUrl != null && currentUrl.isNotEmpty)
             Stack(
               children: [
                 ClipRRect(
                   borderRadius: BorderRadius.circular(8),
                   child: Image.network(currentUrl, height: 100, width: 100, fit: BoxFit.cover),
                 ),
                 Positioned(
                   top: 0, right: 0,
                   child: IconButton(
                     icon: const Icon(Icons.cancel, color: Colors.red),
                     onPressed: () => setState(() => _dynamicValues[field.fieldId] = null),
                   ),
                 )
               ],
             )
           else
             const Text('อัพโหลดรูปภาพ (เร็วๆ นี้)'),
         ],
       );
    }

    return TlzTextField(
      label: field.label,
      controller: _controllers[field.fieldId],
      hint: field.hint,
      keyboardType: field.fieldType == FieldType.phone ? TextInputType.phone : TextInputType.text,
      maxLines: field.fieldType == FieldType.multilineText ? 3 : 1,
    );
  }

  Widget _buildFieldRow(String label, String value, {bool isEditable = true}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 100,
          child: Text(
            label,
            style: AppTextStyles.bodySmall.copyWith(color: Colors.grey),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: AppTextStyles.bodyMedium,
          ),
        ),
      ],
    );
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      setState(() {
        _tempProfileImage = File(image.path);
      });
    }
  }

  Future<void> _selectDate(String fieldId) async {
    final current = _dynamicValues[fieldId] as DateTime? ?? DateTime.now();
    final picked = await showThaiDatePicker(
      context,
      initialDate: current,
      firstDate: DateTime(DateTime.now().year - 100),
      lastDate: DateTime.now(),
      era: Era.be,
      locale: 'th_TH',
    );
    if (picked != null) {
      setState(() {
        _dynamicValues[fieldId] = picked;
      });
    }
  }

  String _getThaiShortMonth(int month) {
    const months = ['ม.ค.', 'ก.พ.', 'มี.ค.', 'เม.ย.', 'พ.ค.', 'มิ.ย.', 'ก.ค.', 'ส.ค.', 'ก.ย.', 'ต.ค.', 'พ.ย.', 'ธ.ค.'];
    return months[month - 1];
  }

  void _handleSave() async {
    if (_user == null) return;
    setState(() => _isSaving = true);

    try {
      final userId = _user!.id;
      final Map<String, dynamic> coreData = {
        'first_name': _controllers['first_name']?.text,
        'last_name': _controllers['last_name']?.text,
      };

      final Map<String, String> dynamicData = {};
      for (final field in _fields) {
        if (field.fieldType == FieldType.date) {
          final date = _dynamicValues[field.fieldId] as DateTime?;
          if (date != null) dynamicData[field.fieldId] = date.toIso8601String();
        } else if (field.fieldType != FieldType.image) {
          final text = _controllers[field.fieldId]?.text ?? '';
          dynamicData[field.fieldId] = text;
        }
      }

      // Handle Profile Image Upload
      if (_tempProfileImage != null) {
         try {
           final fileName = 'profiles/$userId/${DateTime.now().millisecondsSinceEpoch}.jpg';
           final supabase = Supabase.instance.client;
           await supabase.storage.from('public').upload(fileName, _tempProfileImage!);
           final imageUrl = supabase.storage.from('public').getPublicUrl(fileName);
           coreData['profile_image_url'] = imageUrl;
         } catch (e) {
           debugPrint('Image upload failed: $e');
         }
      }

      await _repository.updateProfile(
        userId: userId,
        coreData: coreData,
        dynamicData: dynamicData,
        userType: _user!.userType,
      );
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('บันทึกข้อมูลสำเร็จ')),
        );
        setState(() {
          _isEditing = false;
          _isSaving = false;
          _tempProfileImage = null;
        });
        _loadProfile();
      }
    } catch (e) {
      debugPrint('Save error: $e');
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('บันทึกไม่สำเร็จ: $e')),
        );
      }
    }
  }
}
