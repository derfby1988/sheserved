import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';
import 'package:thai_buddhist_date/thai_buddhist_date.dart';
import 'package:thai_buddhist_date_pickers/thai_buddhist_date_pickers.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../../shared/widgets/widgets.dart';
import '../../../../services/auth_service.dart';
import '../../../admin/models/profession.dart' as prof;
import '../../../admin/models/registration_field_config.dart';
import 'package:sheserved/features/home/presentation/widgets/background_permission_dialog.dart';
import 'package:sheserved/services/location_tracking_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../data/repositories/profile_repository.dart';
import '../../../auth/data/models/user_model.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supa;
import '../../../donation/data/repositories/donation_repository.dart';
import '../../../donation/presentation/pages/leader_verification_page.dart';
import '../../../donation/presentation/widgets/donation_request_management_panel.dart';
import '../../../donation/presentation/widgets/donation_approver_settings_widget.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  late final ProfileRepository _repository;
  late final DonationRepository _donationRepository;
  final Map<String, TextEditingController> _controllers = {};
  final Map<String, dynamic> _dynamicValues = {};
  
  UserModel? _user;
  prof.Profession? _profession;
  List<RegistrationFieldConfig> _fields = [];
  Map<String, String> _dynamicData = {};
  
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isEditing = false;
  bool _thaiMhungEnabled = true; // ความสมัครใจไทยมุง
  int _alertRadius = 500; // รัศมีการแจ้งเตือน (เมตร)
  File? _tempProfileImage;
  bool _isUploadingAvatar = false;
  int _selectedTabIndex = 0; // 0: Profile, 1: Volunteer, 2: Approve, 3: Requests

  // สิทธิ์อนุมัติบริจาค (ดึงจากหมวดหมู่ user_categories.can_approve_donation)
  bool _canApproveDonation = false;

  // ฟีเจอร์กำหนดอาชีพที่เห็นวิดีโอไม่เบลอ
  List<prof.Profession> _allVolunteerProfessions = [];
  Set<String> _selectedUnblurredIds = {};
  bool _isLoadingProfessions = false;
  bool _isSavingUnblurred = false; // สถานะการบันทึกสิทธิ์ดูวิดีโอ
  String? _selectedCategory; // หมวดหมู่ที่กำลังเลือกอยู่
  
  String? _highlightRequestId; // สำหรับ auto-focus เมื่อเพิ่งสร้างคำร้องขอเสร็จ

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map<String, dynamic>) {
      if (args['tabIndex'] != null && _selectedTabIndex != args['tabIndex']) {
        _selectedTabIndex = args['tabIndex'] as int;
      }
      if (args['highlightRequestId'] != null) {
        _highlightRequestId = args['highlightRequestId'] as String;
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _repository = ProfileRepository(Supabase.instance.client);
    _donationRepository = DonationRepository(Supabase.instance.client);
    
    // Auth re-verify as per login_navigation_guide
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!AuthService.instance.isLoggedIn) {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
        return;
      }
      _loadProfile();
      _loadVolunteerProfessions();
      _checkCanApproveDonationStatus();
    });
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
          _thaiMhungEnabled = _user?.isThaiMhungEnabled ?? true;
          _alertRadius = _user?.alertRadius ?? 500;
          
          // โหลดค่า unblurred_profession_ids จาก dynamicData (user_registration_data) 
          // เพื่อความเข้ากันได้ 100% กับ Supabase Cloud โดยไม่ต้องแก้ Schema ตารางหลัก
          final unblurredRaw = _dynamicData['unblurred_profession_ids'];
          if (unblurredRaw != null && unblurredRaw.isNotEmpty) {
            try {
              final List<dynamic> decoded = json.decode(unblurredRaw);
              _selectedUnblurredIds = Set<String>.from(decoded.map((e) => e.toString()));
            } catch (e) {
              _selectedUnblurredIds = Set<String>.from(_user?.unblurredProfessionIds ?? []);
            }
          } else {
            _selectedUnblurredIds = Set<String>.from(_user?.unblurredProfessionIds ?? []);
          }

          // Load settings for approver

          _initControllers();
          _isLoading = false;
        });

        // ซิงค์ข้อมูลลง Local Session เสมอเพื่อให้ส่วนอื่นๆ ของแอปอัปเดตตาม
        if (_user != null) {
          AuthService.instance.login(_user!);
        }
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

  Future<void> _checkCanApproveDonationStatus() async {
    final userId = AuthService.instance.userId;
    if (userId == null) return;
    try {
      // ดึง profession_id ของ user
      final userRow = await supa.Supabase.instance.client
          .from('users')
          .select('profession_id')
          .eq('id', userId)
          .maybeSingle();
      final professionId = userRow?['profession_id'] as String?;
      if (professionId == null) return;

      // ดึง category ของ profession นั้น
      final profRow = await supa.Supabase.instance.client
          .from('professions')
          .select('category')
          .eq('id', professionId)
          .maybeSingle();
      final categoryId = profRow?['category'] as String?;
      if (categoryId == null) return;

      // ตรวจ can_approve_donation จาก user_categories
      final catRow = await supa.Supabase.instance.client
          .from('user_categories')
          .select('can_approve_donation')
          .eq('id', categoryId)
          .maybeSingle();
      final canApprove = catRow?['can_approve_donation'] as bool? ?? false;

      if (mounted) setState(() => _canApproveDonation = canApprove);
    } catch (e) {
      debugPrint('ProfilePage: Error checking can_approve_donation: $e');
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
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('กรุณาเข้าสู่ระบบเพื่อดูโปรไฟล์ของคุณ'),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () {
                          Navigator.pushNamed(context, '/login', arguments: '/profile');
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('เข้าสู่ระบบ / สมัครสมาชิก'),
                      ),
                    ],
                  ),
                )
              : SafeArea(
                  top: false, 
                  child: _buildContent(),
                ),
    );
  }

  Widget _buildContent() {
    return CustomScrollView(
      slivers: [
        SliverAppBar(
          pinned: true,
          floating: true,
          backgroundColor: AppColors.primary,
          automaticallyImplyLeading: false,
          elevation: 2,
          titleSpacing: 0,
          toolbarHeight: 65,
          title: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TlzAppTopBar.onPrimary(
              searchHintText: 'ค้นหา...',
              leading: const TlzHamburgerMenu(),
              actions: const [],
            ),
          ),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(50),
            child: Container(
              width: double.infinity,
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(bottom: BorderSide(color: Color(0xFFEEEEEE))),
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                      SizedBox(
                        width: MediaQuery.of(context).size.width / (_canApproveDonation ? 3 : 2),
                        child: _buildTabItem(
                          icon: Icons.person_outline,
                          text: _profession?.name ?? 'โปรไฟล์',
                          isActive: _selectedTabIndex == 0,
                          activeColor: AppColors.primary,
                          onTap: () => setState(() => _selectedTabIndex = 0),
                        ),
                      ),
                    if (_thaiMhungEnabled || (_profession?.isVolunteer ?? false))
                      SizedBox(
                        width: MediaQuery.of(context).size.width / (_canApproveDonation ? 3 : 2),
                        child: _buildTabItem(
                          icon: Icons.volunteer_activism_outlined,
                          text: 'จิตอาสา',
                          isActive: _selectedTabIndex == 1,
                          activeColor: const Color(0xFFF5A623),
                          onTap: () => setState(() => _selectedTabIndex = 1),
                        ),
                      ),
                    if (_canApproveDonation)
                      SizedBox(
                        width: MediaQuery.of(context).size.width / 3,
                        child: _buildTabItem(
                          icon: Icons.admin_panel_settings_outlined,
                          text: 'อนุมัติบริจาค',
                          isActive: _selectedTabIndex == 2,
                          activeColor: Colors.teal,
                          onTap: () => setState(() => _selectedTabIndex = 2),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.all(16),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              if (_selectedTabIndex == 0) ...[
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
              ] else if (_selectedTabIndex == 1) ...[
                _buildNotificationSettings(),
              ] else if (_selectedTabIndex == 2 && _canApproveDonation) ...[
                DonationApproverSettingsWidget(
                  repository: _donationRepository,
                  userId: _user?.id,
                ),
                const SizedBox(height: 16),
                _buildBeneficiaryRegistrationEntry(),
                const SizedBox(height: 16),
                const LeaderVerificationPage(),
                const SizedBox(height: 24),
              ],
              if (_isEditing && _selectedTabIndex == 0) ...[
                const SizedBox(height: 32),
                TlzButton(
                  text: 'บันทึกข้อมูล',
                  onPressed: _isSaving ? null : _handleSave,
                  isLoading: _isSaving,
                ),
              ],
              if (_selectedTabIndex == 0) ...[
                const SizedBox(height: 40),
                const Divider(thickness: 1.5, color: Color(0xFFEEEEEE)),
                const SizedBox(height: 16),
                DonationRequestManagementPanel(
                  repository: _donationRepository,
                  userId: _user?.id,
                  showCreateButton: true,
                  maxHeight: 550, // จำกัดความสูงเพื่อให้ Scroll ได้หากมีมากกว่า 3 รายการ
                  highlightRequestId: _highlightRequestId,
                ),
              ],
              const SizedBox(height: 50),
            ]),
          ),
        ),
      ],
    );
  }

  Widget _buildBeneficiaryRegistrationEntry() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.orange.shade200),
      ),
      color: Colors.orange.shade50,
      child: InkWell(
        onTap: () {
          // TODO: สร้างและนำทางไปยัง BeneficiaryRegistrationPage
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('กำลังเปิดหน้าลงทะเบียนองค์กรมูลนิธิ...')),
          );
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: const BoxDecoration(
                  color: Colors.orange,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.account_balance, color: Colors.white),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ลงทะเบียนองค์กรมูลนิธิ/MOU',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.deepOrange),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'เป็นตัวแทนบัญชีรับมรดกเพื่อนำไปใช้บรรเทาสาธารณภัย',
                      style: TextStyle(fontSize: 12, color: Colors.deepOrange),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.orange),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTabItem({
    required IconData icon,
    required String text,
    required bool isActive,
    required Color activeColor,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 50,
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: isActive ? activeColor : Colors.transparent,
              width: 3,
            ),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 18,
              color: isActive ? activeColor : Colors.grey,
            ),
            const SizedBox(width: 8),
            Text(
              text,
              style: AppTextStyles.bodySmall.copyWith(
                color: isActive ? activeColor : Colors.grey,
                fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Center(
      child: Column(
        children: [
          const SizedBox(height: 16),
          Stack(
            children: [
              GestureDetector(
                onTap: _isUploadingAvatar ? null : _showImagePickerDropdown,
                child: ClipOval(
                  child: Container(
                    width: 120, // radius 60
                    height: 120,
                    color: AppColors.primary.withOpacity(0.1),
                    child: _isUploadingAvatar 
                      ? const Center(child: CircularProgressIndicator(color: AppColors.primary)) 
                      : _user?.profileImageUrl != null
                            ? Image.network(
                                _user!.profileImageUrl!,
                                fit: BoxFit.cover,
                                loadingBuilder: (context, child, loadingProgress) {
                                  if (loadingProgress == null) return child;
                                  return Center(
                                    child: CircularProgressIndicator(
                                      color: AppColors.primary,
                                      value: loadingProgress.expectedTotalBytes != null
                                          ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                                          : null,
                                    ),
                                  );
                                },
                                errorBuilder: (c, e, s) => const Icon(Icons.person, size: 60, color: AppColors.primary),
                              )
                            : const Icon(Icons.person, size: 60, color: AppColors.primary),
                  ),
                ),
              ),
              if (!_isUploadingAvatar)
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: GestureDetector(
                    onTap: _showImagePickerDropdown,
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
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _user?.fullName ?? '',
                style: AppTextStyles.heading2,
              ),
              const SizedBox(width: 8),
              if (!_isEditing)
                GestureDetector(
                  onTap: () => setState(() => _isEditing = true),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5A623).withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.edit, color: Color(0xFFF5A623), size: 18),
                  ),
                )
              else
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _isEditing = false;
                      _tempProfileImage = null;
                    });
                    _loadProfile();
                  },
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.close, color: Colors.red, size: 18),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _profession?.category.name ?? _user?.userType.displayName ?? '',
                style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
              ),
              if (_user?.verificationStatus == VerificationStatus.verified) ...[
                const SizedBox(width: 8),
                const Icon(Icons.verified, color: AppColors.primary, size: 16),
              ],
            ],
          ),
          const SizedBox(height: 8),
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

  Widget _buildNotificationSettings() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'การตั้งค่าการแจ้งเตือน',
          style: AppTextStyles.heading3.copyWith(color: AppColors.primary),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey[200]!),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'แจ้งเหตุฉุกเฉินใกล้ตัว (ไทยมุง)',
                      style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      'รับแจ้งเตือนเมื่อมีเหตุการณ์เกิดขึ้นในรัศมี 500 เมตร',
                      style: AppTextStyles.bodySmall.copyWith(color: Colors.grey),
                    ),
                  ],
                ),
              ),
              Switch(
                value: _thaiMhungEnabled,
                onChanged: (value) => _updateVolunteerSettings(enabled: value),
                activeThumbColor: AppColors.primary,
              ),
            ],
          ),
        ),
        if (_thaiMhungEnabled || (_profession?.isVolunteer ?? false)) ...[
          const SizedBox(height: 24),
          _buildRadiusSection(),
          const SizedBox(height: 24),
          _buildUnblurredProfessionSection(),
        ],
      ],
    );
  }

  Widget _buildRadiusSection() {
    final isProfessional = _profession?.isVolunteer ?? false;
    final title = isProfessional ? 'รัศมีพื้นที่รับผิดชอบ' : 'พื้นที่ให้ทางแก่เจ้าหน้าที่';
    final description = isProfessional 
        ? 'ระบุระยะทางที่คุณสามารถเดินทางไปช่วยเหลือเหตุฉุกเฉินได้' 
        : 'รัศมีสำหรับการแจ้งเตือนเหตุ เพื่ออำนวยความสะดวก "เส้นทาง"แก่เจ้าหน้าที่';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.bold),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _alertRadius >= 1000 
                    ? '${(_alertRadius / 1000).toStringAsFixed(1)} กม.' 
                    : '$_alertRadius ม.',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            description,
            style: AppTextStyles.bodySmall.copyWith(color: Colors.grey),
          ),
          const SizedBox(height: 16),
          Slider(
            value: _alertRadius.toDouble().clamp(500, 100000),
            min: 500,
            max: 100000,
            divisions: 199,
            onChanged: (value) => setState(() => _alertRadius = value.round()),
            onChangeEnd: (value) => _updateVolunteerSettings(radius: value.round()),
            activeColor: AppColors.primary,
            inactiveColor: Colors.grey[200],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('500 ม.', style: AppTextStyles.bodySmall.copyWith(color: Colors.grey)),
              Text('100 กม.', style: AppTextStyles.bodySmall.copyWith(color: Colors.grey)),
            ],
          ),
        ],
      ),
    );
  }

  /// โหลดรายการอาชีพจิตอาสาทั้งหมดจาก Supabase Professions Table
  Future<void> _loadVolunteerProfessions() async {
    if (_isLoadingProfessions) return;
    setState(() => _isLoadingProfessions = true);
    try {
      final response = await Supabase.instance.client
          .from('professions')
          .select('''
            id, name, color_hex, is_volunteer, is_active, category, display_order,
            category_data:user_categories!professions_category_fkey(*)
          ''')
          .eq('is_active', true)
          .order('display_order'); // Order within categories
      if (mounted) {
        setState(() {
          _allVolunteerProfessions = (response as List).map((json) {
            // Handle category safely
            prof.UserCategory category;
            if (json['category_data'] != null) {
              category = prof.UserCategory.fromJson(json['category_data']);
            } else {
              category = prof.UserCategory.fromString(json['category'] ?? 'consumer');
            }

            return prof.Profession(
              id: json['id'] ?? '',
              name: json['name'] ?? '',
              colorHex: json['color_hex'],
              isVolunteer: json['is_volunteer'] ?? false,
              category: category,
              isActive: json['is_active'] ?? true,
              displayOrder: json['display_order'] ?? 0,
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            );
          }).toList();

          // เรียงลำดับเพิ่มเติม: หมวดหมู่ (displayOrder) -> อาชีพ (displayOrder)
          _allVolunteerProfessions.sort((a, b) {
            final catCompare = a.category.displayOrder.compareTo(b.category.displayOrder);
            if (catCompare != 0) return catCompare;
            return a.displayOrder.compareTo(b.displayOrder);
          });

          // ตั้งค่าเริ่มต้นเป็นกลุ่มแรกหากยังไม่ได้เลือก
          if (_allVolunteerProfessions.isNotEmpty && _selectedCategory == null) {
            _selectedCategory = _allVolunteerProfessions.first.category.id;
          }
          _isLoadingProfessions = false;
        });
      }
    } catch (e) {
      debugPrint('ProfilePage: Error loading professions: $e');
      if (mounted) setState(() => _isLoadingProfessions = false);
    }
  }

  /// UI เลือกอาชีพที่อนุญาตให้เห็นวิดีโอไม่เบลอ
  Widget _buildUnblurredProfessionSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: _isSavingUnblurred
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.red),
                        ),
                      )
                    : const Icon(Icons.visibility, color: Colors.red, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'สิทธิ์ดูวิดีโอต้นฉบับ',
                      style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      'เลือกอาชีพจิตอาสาที่อนุญาตให้เห็นภาพ/วิดีโอไม่ผ่านการเบลอ',
                      style: AppTextStyles.bodySmall.copyWith(color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_isLoadingProfessions)
            const Center(child: CircularProgressIndicator())
          else if (_allVolunteerProfessions.isEmpty)
            Text(
              'ไม่พบรายการอาชีพ',
              style: AppTextStyles.bodySmall.copyWith(color: Colors.grey),
            )
          else ...[
            // 1. ส่วนเลือกกลุ่มอาชีพ (Category Selector)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _getUniqueCategories().map((cat) {
                  final isSelected = _selectedCategory == cat.id;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(cat.displayName),
                      selected: isSelected,
                      onSelected: (val) {
                        if (val) setState(() => _selectedCategory = cat.id);
                      },
                      selectedColor: AppColors.primary.withOpacity(0.1),
                      labelStyle: AppTextStyles.bodySmall.copyWith(
                        color: isSelected ? AppColors.primary : Colors.grey,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 16),
            // 2. ส่วนเลือกอาชีพในกลุ่มที่เลือก (Professions in Selected Category)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _allVolunteerProfessions
                  .where((p) => p.category.id == _selectedCategory)
                  .map((p) {
                final isSelected = _selectedUnblurredIds.contains(p.id);
                Color chipColor = AppColors.primary;
                if (p.colorHex != null && p.colorHex!.isNotEmpty) {
                  try {
                    chipColor = Color(int.parse(p.colorHex!.replaceFirst('#', '0xFF')));
                  } catch (_) {}
                }
                return FilterChip(
                  label: Text(p.name),
                  selected: isSelected,
                  selectedColor: chipColor.withOpacity(0.2),
                  checkmarkColor: chipColor,
                  labelStyle: AppTextStyles.bodySmall.copyWith(
                    color: isSelected ? chipColor : Colors.grey[700],
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                  side: BorderSide(
                    color: isSelected ? chipColor : Colors.grey[300]!,
                    width: isSelected ? 1.5 : 1,
                  ),
                  onSelected: _isSavingUnblurred
                      ? null
                      : (val) {
                          setState(() {
                            if (val) {
                              _selectedUnblurredIds.add(p.id);
                            } else {
                              _selectedUnblurredIds.remove(p.id);
                            }
                          });
                          _saveUnblurredProfessions();
                        },
                );
              }).toList(),
            ),
            const SizedBox(height: 8),
            Text(
              'หมายเหตุ: อาชีพที่ไม่ได้เลือกจะเห็นเพียงภาพเบลอ (Privacy Mode)',
              style: AppTextStyles.bodySmall.copyWith(color: Colors.grey[500], fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }

  /// ดึงหมวดหมู่ที่ไม่ซ้ำกันจากรายการอาชีพทั้งหมด
  List<prof.UserCategory> _getUniqueCategories() {
    final categories = <prof.UserCategory>[];
    final seen = <String>{};
    for (var p in _allVolunteerProfessions) {
      if (!seen.contains(p.category.id)) {
        seen.add(p.category.id);
        categories.add(p.category);
      }
    }
    // เรียงตาม displayOrder เพื่อให้ตรงกับหน้าจัดการ (Admin)
    categories.sort((a, b) => a.displayOrder.compareTo(b.displayOrder));
    return categories;
  }

  Future<void> _saveUnblurredProfessions() async {
    if (_user == null) return;
    setState(() => _isSavingUnblurred = true);
    try {
      // บันทึกลงตาราง user_registration_data ซึ่งเป็นตารางแบบ Dynamic Key-Value
      // วิธีนี้จะทำให้ข้อมูลถูกบันทึกสำเร็จแน่นอนทั้งใน Local และ Supabase Cloud โดยไม่ต้องกังวลเรื่องคอลัมน์ขาดหาย
      await Supabase.instance.client.from('user_registration_data').upsert({
        'user_id': _user!.id,
        'field_id': 'unblurred_profession_ids',
        'field_value': json.encode(_selectedUnblurredIds.toList()),
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'user_id,field_id');

      // อัพเดต local session
      AuthService.instance.login(_user!.copyWith(
        unblurredProfessionIds: _selectedUnblurredIds.toList(),
      ));
      debugPrint('ProfilePage: ✅ Saved unblurred professions: $_selectedUnblurredIds');
    } catch (e) {
      debugPrint('ProfilePage: ❌ Error saving unblurred professions: $e');
    } finally {
      if (mounted) {
        setState(() => _isSavingUnblurred = false);
      }
    }
  }

  Future<void> _updateVolunteerSettings({bool? enabled, int? radius}) async {
    if (_user == null) return;
    
    bool newEnabled = enabled ?? _thaiMhungEnabled;
    final newRadius = radius ?? _alertRadius;

    // Guided UX: If enabling, check for background location permission on Android
    if (enabled == true) {
      final locService = LocationTrackingService();
      final isAlwaysGranted = await locService.isBackgroundPermissionGranted();
      
      if (!isAlwaysGranted) {
        // Show our custom guidance dialog first
        final shouldGoToSettings = await BackgroundPermissionDialog.show(context);
        if (!mounted) return;
        if (shouldGoToSettings) {
          await openAppSettings();
          // After returning from settings, we don't force 'true' yet, 
          // let the user toggle again once they grant permission.
          return;
        } else {
          // User cancelled the guidance, don't enable
          setState(() => _thaiMhungEnabled = false);
          return;
        }
      }
    }
    
    setState(() {
      _thaiMhungEnabled = newEnabled;
      _alertRadius = newRadius;
    });

    try {
      await _repository.updateProfile(
        userId: _user!.id,
        coreData: {
          'is_thai_mhung_enabled': newEnabled,
          'alert_radius': newRadius,
        },
        dynamicData: {},
        userType: _user!.userType,
      );
      
      AuthService.instance.login(_user!.copyWith(
        isThaiMhungEnabled: newEnabled,
        alertRadius: newRadius,
      ));

      // Option 3: Start/Stop persistent tracking based on toggle
      final locService = LocationTrackingService();
      if (newEnabled) {
        // Start persistent tracking
        await locService.startTracking(userId: _user!.id);
      } else {
        // Stop tracking
        locService.stopTracking();
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('บันทึกการตั้งค่าจิตอาสาสำเร็จ'),
            duration: Duration(seconds: 1),
            backgroundColor: AppColors.primary,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error updating volunteer settings: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('บันทึกไม่สำเร็จ: $e')),
        );
      }
    }
  }

  void _showImagePickerDropdown() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('ถ่ายรูป (Camera)'),
              onTap: () {
                Navigator.pop(context);
                _processAndUploadAvatar(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('เลือกจากคลังภาพ (Gallery)'),
              onTap: () {
                Navigator.pop(context);
                _processAndUploadAvatar(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _processAndUploadAvatar(ImageSource source) async {
    if (_user == null) return;
    
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: source);
    if (pickedFile == null) return;
    
    setState(() => _isUploadingAvatar = true);
    
    try {
      // 1. บีบอัดไฟล์ (Compress)
      final tempDir = await getTemporaryDirectory();
      final targetPath = '${tempDir.path}/${DateTime.now().millisecondsSinceEpoch}_compressed.jpg';
      
      final compressedFile = await FlutterImageCompress.compressAndGetFile(
        pickedFile.path,
        targetPath,
        quality: 70,       // ลดคุณภาพลงเหลือ 70%
        minWidth: 800,     // จำกัดความกว้างสูงสุด
        minHeight: 800,    // จำกัดความสูงสูงสุด
      );
      
      if (compressedFile == null) throw Exception('บีบอัดภาพไม่สำเร็จ');

      // 2. อัปโหลดลง Storage
      final userId = _user!.id;
      final fileName = 'profiles/$userId/avatar_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final supabase = Supabase.instance.client;
      
      await supabase.storage.from('avatars').upload(fileName, File(compressedFile.path));
      final imageUrl = supabase.storage.from('avatars').getPublicUrl(fileName);

      // 3. บันทึกลงตารางจริง (users table)
      await supabase.from('users').update({
        'profile_image_url': imageUrl,
      }).eq('id', userId);
      
      // อัปเดต State และ Local Session
      setState(() {
        _user = _user!.copyWith(profileImageUrl: imageUrl);
        _tempProfileImage = null;
      });
      AuthService.instance.login(_user!);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('อัปเดตภาพโปรไฟล์สำเร็จ'), backgroundColor: AppColors.success),
        );
      }
    } catch (e) {
      debugPrint('Avatar upload error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('เกิดข้อผิดพลาดในการอัปโหลด: $e'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploadingAvatar = false);
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
        'is_thai_mhung_enabled': _thaiMhungEnabled,
        'alert_radius': _alertRadius,
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
      // (ระบบถูกย้ายไปให้เป็น _processAndUploadAvatar ที่ทำหน้าที่อัปโหลดอัตโนมัติแล้ว)

      await _repository.updateProfile(
        userId: userId,
        coreData: coreData,
        dynamicData: dynamicData,
        userType: _user!.userType,
      );
      
      // Update local session
      AuthService.instance.login(_user!.copyWith(
        firstName: coreData['first_name'],
        lastName: coreData['last_name'],
        isThaiMhungEnabled: _thaiMhungEnabled,
        alertRadius: _alertRadius,
        profileImageUrl: coreData['profile_image_url'],
      ));
      
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
