import 'dart:io';
import 'dart:convert';
import '../../../../features/consultation/presentation/pages/my_consultations_page.dart';
import '../../../../features/consultation/presentation/pages/provider_history_page.dart';
import '../../../../features/consultation/presentation/pages/health_program_request_dashboard.dart'
    show dashboardRouteObserver;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/rendering.dart';
import 'package:thai_buddhist_date/thai_buddhist_date.dart';
import 'package:thai_buddhist_date_pickers/thai_buddhist_date_pickers.dart';
import 'package:intl/intl.dart';
import 'package:sheserved/features/consultation/presentation/pages/manage_quick_replies_page.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../../shared/widgets/widgets.dart';
import '../../../../services/auth_service.dart';
import '../../../../services/service_locator.dart';
import '../../../admin/models/profession.dart' as prof;
import '../../../admin/models/registration_field_config.dart';
import '../../../admin/data/repositories/profession_repository.dart';
import '../../../admin/data/repositories/registration_repository.dart';
import 'package:sheserved/features/home/presentation/widgets/background_permission_dialog.dart';
import 'package:sheserved/services/location_tracking_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sheserved/features/emergency/data/repositories/emergency_health_settings_repository.dart';
import 'package:sheserved/features/emergency/data/repositories/emergency_dead_man_repository.dart';
import '../../data/repositories/profile_repository.dart';
import '../../../auth/data/models/user_model.dart';
import '../../../auth/data/repositories/user_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supa;
import '../../../donation/data/repositories/donation_repository.dart';
import 'package:sheserved/shared/widgets/tlz_bottom_navigation_bar.dart';
import 'package:sheserved/shared/widgets/tlz_drawer.dart';
import 'package:sheserved/features/donation/presentation/widgets/donation_approver_settings_widget.dart';
import 'package:sheserved/features/donation/presentation/widgets/donation_request_management_panel.dart';
import 'package:sheserved/features/donation/presentation/pages/leader_verification_page.dart';

