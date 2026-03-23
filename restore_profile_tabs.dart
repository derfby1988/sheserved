import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
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
  // สิทธิ์ผู้นำชุมชน
  bool _isLocalLeader = false;
  bool _isApproverEnabled = true;
  int _approvalRadius = 500;
  bool _isEditing = false;
  bool _thaiMhungEnabled = true; // ความสมัครใจไทยมุง
  int _alertRadius = 500; // รัศมีการแจ้งเตือน (เมตร)
  File? _tempProfileImage;
  int _selectedTabIndex = 0; // 0: Profile, 1: Volunteer, 2: Approve, 3: Requests

  // ฟีเจอร์กำหนดอาชีพที่เห็นวิดีโอไม่เบลอ
  List<prof.Profession> _allVolunteerProfessions = [];
  Set<String> _selectedUnblurredIds = {};
  bool _isLoadingProfessions = false;
  bool _isSavingUnblurred = false; // สถานะการบันทึกสิทธิ์ดูวิดีโอ
  String? _selectedCategory; // หมวดหมู่ที่กำลังเลือกอยู่

  @override
  void initState() {
    super.initState();
    _repository = ProfileRepository(Supabase.instance.client);
    _donationRepository = DonationRepository(Supabase.instance.client);
    
    // Auth re-verify as per login_navigation_guide
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!AuthService.instance.isLoggedIn) {
        Navigator.pushReplacementNamed(context, '/login', arguments: '/profile');
        return;
      }
      _loadProfile();
      _loadVolunteerProfessions();
      _checkLocalLeaderStatus();
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
          _isApproverEnabled = _dynamicData['is_approver_enabled'] == 'true' || _dynamicData['is_approver_enabled'] == null;
          _approvalRadius = int.tryParse(_dynamicData['approval_radius'] ?? '500') ?? 500;

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

  Future<void> _checkLocalLeaderStatus() async {
    final userId = AuthService.instance.userId;
    if (userId == null) return;
    try {
      final repo = DonationRepository(supa.Supabase.instance.client);
      final result = await repo.isLocalLeader(userId);
      if (mounted) setState(() => _isLocalLeader = result);
    } catch (e) {
      debugPrint('ProfilePage: Error checking leader status: $e');
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
                        width: MediaQuery.of(context).size.width / (_isLocalLeader ? 4 : 3),
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
                        width: MediaQuery.of(context).size.width / (_isLocalLeader ? 4 : 3),
                        child: _buildTabItem(
                          icon: Icons.volunteer_activism_outlined,
                          text: 'จิตอาสา',
                          isActive: _selectedTabIndex == 1,
                          activeColor: const Color(0xFFF5A623),
                          onTap: () => setState(() => _selectedTabIndex = 1),
                        ),
                      ),
                    if (_isLocalLeader)
                      SizedBox(
                        width: MediaQuery.of(context).size.width / 4,
                        child: _buildTabItem(
                          icon: Icons.admin_panel_settings_outlined,
                          text: 'อนุมัติบริจาค',
                          isActive: _selectedTabIndex == 2,
                          activeColor: Colors.teal,
                          onTap: () => setState(() => _selectedTabIndex = 2),
                        ),
                      ),
                    SizedBox(
                      width: MediaQuery.of(context).size.width / (_isLocalLeader ? 4 : 3),
                      child: _buildTabItem(
                        icon: Icons.assignment_outlined,
                        text: 'คำร้องขอ',
                        isActive: _selectedTabIndex == 3,
                        activeColor: Colors.purple,
                        onTap: () => setState(() => _selectedTabIndex = 3),
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
              ] else if (_selectedTabIndex == 2 && _isLocalLeader) ...[
                const LeaderVerificationPage(),
              ] else if (_selectedTabIndex == 3) ...[
                _buildApproverSettings(),
                DonationRequestManagementPanel(
                  repository: _donationRepository,
                  userId: _user?.id,
                ),
              ],
              if (_isEditing && _selectedTabIndex == 0) ...[
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