enum ProfileTab {
  profile,
  volunteer,
  donationApprove,
  history,
}

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> with RouteAware {
  late final ProfileRepository _repository;
  late final DonationRepository _donationRepository;
  late final EmergencyDeadManRepository _deadManRepo;
  final Map<String, TextEditingController> _controllers = {};
  final Map<String, dynamic> _dynamicValues = {};
  final GlobalKey<ProviderHistoryPageState> _historyPageKey =
      GlobalKey<ProviderHistoryPageState>();
  final GlobalKey<MyConsultationsPageState> _myConsultationsKey =
      GlobalKey<MyConsultationsPageState>();

  UserModel? _user;
  prof.Profession? _profession;
  List<RegistrationFieldConfig> _fields = [];
  Map<String, String> _dynamicData = {};

  bool _isLoading = true;
  bool _isSaving = false;
  bool _isEditing = false;
  bool _thaiMhungEnabled = true; // ความสมัครใจไทยมุง
  int _alertRadius = 500; // รัศมีการแจ้งเตือน (เมตร)
  int _yieldWayRadius = 1000; // รัศมีการให้ทาง (เมตร)
  File? _tempProfileImage;
  bool _isUploadingAvatar = false;
  ProfileTab _selectedTab = ProfileTab.profile;
  bool _isNavBarVisible = true; // ควบคุมการแสดงผล Navigation Bar ตอนเลื่อนจอ

  // สิทธิ์อนุมัติบริจาค (ดึงจากหมวดหมู่ user_categories.can_approve_donation)
  bool _canApproveDonation = false;
  bool _isYieldWayEnabled = false; // สิทธิการแจ้งเตือนให้ทาง (Yield Way)

  // Emergency Health / ระบบเฝ้าระวังความปลอดภัย settings
  EmergencyHealthSettings? _emergencyHealthSettings;
  bool _isLoadingEmergencyHealthSettings = false;
  bool _isSavingEmergencyHealthSettings = false;
  int _emergencyHealthReleaseDelayMinutes = 5;
  List<String> _emergencyHealthEnabledFields = List<String>.from(
    EmergencyHealthSettings.defaultFields,
  );
  bool _emergencyHealthRequireActiveResponder = true;
  bool _emergencyHealthRequireMedicalProfession = false;
  bool _emergencyHealthRequireVerified = false;
  bool _emergencyHealthEmergencyFallback = false;

  // ระบบเฝ้าระวังความปลอดภัย settings
  EmergencyDeadManCheckin? _deadManCheckin;
  bool _isLoadingDeadManSettings = false;
  bool _isSavingDeadManSettings = false;
  bool _deadManEnabled = false;
  int _deadManCheckInIntervalMinutes = 720;

  // ฟีเจอร์กำหนดอาชีพที่เห็นวิดีโอไม่เบลอ
  List<prof.Profession> _allVolunteerProfessions = [];
  Set<String> _selectedUnblurredIds = {};
  bool _isLoadingProfessions = false;
  bool _isSavingUnblurred = false; // สถานะการบันทึกสิทธิ์ดูวิดีโอ
  String? _selectedCategory; // หมวดหมู่ที่กำลังเลือกอยู่

  // ฟีเจอร์เปลี่ยนอาชีพ (Profession Change)
  List<prof.Profession> _allProfessions = [];
  bool _isLoadingAllProfessions = false;
  bool _isChangingProfession = false;

  // ใบสมัครรอตรวจสอบ (Pending Application)
  prof.RegistrationApplication? _pendingApplication;
  bool _isCancellingApplication = false;

  String? _highlightRequestId; // สำหรับ auto-focus เมื่อเพิ่งสร้างคำร้องขอเสร็จ

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    dashboardRouteObserver.subscribe(this, ModalRoute.of(context)!);
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map<String, dynamic>) {
      // Support both new 'tab' (string) and legacy 'tabIndex' (int)
      if (args['tab'] is String) {
        final tabName = args['tab'] as String;
        final mapped = ProfileTab.values.firstWhere(
          (t) => t.name == tabName,
          orElse: () => ProfileTab.profile,
        );
        if (_selectedTab != mapped) {
          _selectedTab = mapped;
        }
      } else if (args['tabIndex'] != null) {
        // Legacy int index support
        final idx = args['tabIndex'] as int;
        final baseCount = _canApproveDonation ? 3 : 2;
        if (idx == 0) {
          _selectedTab = ProfileTab.profile;
        } else if (idx == 1) {
          _selectedTab = ProfileTab.volunteer;
        } else if (idx == 2 && _canApproveDonation) {
          _selectedTab = ProfileTab.donationApprove;
        } else if (idx == baseCount) {
          _selectedTab = ProfileTab.history;
        }
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
    _deadManRepo = EmergencyDeadManRepository();

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
      _loadAllProfessions();
      _checkCanApproveDonationStatus();
      _loadPendingApplication();
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
          _isYieldWayEnabled = _user?.isYieldWayEnabled ?? false;
          _yieldWayRadius = _user?.yieldWayRadius ?? 1000;

          // โหลดค่า unblurred_profession_ids จาก dynamicData (user_registration_data)
          // เพื่อความเข้ากันได้ 100% กับ Supabase Cloud โดยไม่ต้องแก้ Schema ตารางหลัก
          final unblurredRaw = _dynamicData['unblurred_profession_ids'];
          if (unblurredRaw != null && unblurredRaw.isNotEmpty) {
            try {
              final List<dynamic> decoded = json.decode(unblurredRaw);
              _selectedUnblurredIds = Set<String>.from(
                decoded.map((e) => e.toString()),
              );
            } catch (e) {
              _selectedUnblurredIds = Set<String>.from(
                _user?.unblurredProfessionIds ?? [],
              );
            }
          } else {
            _selectedUnblurredIds = Set<String>.from(
              _user?.unblurredProfessionIds ?? [],
            );
          }

          // Load settings for approver

          _initControllers();
          _isLoading = false;
        });

        // ซิงค์ข้อมูลลง Local Session เสมอเพื่อให้ส่วนอื่นๆ ของแอปอัปเดตตาม
        if (_user != null) {
          AuthService.instance.login(_user!);
          _loadEmergencyHealthSettings();
          _loadDeadManSettings();
        }
      }
    } catch (e) {
      debugPrint('Error loading profile: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('โหลดข้อมูลไม่สำเร็จ: $e')));
      }
    }
  }

  Future<void> _loadPendingApplication() async {
    final userId = AuthService.instance.userId;
    if (userId == null) return;
    try {
      final regRepo = RegistrationRepository(Supabase.instance.client);
      final app = await regRepo.getPendingApplicationForUser(userId);
      if (mounted) {
        setState(() => _pendingApplication = app);
      }
    } catch (e) {
      debugPrint('Error loading pending application: $e');
    }
  }

  Future<void> _cancelPendingApplication() async {
    if (_pendingApplication == null) return;
    final userId = AuthService.instance.userId;
    if (userId == null) return;

    setState(() => _isCancellingApplication = true);
    try {
      final regRepo = RegistrationRepository(Supabase.instance.client);
      await regRepo.cancelApplication(_pendingApplication!.id, userId);
      if (mounted) {
        setState(() {
          _pendingApplication = null;
          _isCancellingApplication = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ยกเลิกใบสมัครเรียบร้อยแล้ว')),
        );
        _loadProfile();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isCancellingApplication = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('ไม่สามารถยกเลิกได้: $e')),
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
        _dynamicValues[field.fieldId] = value.isNotEmpty
            ? DateTime.tryParse(value)
            : null;
      } else if (field.fieldType == FieldType.image) {
        _dynamicValues[field.fieldId] = value; // URL
      } else {
        _controllers[field.fieldId] = TextEditingController(text: value);
      }
    }
  }

  final ScrollController _tabScrollController = ScrollController();

  @override
  void dispose() {
    dashboardRouteObserver.unsubscribe(this);
    _tabScrollController.dispose();
    for (var controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  void didPopNext() {
    debugPrint('[ProfilePage] didPopNext → refreshing history if on history tab');
    if (_selectedTab == ProfileTab.history) {
      final bool isConsumer = !(_user?.isProvider ?? false);
      if (isConsumer) {
        _myConsultationsKey.currentState?.loadHistory();
      } else {
        _historyPageKey.currentState?.loadHistory();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      extendBody:
          true, // สำคัญมาก เพื่อให้ Navigation Bar ลอยทับเนื้อหาได้สวยงาม
      drawer: const TlzDrawer(),
      bottomNavigationBar: TlzBottomNavigationBar(
        isVisible: _isNavBarVisible,
        currentIndex: 4,
        onIndexChanged: (index) {
          if (index == 4) return;
          Navigator.pushReplacementNamed(
            context,
            '/main-app',
            arguments: {'index': index},
          );
        },
        onAddPressed: () {
          Navigator.pushNamed(context, '/emergency-live');
        },
      ),
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
                      Navigator.pushNamed(
                        context,
                        '/login',
                        arguments: '/profile',
                      );
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
              bottom: false, // เพื่อให้เนื้อหามุดลงไปใต้ Nav Bar ได้
              child: NotificationListener<UserScrollNotification>(
                onNotification: (notification) {
                  if (notification.direction == ScrollDirection.reverse) {
                    if (_isNavBarVisible)
                      setState(() => _isNavBarVisible = false);
                  } else if (notification.direction ==
                      ScrollDirection.forward) {
                    if (!_isNavBarVisible)
                      setState(() => _isNavBarVisible = true);
                  }
                  return false;
                },
                child: _buildContent(),
              ),
            ),
    );
  }

  Widget _buildDeadManSwitchSection() {
    final checkin = _deadManCheckin;
    final isEnabled = checkin?.isEnabled ?? _deadManEnabled;
    final lastCheckInText = checkin?.lastCheckInAt != null
        ? DateFormat('dd/MM/yyyy HH:mm').format(checkin!.lastCheckInAt!.toLocal())
        : 'ยังไม่เคยเช็กอิน';
    final lastTriggeredText = checkin?.lastTriggeredAt != null
        ? DateFormat('dd/MM/yyyy HH:mm').format(checkin!.lastTriggeredAt!.toLocal())
        : 'ยังไม่เคยถูกกระตุ้น';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'ระบบเฝ้าระวังความปลอดภัย',
          style: AppTextStyles.heading3.copyWith(color: AppColors.primary),
        ),
        const SizedBox(height: 8),
        Text(
          'ระบบจะตรวจสอบว่าคุณยังปลอดภัยอยู่โดยให้คุณกดยืนยันภายในระยะเวลาที่กำหนด หากคุณไม่กดยืนยันภายในเวลาที่กำหนด ระบบจะถือว่าอาจมีเหตุฉุกเฉินเกิดขึ้น',
          style: AppTextStyles.bodySmall.copyWith(color: Colors.grey[700]),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.watch_later_outlined,
                      color: Colors.red.shade700,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'ระบบเฝ้าระวัง',
                          style: AppTextStyles.bodyMedium.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          _isLoadingDeadManSettings
                              ? 'กำลังโหลดการตั้งค่า...'
                              : isEnabled
                                  ? 'เปิดใช้งานอยู่ • ระบบจะนับเวลาจากการยืนยันความปลอดภัยล่าสุด'
                                  : 'ยังไม่เปิดใช้งาน',
                          style: AppTextStyles.bodySmall.copyWith(
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: isEnabled,
                    onChanged: _isSavingDeadManSettings
                        ? null
                        : (value) => _toggleDeadManEnabled(value),
                    activeThumbColor: Colors.red.shade700,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'ช่วงเวลายืนยันความปลอดภัย',
                style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Slider(
                value: _deadManCheckInIntervalMinutes.toDouble().clamp(60, 1440),
                min: 60,
                max: 1440,
                divisions: 23,
                label: '$_deadManCheckInIntervalMinutes นาที',
                activeColor: Colors.red.shade700,
                onChanged: _isSavingDeadManSettings
                    ? null
                    : (value) {
                        setState(() {
                          _deadManCheckInIntervalMinutes = value.round();
                        });
                      },
                onChangeEnd: _isSavingDeadManSettings
                    ? null
                    : (value) => _saveDeadManSettings(
                          checkInIntervalMinutes: value.round(),
                        ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('1 ชม.', style: AppTextStyles.bodySmall.copyWith(color: Colors.grey)),
                  Text(
                    '$_deadManCheckInIntervalMinutes นาที',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: Colors.red.shade700,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text('24 ชม.', style: AppTextStyles.bodySmall.copyWith(color: Colors.grey)),
                ],
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _buildMiniStatusChip('เช็กอินล่าสุด: $lastCheckInText', Icons.check_circle_outline),
                  _buildMiniStatusChip('กระตุ้นล่าสุด: $lastTriggeredText', Icons.warning_amber_outlined),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isSavingDeadManSettings ? null : _checkInDeadManNow,
                      icon: const Icon(Icons.touch_app),
                      label: const Text('ยืนยันความปลอดภัยตอนนี้'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _isSavingDeadManSettings
                          ? null
                          : () => _saveDeadManSettings(isEnabled: isEnabled),
                      icon: const Icon(Icons.save_outlined),
                      label: const Text('บันทึก'),
                    ),
                  ),
                ],
              ),
              if (_isLoadingDeadManSettings || _isSavingDeadManSettings) ...[
                const SizedBox(height: 16),
                const LinearProgressIndicator(minHeight: 2),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMiniStatusChip(String label, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Colors.grey.shade700),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              style: AppTextStyles.bodySmall,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
            ),
    );
  }

  Widget _buildContent() {
    final bool isConsumer = !(_user?.isProvider ?? false);
    final bool isProvider = !isConsumer;

    return CustomScrollView(
      slivers: [
        SliverAppBar(
          pinned: true,
          floating: false,
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
            preferredSize: const Size.fromHeight(49),
            child: Container(
              width: double.infinity,
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(bottom: BorderSide(color: Color(0xFFEEEEEE))),
              ),
              child: SingleChildScrollView(
                controller: _tabScrollController,
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildTabItem(
                      icon: Icons.person_outline,
                      text: _profession?.name ?? 'โปรไฟล์',
                      isActive: _selectedTab == ProfileTab.profile,
                      activeColor: AppColors.primary,
                      onTap: () => setState(() => _selectedTab = ProfileTab.profile),
                    ),
                    _buildTabItem(
                      icon: Icons.volunteer_activism_outlined,
                      text: 'จิตอาสา',
                      isActive: _selectedTab == ProfileTab.volunteer,
                      activeColor: const Color(0xFFF5A623),
                      onTap: () => setState(() => _selectedTab = ProfileTab.volunteer),
                    ),
                    if (_canApproveDonation)
                      _buildTabItem(
                        icon: Icons.admin_panel_settings_outlined,
                        text: 'อนุมัติบริจาค',
                        isActive: _selectedTab == ProfileTab.donationApprove,
                        activeColor: Colors.teal,
                        onTap: () => setState(() => _selectedTab = ProfileTab.donationApprove),
                      ),
                    if (isConsumer)
                      _buildTabItem(
                        icon: Icons.medical_services_outlined,
                        text: 'ประวัติปรึกษา',
                        isActive: _selectedTab == ProfileTab.history,
                        activeColor: AppColors.primary,
                        onTap: () => setState(() => _selectedTab = ProfileTab.history),
                      ),
                    if (isProvider) ...[
                      _buildTabItem(
                        icon: Icons.edit_note,
                        text: 'จัดการ Quick Replies',
                        isActive: false,
                        activeColor: Colors.purple,
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ManageQuickRepliesPage())),
                      ),
                      _buildTabItem(
                        icon: Icons.history_edu_outlined,
                        text: 'ประวัติให้บริการ',
                        isActive: _selectedTab == ProfileTab.history,
                        activeColor: Colors.green,
                        onTap: () => setState(() => _selectedTab = ProfileTab.history),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
        if (_selectedTab == ProfileTab.history) ...[
          SliverFillRemaining(
            child: isConsumer
                ? MyConsultationsPage(
                    key: _myConsultationsKey,
                    isEmbedded: true,
                  )
                : ProviderHistoryPage(
                    key: _historyPageKey,
                    isEmbedded: true,
                  ),
          ),
        ] else ...[
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                if (_selectedTab == ProfileTab.profile) ...[
                  _buildHeader(),
                  const SizedBox(height: 24),
                  _buildCoreInfo(),
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 16),
                  Text(
                    'ข้อมูลเพิ่มเติม (${_profession?.name ?? ""})',
                    style: AppTextStyles.heading3.copyWith(
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ..._buildDynamicFields(),
                ] else if (_selectedTab == ProfileTab.volunteer) ...[
                  _buildNotificationSettings(),
                ] else if (_selectedTab == ProfileTab.donationApprove && _canApproveDonation) ...[
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
                if (_isEditing && _selectedTab == ProfileTab.profile) ...[
                  const SizedBox(height: 32),
                  TlzButton(
                    text: 'บันทึกข้อมูล',
                    onPressed: _isSaving ? null : _handleSave,
                    isLoading: _isSaving,
                  ),
                ],
                if (_selectedTab == ProfileTab.profile) ...[
                  const SizedBox(height: 40),
                  const Divider(thickness: 1.5, color: Color(0xFFEEEEEE)),
                  const SizedBox(height: 16),
                  DonationRequestManagementPanel(
                    repository: _donationRepository,
                    userId: _user?.id,
                    showCreateButton: true,
                    maxHeight:
                        550, // จำกัดความสูงเพื่อให้ Scroll ได้หากมีมากกว่า 3 รายการ
                    highlightRequestId: _highlightRequestId,
                  ),
                ],
                // เว้นที่ว่างด้านล่างเพื่อให้เนื้อหาไม่ถูก Bottom Navigation Bar บัง
                const SizedBox(height: 120),
              ]),
            ),
          ),
        ],
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
            const SnackBar(
              content: Text('กำลังเปิดหน้าลงทะเบียนองค์กรมูลนิธิ...'),
            ),
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
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: Colors.deepOrange,
                      ),
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
        height: 49,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: isActive ? activeColor : Colors.transparent,
              width: 3,
            ),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: isActive ? activeColor : Colors.grey),
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
                        ? const Center(
                            child: CircularProgressIndicator(
                              color: AppColors.primary,
                            ),
                          )
                        : _user?.profileImageUrl != null
                        ? Image.network(
                            _user!.profileImageUrl!,
                            fit: BoxFit.cover,
                            loadingBuilder: (context, child, loadingProgress) {
                              if (loadingProgress == null) return child;
                              return Center(
                                child: CircularProgressIndicator(
                                  color: AppColors.primary,
                                  value:
                                      loadingProgress.expectedTotalBytes != null
                                      ? loadingProgress.cumulativeBytesLoaded /
                                            loadingProgress.expectedTotalBytes!
                                      : null,
                                ),
                              );
                            },
                            errorBuilder: (c, e, s) => const Icon(
                              Icons.person,
                              size: 60,
                              color: AppColors.primary,
                            ),
                          )
                        : const Icon(
                            Icons.person,
                            size: 60,
                            color: AppColors.primary,
                          ),
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
                      child: const Icon(
                        Icons.camera_alt,
                        color: Colors.white,
                        size: 20,
                      ),
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
              Text(_user?.fullName ?? '', style: AppTextStyles.heading2),
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
                    child: const Icon(
                      Icons.edit,
                      color: Color(0xFFF5A623),
                      size: 18,
                    ),
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
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.textSecondary,
                ),
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
          TlzTextField(label: 'ชื่อ', controller: _controllers['first_name']),
          const SizedBox(height: 12),
          TlzTextField(label: 'นามสกุล', controller: _controllers['last_name']),
        ] else ...[
          _buildFieldRow('ชื่อ', _user?.firstName ?? ''),
          const SizedBox(height: 12),
          _buildFieldRow('นามสกุล', _user?.lastName ?? ''),
        ],
        const SizedBox(height: 12),
        _buildProfessionRow(),
        if (_pendingApplication != null) ...[
          const SizedBox(height: 12),
          _buildPendingApplicationCard(),
        ],
      ],
    );
  }

  Widget _buildProfessionRow() {
    final professionName = _profession?.name ?? 'ยังไม่ได้เลือกอาชีพ';
    final status = _user?.verificationStatus;
    final isVerified = status == VerificationStatus.verified;
    final isPending = status == VerificationStatus.pending;
    final isRejected = status == VerificationStatus.rejected;
    final isCancelled = status == VerificationStatus.cancelled;

    return InkWell(
      onTap: _isChangingProfession ? null : _showProfessionPicker,
      borderRadius: BorderRadius.circular(8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              'อาชีพ',
              style: AppTextStyles.bodySmall.copyWith(color: Colors.grey),
            ),
          ),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    professionName,
                    style: AppTextStyles.bodyMedium,
                  ),
                ),
                if (isVerified)
                  const Icon(Icons.verified, color: AppColors.primary, size: 16)
                else if (isPending)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'รอตรวจสอบ',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: Colors.orange,
                        fontSize: 11,
                      ),
                    ),
                  )
                else if (isRejected)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'ไม่ผ่าน',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: Colors.red,
                        fontSize: 11,
                      ),
                    ),
                  )
                else if (isCancelled)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.grey.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'ยกเลิกแล้ว',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: Colors.grey[700],
                        fontSize: 11,
                      ),
                    ),
                  ),
                const SizedBox(width: 4),
                if (_isChangingProfession)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  Icon(Icons.edit, size: 14, color: Colors.grey[400]),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPendingApplicationCard() {
    final app = _pendingApplication!;
    final isOwnerRequest =
        app.registrationData['is_owner_request'] == 'true' ||
            app.registrationData['is_owner_request'] == true;
    final createdDate = '${app.createdAt.day}/${app.createdAt.month}/${app.createdAt.year + 543}';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.orange.withOpacity(0.3), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.hourglass_top, size: 16, color: Colors.orange[700]),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'ใบสมัครของคุณกำลังรอตรวจสอบ',
                  style: AppTextStyles.bodySmall.copyWith(
                    fontWeight: FontWeight.w600,
                    color: Colors.orange[700],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'อาชีพ: ${app.profession?.name ?? 'ไม่ระบุ'}${isOwnerRequest ? ' (สมัครเป็นเจ้าขององค์กร)' : ''}',
            style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 4),
          Text(
            'สมัครเมื่อ: $createdDate',
            style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: _isCancellingApplication
                  ? null
                  : () {
                      showDialog(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('ยืนยันการยกเลิก'),
                          content: const Text(
                            'คุณแน่ใจหรือไม่ว่าต้องการยกเลิกใบสมัครนี้?',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx),
                              child: const Text('ไม่ยกเลิก'),
                            ),
                            TextButton(
                              onPressed: () {
                                Navigator.pop(ctx);
                                _cancelPendingApplication();
                              },
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.red,
                              ),
                              child: const Text('ยกเลิกใบสมัคร'),
                            ),
                          ],
                        ),
                      );
                    },
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red,
                side: BorderSide(color: Colors.red.withOpacity(0.5)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: _isCancellingApplication
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('ยกเลิกใบสมัคร'),
            ),
          ),
        ],
      ),
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
        value =
            '${date.day} ${_getThaiShortMonth(date.month)} ${date.year + 543}';
      }
    } else if (field.fieldType == FieldType.image) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            field.label,
            style: AppTextStyles.bodySmall.copyWith(color: Colors.grey),
          ),
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
                    style: TextStyle(
                      color: date != null ? Colors.black : Colors.grey,
                    ),
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
                  child: Image.network(
                    currentUrl,
                    height: 100,
                    width: 100,
                    fit: BoxFit.cover,
                  ),
                ),
                Positioned(
                  top: 0,
                  right: 0,
                  child: IconButton(
                    icon: const Icon(Icons.cancel, color: Colors.red),
                    onPressed: () =>
                        setState(() => _dynamicValues[field.fieldId] = null),
                  ),
                ),
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
      keyboardType: field.fieldType == FieldType.phone
          ? TextInputType.phone
          : TextInputType.text,
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
        Expanded(child: Text(value, style: AppTextStyles.bodyMedium)),
      ],
    );
  }

  void _showProfessionPicker() {
    if (_allProfessions.isEmpty && !_isLoadingAllProfessions) {
      _loadAllProfessions();
    }

    // Group professions by category
    final Map<String, List<prof.Profession>> groups = {};
    final Map<String, prof.UserCategory> categories = {};
    for (var p in _allProfessions) {
      if (!groups.containsKey(p.category.id)) {
        groups[p.category.id] = [];
        categories[p.category.id] = p.category;
      }
      groups[p.category.id]!.add(p);
    }
    final sortedCatIds = categories.keys.toList()
      ..sort((a, b) => (categories[a]?.displayOrder ?? 0)
          .compareTo(categories[b]?.displayOrder ?? 0));

    String? expandedCatId = _profession?.category.id;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          height: MediaQuery.of(context).size.height * 0.55,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(32),
              topRight: Radius.circular(32),
            ),
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  children: [
                    Text(
                      'เลือกอาชีพ',
                      style: AppTextStyles.heading5.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    if (_isLoadingAllProfessions)
                      const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: _isLoadingAllProfessions
                    ? const Center(child: CircularProgressIndicator())
                    : Scrollbar(
                        thumbVisibility: true,
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                          itemCount: sortedCatIds.length,
                          itemBuilder: (context, index) {
                            final catId = sortedCatIds[index];
                            final category = categories[catId]!;
                            final proList = groups[catId]!;

                            if (proList.length == 1) {
                              final p = proList.first;
                              final isSelected = _profession?.id == p.id;
                              return _buildProfessionPickerItem(
                                p, isSelected, setModalState,
                              );
                            }

                            final isExpanded = expandedCatId == catId;
                            final hasSelectedInGroup = proList.any(
                              (p) => _profession?.id == p.id,
                            );

                            return Theme(
                              data: Theme.of(context).copyWith(
                                dividerColor: Colors.transparent,
                              ),
                              child: ExpansionTile(
                                key: Key('${catId}_$isExpanded'),
                                initiallyExpanded: isExpanded,
                                onExpansionChanged: (expanding) {
                                  setModalState(() {
                                    expandedCatId = expanding ? catId : null;
                                  });
                                },
                                shape: const Border(),
                                collapsedShape: const Border(),
                                tilePadding: EdgeInsets.zero,
                                childrenPadding: EdgeInsets.zero,
                                leading: Icon(
                                  _getIconForProfession(category.iconName),
                                  color: AppColors.primary,
                                  size: 22,
                                ),
                                title: Text(
                                  category.name,
                                  style: AppTextStyles.bodyMedium.copyWith(
                                    color: hasSelectedInGroup
                                        ? AppColors.primary
                                        : AppColors.textPrimary,
                                  ),
                                ),
                                children: proList.map((p) {
                                  final isSelected = _profession?.id == p.id;
                                  return _buildProfessionPickerItem(
                                    p, isSelected, setModalState,
                                    padding: const EdgeInsets.only(left: 20),
                                  );
                                }).toList(),
                              ),
                            );
                          },
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProfessionPickerItem(
    prof.Profession p,
    bool isSelected,
    StateSetter setModalState, {
    EdgeInsets? padding,
  }) {
    final color = p.colorHex != null
        ? Color(int.parse(p.colorHex!.replaceFirst('#', '0xFF')))
        : AppColors.primary;

    return ListTile(
      onTap: () {
        Navigator.pop(context);
        _onProfessionSelected(p);
      },
      contentPadding: padding ?? EdgeInsets.zero,
      leading: Icon(
        _getIconForProfession(p.iconName),
        color: color,
        size: 22,
      ),
      title: Text(
        p.name,
        style: AppTextStyles.bodyMedium.copyWith(
          color: isSelected ? AppColors.primary : AppColors.textPrimary,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      subtitle: p.requiresVerification
          ? Text(
              'ต้องผ่านการตรวจสอบ',
              style: AppTextStyles.bodySmall.copyWith(
                color: Colors.orange,
                fontSize: 11,
              ),
            )
          : null,
      trailing: isSelected
          ? const Icon(Icons.check_circle, color: AppColors.primary, size: 20)
          : null,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      tileColor: isSelected ? AppColors.primary.withOpacity(0.05) : null,
    );
  }

  IconData _getIconForProfession(String? iconName) {
    switch (iconName) {
      case 'shopping_cart': return Icons.shopping_cart;
      case 'store': return Icons.store;
      case 'local_hospital': return Icons.local_hospital;
      case 'medical_services': return Icons.medical_services;
      case 'delivery_dining': return Icons.delivery_dining;
      case 'engineering': return Icons.engineering;
      case 'gavel': return Icons.gavel;
      case 'person': return Icons.person;
      case 'school': return Icons.school;
      case 'restaurant': return Icons.restaurant;
      case 'spa': return Icons.spa;
      case 'fitness_center': return Icons.fitness_center;
      default: return Icons.work;
    }
  }

  Future<void> _onProfessionSelected(prof.Profession newProfession) async {
    if (newProfession.id == _user?.professionId) return;

    bool isOwnerRequest = false;
    if (newProfession.requiresVerification) {
      // Show confirmation dialog for verification-required professions
      final result = await showDialog<Map<String, dynamic>?>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('เปลี่ยนอาชีพ'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'อาชีพ "${newProfession.name}" ต้องผ่านการตรวจสอบคุณสมบัติก่อนใช้งาน\n\n'
                  'หลังจากส่งคำขอ คุณจะต้องรอการอนุมัติจากแอดมิน ระหว่างนี้คุณอาจไม่สามารถใช้ฟีเจอร์บางอย่างที่ต้องการอาชีพนี้ได้',
                ),
                if (newProfession.category.id == prof.UserCategory.providerId ||
                    newProfession.id == prof.Profession.clinicProfessionId ||
                    newProfession.id == prof.Profession.expertProfessionId) ...[
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Checkbox(
                        value: isOwnerRequest,
                        onChanged: (val) {
                          setDialogState(() {
                            isOwnerRequest = val ?? false;
                          });
                        },
                      ),
                      const Expanded(
                        child: Text(
                          'ต้องการสร้างและจดทะเบียนองค์กรใหม่ (สมัครเป็นผู้ดูแลระบบคนแรก/Owner)',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, null),
                child: const Text('ยกเลิก'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, {'confirmed': true, 'isOwner': isOwnerRequest}),
                child: const Text('ดำเนินการต่อ'),
              ),
            ],
          ),
        ),
      );
      if (result == null || result['confirmed'] != true) return;
      isOwnerRequest = result['isOwner'] ?? false;
    }

    setState(() => _isChangingProfession = true);

    try {
      final supabase = supa.Supabase.instance.client;
      final userRepo = UserRepository(supabase);
      final profRepo = ProfessionRepository(supabase);

      // 0. Pre-check: ตรวจสอบก่อนว่าสมัครได้หรือไม่ (ก่อนเปลี่ยน profession_id)
      // เพื่อป้องกัน limbo state ที่ user เปลี่ยนอาชีพแล้วแต่สมัครไม่ได้
      if (newProfession.requiresVerification) {
        final errorMessage = await profRepo.canCreateApplication(
          userId: _user!.id,
          professionId: newProfession.id,
        );
        if (errorMessage != null) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(errorMessage)),
            );
          }
          return;
        }
      }

      // 1. Update user profession and role
      // หมายเหตุ: ตาราง users ใช้ column `role` (consumer/provider/admin) ไม่ใช่ `user_type`
      final newRole =
          newProfession.category.id == prof.UserCategory.consumerId
              ? 'consumer'
              : 'provider';
      await userRepo.updateUser(_user!.id, {
        'profession_id': newProfession.id,
        'role': newRole,
        'verification_status': newProfession.requiresVerification
            ? VerificationStatus.pending.value
            : VerificationStatus.verified.value,
      });

      // 2. If requires verification, create registration application
      if (newProfession.requiresVerification) {
        await profRepo.createApplication(
          oderId: _user!.id,
          professionId: newProfession.id,
          firstName: _user!.firstName,
          lastName: _user!.lastName,
          username: _user!.username,
          phone: _user!.phone,
          profileImageUrl: _user!.profileImageUrl,
          registrationData: {
            'is_owner_request': isOwnerRequest ? 'true' : 'false',
          },
        );
      }

      // 3. Reload profile
      await _loadProfile();
      _loadPendingApplication();

      if (mounted) {
        final message = newProfession.requiresVerification
            ? 'ส่งคำขอเปลี่ยนอาชีพเรียบร้อย รอการตรวจสอบ'
            : 'เปลี่ยนอาชีพเป็น ${newProfession.name} เรียบร้อยแล้ว';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
      }
    } catch (e) {
      debugPrint('Error changing profession: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('เปลี่ยนอาชีพไม่สำเร็จ: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isChangingProfession = false);
    }
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
                      style: AppTextStyles.bodyMedium.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'รับแจ้งเตือนเมื่อมีเหตุการณ์เกิดขึ้นในรัศมี 500 เมตร',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: Colors.grey,
                      ),
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
          const SizedBox(height: 16),
          _buildRadiusSection(),
        ],
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
                      'แจ้งเตือนช่วยเปิดทาง (Yield Way)',
                      style: AppTextStyles.bodyMedium.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'รับแจ้งเตือนเมื่อมีรถฉุกเฉินกำลังวิ่งมาบนเส้นทางของคุณ',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: _isYieldWayEnabled,
                onChanged: (value) => _updateYieldWayStatus(value),
                activeThumbColor: const Color(0xFF007AFF),
              ),
            ],
          ),
        ),
        if (_isYieldWayEnabled) ...[
          const SizedBox(height: 16),
          _buildYieldWayRadiusSection(),
        ],
        if (_thaiMhungEnabled ||
            (_profession?.isVolunteer ?? false) ||
            _isYieldWayEnabled) ...[
          const SizedBox(height: 24),
          _buildUnblurredProfessionSection(),
        ],
        const SizedBox(height: 24),
        _buildEmergencyHealthSettingsSection(),
        const SizedBox(height: 24),
        _buildDeadManSwitchSection(),
      ],
    );
  }

  Widget _buildRadiusSection() {
    final isProfessional = _profession?.isVolunteer ?? false;
    final title = isProfessional
        ? 'รัศมีพื้นที่รับผิดชอบ'
        : 'พื้นที่ให้ทางแก่เจ้าหน้าที่';
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
                style: AppTextStyles.bodyMedium.copyWith(
                  fontWeight: FontWeight.bold,
                ),
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
            onChangeEnd: (value) =>
                _updateVolunteerSettings(radius: value.round()),
            activeColor: AppColors.primary,
            inactiveColor: Colors.grey[200],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '500 ม.',
                style: AppTextStyles.bodySmall.copyWith(color: Colors.grey),
              ),
              Text(
                '100 กม.',
                style: AppTextStyles.bodySmall.copyWith(color: Colors.grey),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Section แยกสำหรับตั้งรัศมีการให้ทาง
  Widget _buildYieldWayRadiusSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF007AFF).withOpacity(0.3)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF007AFF).withOpacity(0.06),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.airport_shuttle,
                    color: Color(0xFF007AFF),
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'รัศมีรับแจ้งเตือนให้ทาง',
                    style: AppTextStyles.bodyMedium.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF007AFF).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _yieldWayRadius >= 1000
                      ? '${(_yieldWayRadius / 1000).toStringAsFixed(1)} กม.'
                      : '$_yieldWayRadius ม.',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: const Color(0xFF007AFF),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'รัศมีรอบจุดเกิดเหตุ ที่คุณยินดีช่วยเปิดทางให้รถฉุกเฉิน (หากอยู่บนเส้นทางของจิตอาสา)',
            style: AppTextStyles.bodySmall.copyWith(color: Colors.grey),
          ),
          const SizedBox(height: 16),
          Slider(
            value: _yieldWayRadius.toDouble().clamp(500, 20000),
            min: 500,
            max: 20000,
            divisions: 39,
            onChanged: (value) =>
                setState(() => _yieldWayRadius = value.round()),
            onChangeEnd: (value) => _updateYieldWayRadius(value.round()),
            activeColor: const Color(0xFF007AFF),
            inactiveColor: Colors.grey[200],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '500 ม.',
                style: AppTextStyles.bodySmall.copyWith(color: Colors.grey),
              ),
              Text(
                '20 กม.',
                style: AppTextStyles.bodySmall.copyWith(color: Colors.grey),
              ),
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
              category = prof.UserCategory.fromString(
                json['category'] ?? 'consumer',
              );
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
            final catCompare = a.category.displayOrder.compareTo(
              b.category.displayOrder,
            );
            if (catCompare != 0) return catCompare;
            return a.displayOrder.compareTo(b.displayOrder);
          });

          // ตั้งค่าเริ่มต้นเป็นกลุ่มแรกหากยังไม่ได้เลือก
          if (_allVolunteerProfessions.isNotEmpty &&
              _selectedCategory == null) {
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

  /// โหลดรายการอาชีพทั้งหมดสำหรับเลือกเปลี่ยนอาชีพ
  Future<void> _loadAllProfessions() async {
    if (_isLoadingAllProfessions) return;
    setState(() => _isLoadingAllProfessions = true);
    try {
      final repository = ProfessionRepository(supa.Supabase.instance.client);
      final professions = await repository.getAllProfessions();
      if (mounted) {
        setState(() {
          _allProfessions = professions;
          _isLoadingAllProfessions = false;
        });
      }
    } catch (e) {
      debugPrint('ProfilePage: Error loading all professions: $e');
      if (mounted) setState(() => _isLoadingAllProfessions = false);
    }
  }

  Widget _buildEmergencyHealthSettingsSection() {
    final settings = _emergencyHealthSettings;
    final isEnabled = settings?.isEnabled ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'ข้อมูลสุขภาพสำหรับผู้ช่วยเหลือ',
          style: AppTextStyles.heading3.copyWith(color: AppColors.primary),
        ),
        const SizedBox(height: 8),
        Text(
          'ตั้งค่าระบบเฝ้าระวังความปลอดภัยและข้อมูลสุขภาพที่จะเปิดเผยอัตโนมัติเมื่อเกิดเหตุฉุกเฉิน',
          style: AppTextStyles.bodySmall.copyWith(color: Colors.grey[700]),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.health_and_safety_outlined,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Emergency Health Auto-Release',
                          style: AppTextStyles.bodyMedium.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          _isLoadingEmergencyHealthSettings
                              ? 'กำลังโหลดการตั้งค่า...'
                              : isEnabled
                                  ? 'เปิดใช้งานอยู่ • พร้อมปลดล็อกเมื่อครบเงื่อนไข'
                                  : 'ยังไม่เปิดใช้งาน',
                          style: AppTextStyles.bodySmall.copyWith(
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: isEnabled,
                    onChanged: _isSavingEmergencyHealthSettings
                        ? null
                        : (value) => _toggleEmergencyHealthEnabled(value),
                    activeThumbColor: AppColors.primary,
                  ),
                ],
              ),
              if (settings?.consentGivenAt != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.verified_outlined, color: Colors.green[700], size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'ยินยอมแล้วเมื่อ ${DateFormat('dd/MM/yyyy HH:mm').format(settings!.consentGivenAt!.toLocal())}',
                          style: AppTextStyles.bodySmall.copyWith(
                            color: Colors.green[800],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Text(
                'เวลารอปลดล็อกข้อมูล',
                style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Slider(
                value: _emergencyHealthReleaseDelayMinutes.toDouble().clamp(1, 120),
                min: 1,
                max: 120,
                divisions: 119,
                label: '$_emergencyHealthReleaseDelayMinutes นาที',
                activeColor: AppColors.primary,
                onChanged: _isSavingEmergencyHealthSettings
                    ? null
                    : (value) {
                        setState(() {
                          _emergencyHealthReleaseDelayMinutes = value.round();
                        });
                      },
                onChangeEnd: _isSavingEmergencyHealthSettings
                    ? null
                    : (value) => _saveEmergencyHealthSettings(
                          releaseDelayMinutes: value.round(),
                        ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('1 นาที', style: AppTextStyles.bodySmall.copyWith(color: Colors.grey)),
                  Text(
                    '$_emergencyHealthReleaseDelayMinutes นาที',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text('120 นาที', style: AppTextStyles.bodySmall.copyWith(color: Colors.grey)),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'ข้อมูลที่จะแชร์',
                style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _emergencyFieldOptions.map((option) {
                  final key = option['key']!;
                  final label = option['label']!;
                  final selected = _emergencyHealthEnabledFields.contains(key);
                  return FilterChip(
                    label: Text(label),
                    selected: selected,
                    onSelected: _isSavingEmergencyHealthSettings
                        ? null
                        : (value) => _toggleEmergencyField(key, value),
                    selectedColor: AppColors.primary.withOpacity(0.15),
                    checkmarkColor: AppColors.primary,
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              Text(
                'เงื่อนไขการปลดล็อก',
                style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              _buildEmergencyBooleanSetting(
                title: 'ต้องมี responder ที่ active',
                subtitle: 'เปิดไว้เพื่อให้ข้อมูลปลดล็อกเฉพาะเมื่อมีผู้ช่วยเหลือที่ยัง active',
                value: _emergencyHealthRequireActiveResponder,
                onChanged: (value) => _saveEmergencyBooleanSetting(
                  requireActiveResponder: value,
                ),
              ),
              const SizedBox(height: 12),
              _buildEmergencyBooleanSetting(
                title: 'ต้องเป็นสายอาชีพแพทย์/สาธารณสุข',
                subtitle: 'ใช้กรองผู้ช่วยเหลือที่มีสิทธิ์พิเศษด้านการรักษา',
                value: _emergencyHealthRequireMedicalProfession,
                onChanged: (value) => _saveEmergencyBooleanSetting(
                  requireMedicalProfession: value,
                ),
              ),
              const SizedBox(height: 12),
              _buildEmergencyBooleanSetting(
                title: 'ต้องยืนยันตัวตนแล้ว',
                subtitle: 'จำกัดการเข้าถึงเฉพาะผู้ใช้ที่ยืนยันตัวตนแล้ว',
                value: _emergencyHealthRequireVerified,
                onChanged: (value) => _saveEmergencyBooleanSetting(
                  requireVerified: value,
                ),
              ),
              const SizedBox(height: 12),
              _buildEmergencyBooleanSetting(
                title: 'เปิด fallback หากไม่มีคนผ่านเงื่อนไข',
                subtitle: 'ขยายสิทธิ์อัตโนมัติเมื่อไม่มี responder ที่ตรงตามเงื่อนไข',
                value: _emergencyHealthEmergencyFallback,
                onChanged: (value) => _saveEmergencyBooleanSetting(
                  emergencyFallback: value,
                ),
              ),
              if (_isLoadingEmergencyHealthSettings || _isSavingEmergencyHealthSettings) ...[
                const SizedBox(height: 16),
                const LinearProgressIndicator(minHeight: 2),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEmergencyBooleanSetting({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTextStyles.bodySmall.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: AppTextStyles.bodySmall.copyWith(color: Colors.grey),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: _isSavingEmergencyHealthSettings ? null : onChanged,
            activeThumbColor: AppColors.primary,
          ),
        ],
      ),
    );
  }

  Future<void> _toggleEmergencyHealthEnabled(bool enabled) async {
    if (_user == null) return;

    if (enabled && (_emergencyHealthSettings?.consentGivenAt == null)) {
      final consented = await _showEmergencyHealthConsentDialog();
      if (!consented) return;
    }

    setState(() {
      _emergencyHealthSettings = (_emergencyHealthSettings ?? EmergencyHealthSettings.defaults())
          .copyWith(
        isEnabled: enabled,
        consentGivenAt: enabled
            ? (_emergencyHealthSettings?.consentGivenAt ?? DateTime.now())
            : _emergencyHealthSettings?.consentGivenAt,
      );
    });

    await _saveEmergencyHealthSettings(isEnabled: enabled);
  }

  Future<void> _toggleEmergencyField(String key, bool selected) async {
    final updatedFields = List<String>.from(_emergencyHealthEnabledFields);
    if (selected) {
      if (!updatedFields.contains(key)) updatedFields.add(key);
    } else {
      updatedFields.remove(key);
    }

    setState(() => _emergencyHealthEnabledFields = updatedFields);
    await _saveEmergencyHealthSettings(enabledFields: updatedFields);
  }

  Future<void> _saveEmergencyBooleanSetting({
    bool? requireActiveResponder,
    bool? requireMedicalProfession,
    bool? requireVerified,
    bool? emergencyFallback,
  }) async {
    if (requireActiveResponder != null) {
      setState(() => _emergencyHealthRequireActiveResponder = requireActiveResponder);
    }
    if (requireMedicalProfession != null) {
      setState(() => _emergencyHealthRequireMedicalProfession = requireMedicalProfession);
    }
    if (requireVerified != null) {
      setState(() => _emergencyHealthRequireVerified = requireVerified);
    }
    if (emergencyFallback != null) {
      setState(() => _emergencyHealthEmergencyFallback = emergencyFallback);
    }

    await _saveEmergencyHealthSettings(
      requireActiveResponder: requireActiveResponder,
      requireMedicalProfession: requireMedicalProfession,
      requireVerified: requireVerified,
      emergencyFallback: emergencyFallback,
    );
  }

  Future<bool> _showEmergencyHealthConsentDialog() async {
    if (!mounted) return false;
    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('ยินยอมเปิดใช้ข้อมูลสุขภาพ'),
          content: const Text(
            'การเปิดใช้งานนี้จะอนุญาตให้ระบบปลดล็อกข้อมูลสุขภาพอัตโนมัติเมื่อครบเงื่อนไขฉุกเฉิน\n\nคุณยืนยันว่าจะเปิดใช้ฟังก์ชันนี้หรือไม่?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('ยกเลิก'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('ยินยอม'),
            ),
          ],
        );
      },
    );
    return result == true;
  }

  Future<void> _saveEmergencyHealthSettings({
    bool? isEnabled,
    int? releaseDelayMinutes,
    List<String>? enabledFields,
    bool? requireActiveResponder,
    bool? requireMedicalProfession,
    bool? requireVerified,
    bool? emergencyFallback,
  }) async {
    final userId = AuthService.instance.userId;
    if (userId == null) return;

    final current = _emergencyHealthSettings ?? EmergencyHealthSettings.defaults();
    final updated = current.copyWith(
      isEnabled: isEnabled ?? current.isEnabled,
      releaseDelayMinutes: releaseDelayMinutes ?? _emergencyHealthReleaseDelayMinutes,
      enabledFields: enabledFields ?? _emergencyHealthEnabledFields,
      requireActiveResponder:
          requireActiveResponder ?? _emergencyHealthRequireActiveResponder,
      requireMedicalProfession:
          requireMedicalProfession ?? _emergencyHealthRequireMedicalProfession,
      requireVerified: requireVerified ?? _emergencyHealthRequireVerified,
      emergencyFallback: emergencyFallback ?? _emergencyHealthEmergencyFallback,
      consentGivenAt: current.consentGivenAt,
      updatedAt: DateTime.now(),
    );

    if (mounted) {
      setState(() => _isSavingEmergencyHealthSettings = true);
    }

    try {
      await ServiceLocator.instance.emergencyHealthSettingsRepository
          .upsertSettings(userId, updated);
      await ServiceLocator.instance.emergencyHealthSettingsRepository
          .revokeActiveSessionsIfDisabled(userId, updated.isEnabled);

      if (!mounted) return;
      setState(() {
        _emergencyHealthSettings = updated;
        _emergencyHealthReleaseDelayMinutes = updated.releaseDelayMinutes;
        _emergencyHealthEnabledFields = List<String>.from(updated.enabledFields);
        _emergencyHealthRequireActiveResponder = updated.requireActiveResponder;
        _emergencyHealthRequireMedicalProfession = updated.requireMedicalProfession;
        _emergencyHealthRequireVerified = updated.requireVerified;
        _emergencyHealthEmergencyFallback = updated.emergencyFallback;
      });

      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('บันทึกการตั้งค่าข้อมูลสุขภาพสำเร็จ'),
          duration: Duration(seconds: 2),
          backgroundColor: AppColors.primary,
        ),
      );
    } catch (e) {
      debugPrint('Error saving emergency health settings: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('บันทึกการตั้งค่าข้อมูลสุขภาพไม่สำเร็จ: $e')),
        );
      }
      await _loadEmergencyHealthSettings();
    } finally {
      if (mounted) {
        setState(() => _isSavingEmergencyHealthSettings = false);
      }
    }
  }

  Future<void> _loadEmergencyHealthSettings() async {
    final userId = AuthService.instance.userId;
    if (userId == null) return;

    if (mounted) {
      setState(() => _isLoadingEmergencyHealthSettings = true);
    }

    try {
      final settings = await ServiceLocator.instance.emergencyHealthSettingsRepository
              .fetchSettings(userId) ??
          EmergencyHealthSettings.defaults();

      if (!mounted) return;
      setState(() {
        _emergencyHealthSettings = settings;
        _emergencyHealthReleaseDelayMinutes = settings.releaseDelayMinutes;
        _emergencyHealthEnabledFields = List<String>.from(settings.enabledFields);
        _emergencyHealthRequireActiveResponder = settings.requireActiveResponder;
        _emergencyHealthRequireMedicalProfession = settings.requireMedicalProfession;
        _emergencyHealthRequireVerified = settings.requireVerified;
        _emergencyHealthEmergencyFallback = settings.emergencyFallback;
      });
    } catch (e) {
      debugPrint('Error loading emergency health settings: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoadingEmergencyHealthSettings = false);
      }
    }
  }

  List<Map<String, String>> get _emergencyFieldOptions => const [
        {'key': 'blood_type', 'label': 'กรุ๊ปเลือด'},
        {'key': 'allergies', 'label': 'แพ้ยา/อาหาร'},
        {'key': 'emergency_contact', 'label': 'ผู้ติดต่อฉุกเฉิน'},
        {'key': 'chronic_conditions', 'label': 'โรคประจำตัว'},
        {'key': 'surgical_history', 'label': 'ประวัติผ่าตัด'},
        {'key': 'device_metrics', 'label': 'Device Metrics'},
        {'key': 'prescriptions', 'label': 'ยาที่รับอยู่'},
        {'key': 'consultation_history', 'label': 'ประวัติปรึกษา'},
        {'key': 'weight_history', 'label': 'น้ำหนักย้อนหลัง'},
      ];

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
                      style: AppTextStyles.bodyMedium.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'เลือกอาชีพจิตอาสาที่อนุญาตให้เห็นภาพ/วิดีโอไม่ผ่านการเบลอ',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: Colors.grey,
                      ),
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
                        fontWeight: isSelected
                            ? FontWeight.bold
                            : FontWeight.normal,
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
                        chipColor = Color(
                          int.parse(p.colorHex!.replaceFirst('#', '0xFF')),
                        );
                      } catch (_) {}
                    }
                    return FilterChip(
                      label: Text(p.name),
                      selected: isSelected,
                      selectedColor: chipColor.withOpacity(0.2),
                      checkmarkColor: chipColor,
                      labelStyle: AppTextStyles.bodySmall.copyWith(
                        color: isSelected ? chipColor : Colors.grey[700],
                        fontWeight: isSelected
                            ? FontWeight.bold
                            : FontWeight.normal,
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
                  })
                  .toList(),
            ),
            const SizedBox(height: 8),
            Text(
              'หมายเหตุ: อาชีพที่ไม่ได้เลือกจะเห็นเพียงภาพเบลอ (Privacy Mode)',
              style: AppTextStyles.bodySmall.copyWith(
                color: Colors.grey[500],
                fontSize: 11,
              ),
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
      AuthService.instance.login(
        _user!.copyWith(unblurredProfessionIds: _selectedUnblurredIds.toList()),
      );
      debugPrint(
        'ProfilePage: ✅ Saved unblurred professions: $_selectedUnblurredIds',
      );
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
        final shouldGoToSettings = await BackgroundPermissionDialog.show(
          context,
        );
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

      AuthService.instance.login(
        _user!.copyWith(isThaiMhungEnabled: newEnabled, alertRadius: newRadius),
      );

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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('บันทึกไม่สำเร็จ: $e')));
      }
    }
  }

  Future<void> _updateYieldWayStatus(bool enabled) async {
    if (_user == null) return;
    setState(() => _isYieldWayEnabled = enabled);
    try {
      await _repository.updateProfile(
        userId: _user!.id,
        coreData: {'is_yield_way_enabled': enabled},
        dynamicData: {},
        userType: _user!.userType,
      );
      AuthService.instance.login(_user!.copyWith(isYieldWayEnabled: enabled));
    } catch (e) {
      debugPrint('Error updating yield way status: $e');
    }
  }

  Future<void> _updateYieldWayRadius(int radius) async {
    if (_user == null) return;
    setState(() => _yieldWayRadius = radius);
    try {
      await _repository.updateProfile(
        userId: _user!.id,
        coreData: {'yield_way_radius': radius},
        dynamicData: {},
        userType: _user!.userType,
      );
      AuthService.instance.login(_user!.copyWith(yieldWayRadius: radius));
    } catch (e) {
      debugPrint('Error updating yield way radius: $e');
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
      final targetPath =
          '${tempDir.path}/${DateTime.now().millisecondsSinceEpoch}_compressed.jpg';

      final compressedFile = await FlutterImageCompress.compressAndGetFile(
        pickedFile.path,
        targetPath,
        quality: 70, // ลดคุณภาพลงเหลือ 70%
        minWidth: 800, // จำกัดความกว้างสูงสุด
        minHeight: 800, // จำกัดความสูงสูงสุด
      );

      if (compressedFile == null) throw Exception('บีบอัดภาพไม่สำเร็จ');

      // 2. อัปโหลดลง Storage
      final userId = _user!.id;
      final fileName =
          'profiles/$userId/avatar_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final supabase = Supabase.instance.client;

      await supabase.storage
          .from('avatars')
          .upload(fileName, File(compressedFile.path));
      final imageUrl = supabase.storage.from('avatars').getPublicUrl(fileName);

      // 3. บันทึกลงตารางจริง (users table)
      await supabase
          .from('users')
          .update({'profile_image_url': imageUrl})
          .eq('id', userId);

      // อัปเดต State และ Local Session
      setState(() {
        _user = _user!.copyWith(profileImageUrl: imageUrl);
        _tempProfileImage = null;
      });
      AuthService.instance.login(_user!);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('อัปเดตภาพโปรไฟล์สำเร็จ'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      debugPrint('Avatar upload error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('เกิดข้อผิดพลาดในการอัปโหลด: $e'),
            backgroundColor: AppColors.error,
          ),
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
    const months = [
      'ม.ค.',
      'ก.พ.',
      'มี.ค.',
      'เม.ย.',
      'พ.ค.',
      'มิ.ย.',
      'ก.ค.',
      'ส.ค.',
      'ก.ย.',
      'ต.ค.',
      'พ.ย.',
      'ธ.ค.',
    ];
    return months[month - 1];
  }

  Future<void> _handleSave() async {
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
      AuthService.instance.login(
        _user!.copyWith(
          firstName: coreData['first_name'],
          lastName: coreData['last_name'],
          isThaiMhungEnabled: _thaiMhungEnabled,
          alertRadius: _alertRadius,
          profileImageUrl: coreData['profile_image_url'],
        ),
      );

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('บันทึกข้อมูลสำเร็จ')));
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('บันทึกไม่สำเร็จ: $e')));
      }
    }
  }

  // ── ระบบเฝ้าระวังความปลอดภัย helpers ──

  Future<void> _loadDeadManSettings() async {
    final userId = _user?.id ?? AuthService.instance.userId;
    if (userId == null) return;
    setState(() => _isLoadingDeadManSettings = true);
    try {
      final checkin = await _deadManRepo.fetchCheckin(userId);
      if (mounted) {
        setState(() {
          _deadManCheckin = checkin;
          if (checkin != null) {
            _deadManEnabled = checkin.isEnabled;
            _deadManCheckInIntervalMinutes = checkin.checkInIntervalMinutes;
          }
          _isLoadingDeadManSettings = false;
        });
      }
    } catch (e) {
      debugPrint('_loadDeadManSettings error: $e');
      if (mounted) setState(() => _isLoadingDeadManSettings = false);
    }
  }

  void _toggleDeadManEnabled(bool value) {
    setState(() => _deadManEnabled = value);
    _saveDeadManSettings(isEnabled: value);
  }

  Future<void> _saveDeadManSettings({
    int? checkInIntervalMinutes,
    bool? isEnabled,
  }) async {
    final userId = _user?.id ?? AuthService.instance.userId;
    if (userId == null) return;
    setState(() => _isSavingDeadManSettings = true);
    try {
      await _deadManRepo.upsertCheckin(
        userId: userId,
        isEnabled: isEnabled ?? _deadManEnabled,
        intervalMinutes: checkInIntervalMinutes ?? _deadManCheckInIntervalMinutes,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('บันทึกการตั้งค่าระบบเฝ้าระวังความปลอดภัยสำเร็จ'),
            backgroundColor: AppColors.success,
          ),
        );
      }
      await _loadDeadManSettings();
    } catch (e) {
      debugPrint('_saveDeadManSettings error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('บันทึกไม่สำเร็จ: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSavingDeadManSettings = false);
    }
  }

  Future<void> _checkInDeadManNow() async {
    final userId = _user?.id ?? AuthService.instance.userId;
    if (userId == null) return;
    setState(() => _isSavingDeadManSettings = true);
    try {
      await _deadManRepo.updateCheckInTimestamp(userId: userId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('เช็กอินสำเร็จ'),
            backgroundColor: AppColors.success,
          ),
        );
      }
      await _loadDeadManSettings();
    } catch (e) {
      debugPrint('_checkInDeadManNow error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('เช็กอินไม่สำเร็จ: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSavingDeadManSettings = false);
    }
  }
}
