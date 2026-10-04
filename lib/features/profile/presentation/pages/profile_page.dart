import 'dart:async';
import 'dart:convert';
import '../../../../features/consultation/presentation/pages/my_consultations_page.dart';
import '../../../../features/consultation/presentation/pages/provider_history_page.dart';
import '../../../../features/consultation/presentation/pages/health_program_request_dashboard.dart'
    show dashboardRouteObserver;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../../../core/utils/file_ops.dart';
import 'package:flutter/rendering.dart';
import 'package:thai_buddhist_date/thai_buddhist_date.dart';
import 'package:thai_buddhist_date_pickers/thai_buddhist_date_pickers.dart';
import 'package:intl/intl.dart';
import 'package:sheserved/features/consultation/presentation/pages/manage_quick_replies_page.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../../core/network/authenticated_http_client.dart';
import '../../../../config/app_config.dart';
import '../../../../shared/widgets/widgets.dart';
import '../../../../services/auth_service.dart';
import '../../../../services/service_locator.dart';
import '../../../../services/websocket_service.dart';
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
import '../../../auth/data/models/password_change_result.dart';
import '../widgets/change_password_bottom_sheet.dart';

enum ProfileTab { profile, volunteer, shareHealth, donationApprove, history }

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
  XFile? _tempProfileImage;
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
  StreamSubscription<Map<String, dynamic>>?
  _applicationNotificationSubscription;

  String? _highlightRequestId; // สำหรับ auto-focus เมื่อเพิ่งสร้างคำร้องขอเสร็จ

  // สถานะว่าผู้ใช้ปัจจุบันมี password_hash หรือไม่ (ใช้ disable menu เปลี่ยนรหัสผ่าน)
  bool _hasPassword = false;

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

    // Refresh profession/application state when the admin review result arrives.
    _applicationNotificationSubscription = WebSocketService()
        .applicationNotificationStream
        .listen((event) {
          if (!mounted) return;
          final eventType = event['event_type']?.toString() ?? '';
          if (eventType.startsWith('profession_application.')) {
            _loadProfile();
            _loadPendingApplication();
          }
        });

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
      final userRepo = UserRepository(Supabase.instance.client);
      final hasPassword = await userRepo.hasPassword(userId);

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
          _hasPassword = hasPassword;

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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('ไม่สามารถยกเลิกได้: $e')));
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
    _applicationNotificationSubscription?.cancel();
    dashboardRouteObserver.unsubscribe(this);
    _tabScrollController.dispose();
    for (var controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  void didPopNext() {
    debugPrint(
      '[ProfilePage] didPopNext → refreshing history if on history tab',
    );
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
      backgroundColor: NeumorphicTheme.baseColor,
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
                  const Text(
                    'กรุณาเข้าสู่ระบบเพื่อดูโปรไฟล์ของคุณ',
                    style: TextStyle(color: NeumorphicTheme.textSecondary),
                  ),
                  const SizedBox(height: 20),
                  NeumorphicVerifyButton(
                    text: 'เข้าสู่ระบบ / สมัครสมาชิก',
                    width: 260,
                    icon: const Icon(
                      Icons.login_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                    onPressed: () {
                      Navigator.pushNamed(
                        context,
                        '/login',
                        arguments: '/profile',
                      );
                    },
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
        ? DateFormat(
            'dd/MM/yyyy HH:mm',
          ).format(checkin!.lastCheckInAt!.toLocal())
        : 'ยังไม่เคยเช็กอิน';
    final lastTriggeredText = checkin?.lastTriggeredAt != null
        ? DateFormat(
            'dd/MM/yyyy HH:mm',
          ).format(checkin!.lastTriggeredAt!.toLocal())
        : 'ยังไม่เคยถูกกระตุ้น';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          'ระบบเฝ้าระวังความปลอดภัย',
          icon: Icons.watch_later_outlined,
          accent: Colors.red.shade700,
        ),
        const SizedBox(height: 8),
        Text(
          'ระบบจะตรวจสอบว่าคุณยังปลอดภัยอยู่โดยให้คุณกดยืนยันภายในระยะเวลาที่กำหนด หากคุณไม่กดยืนยันภายในเวลาที่กำหนด ระบบจะถือว่าอาจมีเหตุฉุกเฉินเกิดขึ้น',
          style: AppTextStyles.bodySmall.copyWith(
            color: NeumorphicTheme.textSecondary,
          ),
        ),
        const SizedBox(height: 12),
        _buildNeuCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              NeumorphicSwitchTile(
                leading: _neuIconBadge(
                  Icons.watch_later_outlined,
                  Colors.red.shade700,
                ),
                title: 'ระบบเฝ้าระวัง',
                subtitle: _isLoadingDeadManSettings
                    ? 'กำลังโหลดการตั้งค่า...'
                    : isEnabled
                    ? 'เปิดใช้งานอยู่ • ระบบจะนับเวลาจากการยืนยันความปลอดภัยล่าสุด'
                    : 'ยังไม่เปิดใช้งาน',
                value: isEnabled,
                activeColor: Colors.red.shade700,
                onChanged: _isSavingDeadManSettings
                    ? null
                    : (value) => _toggleDeadManEnabled(value),
              ),
              const SizedBox(height: 16),
              Text(
                'ช่วงเวลายืนยันความปลอดภัย',
                style: AppTextStyles.bodyMedium.copyWith(
                  fontWeight: FontWeight.bold,
                  color: NeumorphicTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              NeumorphicSlider(
                value: _deadManCheckInIntervalMinutes.toDouble().clamp(
                  60,
                  1440,
                ),
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
                  Text(
                    '1 ชม.',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: NeumorphicTheme.textSecondary,
                    ),
                  ),
                  Text(
                    '$_deadManCheckInIntervalMinutes นาที',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: Colors.red.shade700,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    '24 ชม.',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: NeumorphicTheme.textSecondary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _buildMiniStatusChip(
                    'เช็กอินล่าสุด: $lastCheckInText',
                    Icons.check_circle_outline,
                  ),
                  _buildMiniStatusChip(
                    'กระตุ้นล่าสุด: $lastTriggeredText',
                    Icons.warning_amber_outlined,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: NeumorphicPillButton(
                      text: 'ยืนยันความปลอดภัยตอนนี้',
                      icon: Icons.touch_app,
                      color: Colors.red.shade700,
                      height: 46,
                      fontSize: 12.5,
                      depth: 4,
                      blur: 8,
                      onPressed: _isSavingDeadManSettings
                          ? null
                          : _checkInDeadManNow,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: NeumorphicVerifyButton(
                      text: 'บันทึก',
                      height: 46,
                      icon: const Icon(
                        Icons.save_outlined,
                        color: Colors.white,
                        size: 18,
                      ),
                      onPressed: _isSavingDeadManSettings
                          ? null
                          : () => _saveDeadManSettings(isEnabled: isEnabled),
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
    return NeumorphicContainer(
      borderRadius: 12,
      depth: 3,
      blur: 6,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: NeumorphicTheme.textSecondary),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              style: AppTextStyles.bodySmall.copyWith(
                color: NeumorphicTheme.textPrimary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  /// แถบ Top Bar สีเขียว (app chrome เดียวกับทุกหน้า)
  Widget _buildTopBarContent() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: TlzAppTopBar.onPrimary(
        searchHintText: 'ค้นหา...',
        notificationCategory: 'profile',
        leading: const TlzHamburgerMenu(),
        actions: const [],
      ),
    );
  }

  /// แถบแท็บ Neumorphic — ใช้ร่วมกันทั้งใน SliverAppBar และ layout แบบคงที่
  Widget _buildTabStrip() {
    final bool isConsumer = !(_user?.isProvider ?? false);
    final bool isProvider = !isConsumer;

    return Container(
      width: double.infinity,
      color: NeumorphicTheme.baseColor,
      child: SingleChildScrollView(
        controller: _tabScrollController,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 8,
        ),
        child: Row(
          children: [
                    _buildTabItem(
                      icon: Icons.person_outline,
                      text: _profession?.name ?? 'โปรไฟล์',
                      isActive: _selectedTab == ProfileTab.profile,
                      activeColor: AppColors.primary,
                      onTap: () =>
                          setState(() => _selectedTab = ProfileTab.profile),
                    ),
                    _buildTabItem(
                      icon: Icons.volunteer_activism_outlined,
                      text: 'จิตอาสา',
                      isActive: _selectedTab == ProfileTab.volunteer,
                      activeColor: const Color(0xFFF5A623),
                      onTap: () =>
                          setState(() => _selectedTab = ProfileTab.volunteer),
                    ),
                    _buildTabItem(
                      icon: Icons.health_and_safety_outlined,
                      text: 'แชร์สุขภาพ',
                      isActive: _selectedTab == ProfileTab.shareHealth,
                      activeColor: const Color(0xFFE91E63),
                      onTap: () =>
                          setState(() => _selectedTab = ProfileTab.shareHealth),
                    ),
                    if (_canApproveDonation)
                      _buildTabItem(
                        icon: Icons.admin_panel_settings_outlined,
                        text: 'อนุมัติบริจาค',
                        isActive: _selectedTab == ProfileTab.donationApprove,
                        activeColor: Colors.teal,
                        onTap: () => setState(
                          () => _selectedTab = ProfileTab.donationApprove,
                        ),
                      ),
                    if (isConsumer)
                      _buildTabItem(
                        icon: Icons.medical_services_outlined,
                        text: 'ประวัติปรึกษา',
                        isActive: _selectedTab == ProfileTab.history,
                        activeColor: AppColors.primary,
                        onTap: () =>
                            setState(() => _selectedTab = ProfileTab.history),
                      ),
                    if (isProvider) ...[
                      _buildTabItem(
                        icon: Icons.edit_note,
                        text: 'จัดการ Quick Replies',
                        isActive: false,
                        activeColor: Colors.purple,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ManageQuickRepliesPage(),
                          ),
                        ),
                      ),
                      _buildTabItem(
                        icon: Icons.history_edu_outlined,
                        text: 'ประวัติให้บริการ',
                        isActive: _selectedTab == ProfileTab.history,
                        activeColor: Colors.green,
                        onTap: () =>
                            setState(() => _selectedTab = ProfileTab.history),
                      ),
                    ],
                  ],
                ),
              ),
            );
  }

  /// ปุ่มย้อนกลับแบบวงกลมนูน — ใช้ร่วมกันทุก tab
  Widget _buildBackButtonRow() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
        child: NeumorphicIconButton(
          icon: Icons.arrow_back,
          tooltip: 'ย้อนกลับ',
          color: NeumorphicTheme.primaryBlue,
          onPressed: () {
            final navigator = Navigator.of(context);
            if (navigator.canPop()) {
              navigator.pop();
            } else {
              navigator.pushReplacementNamed('/home');
            }
          },
        ),
      ),
    );
  }

  Widget _buildContent() {
    final bool isConsumer = !(_user?.isProvider ?? false);
    final bool isProvider = !isConsumer;

    // แท็บประวัติฝังหน้าที่เลื่อนเองอยู่แล้ว — ใช้ layout คงที่
    // เพื่อไม่ให้การ์ดใบบนเลื่อนลอดใต้ tab strip ที่ปักหมุดอยู่
    if (_selectedTab == ProfileTab.history) {
      return Column(
        children: [
          Container(
            color: AppColors.primary,
            padding: EdgeInsets.only(
              top: MediaQuery.of(context).padding.top,
            ),
            child: SizedBox(height: 65, child: _buildTopBarContent()),
          ),
          _buildTabStrip(),
          _buildBackButtonRow(),
          const SizedBox(height: 8),
          Expanded(
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
        ],
      );
    }

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
          title: _buildTopBarContent(),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(58),
            child: _buildTabStrip(),
          ),
        ),
        SliverToBoxAdapter(child: _buildBackButtonRow()),
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                if (_selectedTab == ProfileTab.profile) ...[
                  _buildHeader(),
                  const SizedBox(height: 20),
                  _buildCoreInfo(),
                  const SizedBox(height: 20),
                  _buildSectionHeader(
                    'ความปลอดภัยของบัญชี',
                    icon: Icons.shield_outlined,
                  ),
                  const SizedBox(height: 12),
                  _buildChangePasswordTile(),
                  const SizedBox(height: 20),
                  _buildSectionHeader(
                    'ข้อมูลเพิ่มเติม (${_profession?.name ?? ""})',
                    icon: Icons.badge_outlined,
                  ),
                  const SizedBox(height: 12),
                  ..._buildDynamicFields(),
                ] else if (_selectedTab == ProfileTab.volunteer) ...[
                  _buildNotificationSettings(),
                ] else if (_selectedTab == ProfileTab.shareHealth) ...[
                  _buildShareHealthSettings(),
                ] else if (_selectedTab == ProfileTab.donationApprove &&
                    _canApproveDonation) ...[
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
                  const SizedBox(height: 28),
                  NeumorphicVerifyButton(
                    text: 'บันทึกข้อมูล',
                    onPressed: _isSaving ? null : _handleSave,
                    isLoading: _isSaving,
                    icon: const Icon(
                      Icons.save_outlined,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ],
                if (_selectedTab == ProfileTab.profile) ...[
                  const SizedBox(height: 32),
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
    );
  }

  Widget _buildBeneficiaryRegistrationEntry() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          // TODO: สร้างและนำทางไปยัง BeneficiaryRegistrationPage
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('กำลังเปิดหน้าลงทะเบียนองค์กรมูลนิธิ...'),
            ),
          );
        },
        borderRadius: BorderRadius.circular(20),
        child: _buildNeuCard(
          color: Color.alphaBlend(
            Colors.orange.withValues(alpha: 0.10),
            NeumorphicTheme.baseColor,
          ),
          child: Row(
            children: [
              NeumorphicContainer(
                width: 44,
                height: 44,
                shape: BoxShape.circle,
                depth: 3,
                blur: 6,
                color: Colors.orange,
                child: const Icon(
                  Icons.account_balance,
                  color: Colors.white,
                  size: 22,
                ),
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

  /// แผงการ์ดนูน Neumorphic มาตรฐานของหน้าโปรไฟล์
  Widget _buildNeuCard({
    required Widget child,
    EdgeInsetsGeometry? padding,
    Color? color,
    double borderRadius = 20,
    double depth = 6,
    double blur = 12,
  }) {
    return NeumorphicContainer(
      borderRadius: borderRadius,
      depth: depth,
      blur: blur,
      color: color ?? NeumorphicTheme.baseColor,
      padding: padding ?? const EdgeInsets.all(16),
      child: child,
    );
  }

  /// หัวข้อ section พร้อม badge ไอคอนวงกลมนูน — ใช้ร่วมกันทุก tab
  Widget _buildSectionHeader(
    String title, {
    IconData icon = Icons.tune_rounded,
    Color accent = NeumorphicTheme.primaryBlue,
  }) {
    return Row(
      children: [
        NeumorphicContainer(
          width: 36,
          height: 36,
          shape: BoxShape.circle,
          depth: 3,
          blur: 6,
          child: Icon(icon, size: 18, color: accent),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            title,
            style: AppTextStyles.heading3.copyWith(
              color: NeumorphicTheme.textPrimary,
            ),
          ),
        ),
      ],
    );
  }

  /// label เหนือช่องกรอก Neumorphic — โทนเดียวกับหน้า login/register
  Widget _buildFieldLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: NeumorphicTheme.textSecondary,
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
    const padding = EdgeInsets.symmetric(horizontal: 14, vertical: 9);
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          icon,
          size: 16,
          color: isActive ? activeColor : NeumorphicTheme.textSecondary,
        ),
        const SizedBox(width: 6),
        Text(
          text,
          style: AppTextStyles.bodySmall.copyWith(
            color: isActive ? activeColor : NeumorphicTheme.textSecondary,
            fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
          ),
        ),
      ],
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: isActive
              ? NeumorphicInsetBox(
                  height: null,
                  borderRadius: 16,
                  padding: padding,
                  child: content,
                )
              : NeumorphicContainer(
                  borderRadius: 16,
                  depth: 4,
                  blur: 8,
                  padding: padding,
                  child: content,
                ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return _buildNeuCard(
      borderRadius: 28,
      depth: 10,
      blur: 20,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Column(
        children: [
          Stack(
            children: [
              GestureDetector(
                onTap: _isUploadingAvatar ? null : _showImagePickerDropdown,
                child: NeumorphicContainer(
                  width: 124,
                  height: 124,
                  shape: BoxShape.circle,
                  depth: 6,
                  blur: 12,
                  padding: const EdgeInsets.all(5),
                  child: ClipOval(
                    child: Container(
                      color: NeumorphicTheme.primaryBlue.withValues(
                        alpha: 0.08,
                      ),
                      child: _isUploadingAvatar
                          ? const Center(
                              child: CircularProgressIndicator(
                                color: NeumorphicTheme.primaryBlue,
                              ),
                            )
                          : _user?.profileImageUrl != null
                          ? Image.network(
                              _user!.profileImageUrl!,
                              fit: BoxFit.cover,
                              loadingBuilder:
                                  (context, child, loadingProgress) {
                                    if (loadingProgress == null) return child;
                                    return Center(
                                      child: CircularProgressIndicator(
                                        color: NeumorphicTheme.primaryBlue,
                                        value:
                                            loadingProgress
                                                    .expectedTotalBytes !=
                                                null
                                            ? loadingProgress
                                                      .cumulativeBytesLoaded /
                                                  loadingProgress
                                                      .expectedTotalBytes!
                                            : null,
                                      ),
                                    );
                                  },
                              errorBuilder: (c, e, s) => const Center(
                                child: Icon(
                                  Icons.person,
                                  size: 56,
                                  color: NeumorphicTheme.primaryBlue,
                                ),
                              ),
                            )
                          : const Center(
                              child: Icon(
                                Icons.person,
                                size: 56,
                                color: NeumorphicTheme.primaryBlue,
                              ),
                            ),
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
                    child: NeumorphicContainer(
                      width: 36,
                      height: 36,
                      shape: BoxShape.circle,
                      depth: 3,
                      blur: 6,
                      child: const Icon(
                        Icons.camera_alt,
                        color: NeumorphicTheme.primaryBlue,
                        size: 17,
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
              Flexible(
                child: Text(
                  _user?.fullName ?? '',
                  style: AppTextStyles.heading2.copyWith(
                    color: NeumorphicTheme.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              if (!_isEditing)
                NeumorphicIconButton(
                  icon: Icons.edit,
                  color: const Color(0xFFF5A623),
                  size: 32,
                  iconSize: 16,
                  tooltip: 'แก้ไขโปรไฟล์',
                  onPressed: () => setState(() => _isEditing = true),
                )
              else
                NeumorphicIconButton(
                  icon: Icons.close,
                  color: Colors.red,
                  size: 32,
                  iconSize: 16,
                  tooltip: 'ยกเลิกการแก้ไข',
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
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  _profession?.category.name ??
                      _user?.userType.displayName ??
                      '',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: NeumorphicTheme.textSecondary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (_user?.verificationStatus ==
                  VerificationStatus.verified) ...[
                const SizedBox(width: 6),
                const Icon(
                  Icons.verified,
                  color: NeumorphicTheme.primaryBlue,
                  size: 16,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCoreInfo() {
    return _buildNeuCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildFieldRow(
            'ชื่อผู้ใช้',
            _user?.username ?? '',
            isEditable: false,
          ),
          const SizedBox(height: 12),
          if (_isEditing) ...[
            _buildFieldLabel('ชื่อ'),
            const SizedBox(height: 8),
            NeumorphicInputField(
              controller: _controllers['first_name'],
              hintText: 'กรอกชื่อ',
              prefixIcon: Icons.person_outline_rounded,
            ),
            const SizedBox(height: 16),
            _buildFieldLabel('นามสกุล'),
            const SizedBox(height: 8),
            NeumorphicInputField(
              controller: _controllers['last_name'],
              hintText: 'กรอกนามสกุล',
              prefixIcon: Icons.person_outline_rounded,
            ),
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
      ),
    );
  }

  Widget _buildProfessionRow() {
    final professionName =
        (_user?.isAdmin == true && _profession?.name == 'ผู้ใช้งานทั่วไป')
        ? 'Admin ของ Sheserved'
        : (_profession?.name ?? 'ยังไม่ได้เลือกอาชีพ');
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
              style: AppTextStyles.bodySmall.copyWith(
                color: NeumorphicTheme.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    professionName,
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: NeumorphicTheme.textPrimary,
                    ),
                  ),
                ),
                if (isVerified)
                  const Icon(
                    Icons.verified,
                    color: NeumorphicTheme.primaryBlue,
                    size: 16,
                  )
                else if (isPending)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
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
                  const Icon(
                    Icons.edit,
                    size: 14,
                    color: NeumorphicTheme.textSecondary,
                  ),
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
    final previousProfessionName = app
        .registrationData['previous_profession_name']
        ?.toString()
        .trim();
    final requestedProfessionName = app.profession?.name ?? 'ไม่ระบุ';
    final createdDate =
        '${app.createdAt.day}/${app.createdAt.month}/${app.createdAt.year + 543}';

    return _buildNeuCard(
      borderRadius: 14,
      depth: 4,
      blur: 8,
      color: Color.alphaBlend(
        Colors.orange.withValues(alpha: 0.10),
        NeumorphicTheme.baseColor,
      ),
      padding: const EdgeInsets.all(12),
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
            previousProfessionName != null && previousProfessionName.isNotEmpty
                ? 'เดิมอาชีพ $previousProfessionName กำลังขออนุมัติเพื่อเปลี่ยนเป็น $requestedProfessionName'
                : 'อาชีพ: $requestedProfessionName${isOwnerRequest ? ' (สมัครเป็นเจ้าขององค์กร)' : ''}',
            style: AppTextStyles.bodySmall.copyWith(
              color: NeumorphicTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'สมัครเมื่อ: $createdDate',
            style: AppTextStyles.bodySmall.copyWith(
              color: NeumorphicTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: _isCancellingApplication
                ? const Center(
                    child: SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : NeumorphicPillButton(
                    text: 'ยกเลิกใบสมัคร',
                    icon: Icons.cancel_outlined,
                    color: Colors.red.shade600,
                    height: 42,
                    depth: 4,
                    blur: 8,
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          backgroundColor: NeumorphicTheme.baseColor,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(24),
                          ),
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
                  ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildDynamicFields() {
    if (_fields.isEmpty) return const [];

    if (_isEditing) {
      return _fields
          .map(
            (field) => Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: _buildEditableDynamicField(field),
            ),
          )
          .toList();
    }

    return [
      _buildNeuCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Column(
          children: [
            for (var i = 0; i < _fields.length; i++) ...[
              if (i > 0) const SizedBox(height: 12),
              _buildReadonlyDynamicField(_fields[i]),
            ],
          ],
        ),
      ),
    ];
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
            style: AppTextStyles.bodySmall.copyWith(
              color: NeumorphicTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          if (value.isNotEmpty)
            NeumorphicContainer(
              borderRadius: 12,
              depth: 4,
              blur: 8,
              padding: const EdgeInsets.all(4),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(9),
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
          _buildFieldLabel(field.label),
          const SizedBox(height: 8),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => _selectDate(field.fieldId),
              borderRadius: BorderRadius.circular(16),
              child: NeumorphicInsetBox(
                height: 52,
                borderRadius: 16,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      date != null
                          ? '${date.day} ${_getThaiShortMonth(date.month)} ${date.year + 543}'
                          : field.hint ?? 'เลือกวันที่',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: date != null
                            ? FontWeight.w600
                            : FontWeight.w400,
                        color: date != null
                            ? NeumorphicTheme.textPrimary
                            : NeumorphicTheme.textSecondary.withValues(
                                alpha: 0.65,
                              ),
                      ),
                    ),
                    const Icon(
                      Icons.calendar_today,
                      size: 18,
                      color: NeumorphicTheme.textSecondary,
                    ),
                  ],
                ),
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
          _buildFieldLabel(field.label),
          const SizedBox(height: 8),
          if (currentUrl != null && currentUrl.isNotEmpty)
            Stack(
              children: [
                NeumorphicContainer(
                  borderRadius: 12,
                  depth: 4,
                  blur: 8,
                  padding: const EdgeInsets.all(4),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(9),
                    child: Image.network(
                      currentUrl,
                      height: 100,
                      width: 100,
                      fit: BoxFit.cover,
                    ),
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
            Text(
              'อัพโหลดรูปภาพ (เร็วๆ นี้)',
              style: AppTextStyles.bodySmall.copyWith(
                color: NeumorphicTheme.textSecondary,
              ),
            ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildFieldLabel(field.label),
        const SizedBox(height: 8),
        NeumorphicInputField(
          controller: _controllers[field.fieldId],
          hintText: field.hint ?? 'กรอก${field.label}',
          keyboardType: field.fieldType == FieldType.phone
              ? TextInputType.phone
              : TextInputType.text,
          maxLines: field.fieldType == FieldType.multilineText ? 3 : 1,
        ),
      ],
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
            style: AppTextStyles.bodySmall.copyWith(
              color: NeumorphicTheme.textSecondary,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: AppTextStyles.bodyMedium.copyWith(
              color: NeumorphicTheme.textPrimary,
            ),
          ),
        ),
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
      ..sort(
        (a, b) => (categories[a]?.displayOrder ?? 0).compareTo(
          categories[b]?.displayOrder ?? 0,
        ),
      );

    String? expandedCatId = _profession?.category.id;

    final ScrollController scrollController = ScrollController();
    showModalBottomSheet(
      context: context,
      backgroundColor: NeumorphicTheme.baseColor,
      clipBehavior: Clip.antiAlias,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setModalState) => SizedBox(
          height: MediaQuery.of(context).size.height * 0.55,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              children: [
                const Center(child: NeumorphicSheetDragHandle()),
                const SizedBox(height: 12),
                Row(
                  children: [
                    NeumorphicContainer(
                      width: 36,
                      height: 36,
                      shape: BoxShape.circle,
                      depth: 3,
                      blur: 6,
                      child: const Icon(
                        Icons.work_outline_rounded,
                        size: 18,
                        color: NeumorphicTheme.primaryBlue,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'เลือกอาชีพ',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.heading5.copyWith(
                          fontWeight: FontWeight.bold,
                          color: NeumorphicTheme.textPrimary,
                        ),
                      ),
                    ),
                    if (_isLoadingAllProfessions)
                      const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else
                      NeumorphicSheetCloseButton(
                        onPressed: () => Navigator.pop(sheetContext),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: _isLoadingAllProfessions
                      ? const Center(child: CircularProgressIndicator())
                      : NeumorphicContainer(
                          borderRadius: 20,
                          depth: 4,
                          blur: 8,
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Scrollbar(
                            controller: scrollController,
                            thumbVisibility: true,
                            child: ListView.builder(
                              controller: scrollController,
                              padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                              itemCount: sortedCatIds.length,
                          itemBuilder: (context, index) {
                            final catId = sortedCatIds[index];
                            final category = categories[catId]!;
                            final proList = groups[catId]!;

                            if (proList.length == 1) {
                              final p = proList.first;
                              final isSelected = _profession?.id == p.id;
                              return _buildProfessionPickerItem(
                                p,
                                isSelected,
                                setModalState,
                              );
                            }

                            final isExpanded = expandedCatId == catId;
                            final hasSelectedInGroup = proList.any(
                              (p) => _profession?.id == p.id,
                            );

                            return Theme(
                              data: Theme.of(
                                context,
                              ).copyWith(dividerColor: Colors.transparent),
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
                                  color: NeumorphicTheme.primaryBlue,
                                  size: 22,
                                ),
                                title: Text(
                                  category.name,
                                  style: AppTextStyles.bodyMedium.copyWith(
                                    color: hasSelectedInGroup
                                        ? NeumorphicTheme.primaryBlue
                                        : NeumorphicTheme.textPrimary,
                                  ),
                                ),
                                children: proList.map((p) {
                                  final isSelected = _profession?.id == p.id;
                                  return _buildProfessionPickerItem(
                                    p,
                                    isSelected,
                                    setModalState,
                                    padding: const EdgeInsets.only(left: 20),
                                  );
                                }).toList(),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
              ),
            ],
          ),
        ),
      ),
    ),
    ).whenComplete(() => scrollController.dispose());
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
      leading: Icon(_getIconForProfession(p.iconName), color: color, size: 22),
      title: Text(
        p.name,
        style: AppTextStyles.bodyMedium.copyWith(
          color: isSelected
              ? NeumorphicTheme.primaryBlue
              : NeumorphicTheme.textPrimary,
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
          ? const Icon(
              Icons.check_circle,
              color: NeumorphicTheme.primaryBlue,
              size: 20,
            )
          : null,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      tileColor: isSelected
          ? NeumorphicTheme.primaryBlue.withValues(alpha: 0.08)
          : null,
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
      case 'person':
        return Icons.person;
      case 'school':
        return Icons.school;
      case 'restaurant':
        return Icons.restaurant;
      case 'spa':
        return Icons.spa;
      case 'fitness_center':
        return Icons.fitness_center;
      default:
        return Icons.work;
    }
  }

  Future<void> _onProfessionSelected(prof.Profession newProfession) async {
    if (newProfession.id == _user?.professionId) return;

    final previousProfessionId = _profession?.id ?? _user?.professionId;
    final previousProfessionName = _profession?.name;
    bool isOwnerRequest = false;
    if (newProfession.requiresVerification) {
      // Show confirmation dialog for verification-required professions
      final result = await showDialog<Map<String, dynamic>?>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            backgroundColor: NeumorphicTheme.baseColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
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
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
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
                onPressed: () => Navigator.pop(ctx, {
                  'confirmed': true,
                  'isOwner': isOwnerRequest,
                }),
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
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(errorMessage)));
          }
          return;
        }
      }

      // 1. Gateway path: update user + create application + notify admins atomically.
      // Legacy mode keeps the existing direct Supabase path during compatibility.
      if (AppConfig.useBackendAuth && newProfession.requiresVerification) {
        AuthenticatedHttpClient.instance.configure(
          baseUrl: AppConfig.backendApiUrl,
        );
        await AuthenticatedHttpClient.instance.submitProfessionChange(
          professionId: newProfession.id,
          firstName: _user!.firstName,
          lastName: _user!.lastName,
          username: _user!.username,
          phone: _user!.phone,
          profileImageUrl: _user!.profileImageUrl,
          registrationData: {
            'is_owner_request': isOwnerRequest ? 'true' : 'false',
            'previous_profession_id': previousProfessionId,
            'previous_profession_name': previousProfessionName,
          },
        );
      } else if (newProfession.requiresVerification) {
        // RPC สร้างใบสมัคร + snapshot อาชีพเดิมฝั่ง server +
        // ย้าย user ไปอาชีพใหม่ (pending) ใน transaction เดียว
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
            'previous_profession_name': previousProfessionName,
          },
        );
      } else {
        // หมายเหตุ: ตาราง users ใช้ column `role` (consumer/provider/admin) ไม่ใช่ `user_type`
        final newRole =
            newProfession.category.id == prof.UserCategory.consumerId
            ? 'consumer'
            : 'provider';
        await userRepo.updateUser(_user!.id, {
          'profession_id': newProfession.id,
          'role': newRole,
          'verification_status': VerificationStatus.verified.value,
        });
      }

      // 3. Reload profile
      await _loadProfile();
      _loadPendingApplication();

      if (mounted) {
        final message = newProfession.requiresVerification
            ? 'ส่งคำขอเปลี่ยนอาชีพเรียบร้อย รอการตรวจสอบ'
            : 'เปลี่ยนอาชีพเป็น ${newProfession.name} เรียบร้อยแล้ว';
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
    } catch (e) {
      debugPrint('Error changing profession: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('เปลี่ยนอาชีพไม่สำเร็จ: $e')));
      }
    } finally {
      if (mounted) setState(() => _isChangingProfession = false);
    }
  }

  Widget _buildNotificationSettings() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          'การตั้งค่าการแจ้งเตือน',
          icon: Icons.notifications_active_outlined,
        ),
        const SizedBox(height: 12),
        _buildNeuCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: NeumorphicSwitchTile(
            title: 'แจ้งเหตุฉุกเฉินใกล้ตัว (ไทยมุง)',
            subtitle: 'รับแจ้งเตือนเมื่อมีเหตุการณ์เกิดขึ้นในรัศมี 500 เมตร',
            value: _thaiMhungEnabled,
            activeColor: AppColors.primaryDark,
            onChanged: (value) => _updateVolunteerSettings(enabled: value),
            leading: _neuIconBadge(
              Icons.crisis_alert_outlined,
              AppColors.primaryDark,
            ),
          ),
        ),
        if (_thaiMhungEnabled || (_profession?.isVolunteer ?? false)) ...[
          const SizedBox(height: 16),
          _buildRadiusSection(),
        ],
        const SizedBox(height: 16),
        _buildNeuCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: NeumorphicSwitchTile(
            title: 'แจ้งเตือนช่วยเปิดทาง (Yield Way)',
            subtitle: 'รับแจ้งเตือนเมื่อมีรถฉุกเฉินกำลังวิ่งมาบนเส้นทางของคุณ',
            value: _isYieldWayEnabled,
            activeColor: const Color(0xFF007AFF),
            onChanged: (value) => _updateYieldWayStatus(value),
            leading: _neuIconBadge(
              Icons.airport_shuttle,
              const Color(0xFF007AFF),
            ),
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
      ],
    );
  }

  /// badge ไอคอนนูนสี่เหลี่ยมมน — ใช้เป็น leading ของ switch/การ์ดย่อย
  Widget _neuIconBadge(IconData icon, Color color, {double size = 42}) {
    return NeumorphicContainer(
      width: size,
      height: size,
      borderRadius: 13,
      depth: 3,
      blur: 6,
      child: Icon(icon, size: size * 0.5, color: color),
    );
  }

  /// ป้ายค่าจม (Inset) แสดงค่าปัจจุบัน เช่น รัศมี/นาที
  Widget _buildInsetValueBadge(String text, Color color) {
    return NeumorphicInsetBox(
      height: null,
      borderRadius: 10,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      child: Text(
        text,
        style: AppTextStyles.bodySmall.copyWith(
          color: color,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildShareHealthSettings() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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

    return _buildNeuCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: AppTextStyles.bodyMedium.copyWith(
                    fontWeight: FontWeight.bold,
                    color: NeumorphicTheme.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _buildInsetValueBadge(
                _alertRadius >= 1000
                    ? '${(_alertRadius / 1000).toStringAsFixed(1)} กม.'
                    : '$_alertRadius ม.',
                AppColors.primaryDark,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            description,
            style: AppTextStyles.bodySmall.copyWith(
              color: NeumorphicTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          NeumorphicSlider(
            value: _alertRadius.toDouble().clamp(500, 100000),
            min: 500,
            max: 100000,
            divisions: 199,
            onChanged: (value) => setState(() => _alertRadius = value.round()),
            onChangeEnd: (value) =>
                _updateVolunteerSettings(radius: value.round()),
            activeColor: AppColors.primaryDark,
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '500 ม.',
                style: AppTextStyles.bodySmall.copyWith(
                  color: NeumorphicTheme.textSecondary,
                ),
              ),
              Text(
                '100 กม.',
                style: AppTextStyles.bodySmall.copyWith(
                  color: NeumorphicTheme.textSecondary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Section แยกสำหรับตั้งรัศมีการให้ทาง
  Widget _buildYieldWayRadiusSection() {
    return _buildNeuCard(
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
                  Flexible(
                    child: Text(
                      'รัศมีรับแจ้งเตือนให้ทาง',
                      style: AppTextStyles.bodyMedium.copyWith(
                        fontWeight: FontWeight.bold,
                        color: NeumorphicTheme.textPrimary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 8),
              _buildInsetValueBadge(
                _yieldWayRadius >= 1000
                    ? '${(_yieldWayRadius / 1000).toStringAsFixed(1)} กม.'
                    : '$_yieldWayRadius ม.',
                const Color(0xFF007AFF),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'รัศมีรอบจุดเกิดเหตุ ที่คุณยินดีช่วยเปิดทางให้รถฉุกเฉิน (หากอยู่บนเส้นทางของจิตอาสา)',
            style: AppTextStyles.bodySmall.copyWith(
              color: NeumorphicTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          NeumorphicSlider(
            value: _yieldWayRadius.toDouble().clamp(500, 20000),
            min: 500,
            max: 20000,
            divisions: 39,
            onChanged: (value) =>
                setState(() => _yieldWayRadius = value.round()),
            onChangeEnd: (value) => _updateYieldWayRadius(value.round()),
            activeColor: const Color(0xFF007AFF),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '500 ม.',
                style: AppTextStyles.bodySmall.copyWith(
                  color: NeumorphicTheme.textSecondary,
                ),
              ),
              Text(
                '20 กม.',
                style: AppTextStyles.bodySmall.copyWith(
                  color: NeumorphicTheme.textSecondary,
                ),
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
        _buildSectionHeader(
          'ข้อมูลสุขภาพสำหรับผู้ช่วยเหลือ',
          icon: Icons.health_and_safety_outlined,
          accent: AppColors.primaryDark,
        ),
        const SizedBox(height: 8),
        Text(
          'ตั้งค่าระบบเฝ้าระวังความปลอดภัยและข้อมูลสุขภาพที่จะเปิดเผยอัตโนมัติเมื่อเกิดเหตุฉุกเฉิน',
          style: AppTextStyles.bodySmall.copyWith(
            color: NeumorphicTheme.textSecondary,
          ),
        ),
        const SizedBox(height: 12),
        _buildNeuCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              NeumorphicSwitchTile(
                leading: _neuIconBadge(
                  Icons.health_and_safety_outlined,
                  AppColors.primaryDark,
                ),
                title: 'Emergency Health Auto-Release',
                subtitle: _isLoadingEmergencyHealthSettings
                    ? 'กำลังโหลดการตั้งค่า...'
                    : isEnabled
                    ? 'เปิดใช้งานอยู่ • พร้อมปลดล็อกเมื่อครบเงื่อนไข'
                    : 'ยังไม่เปิดใช้งาน',
                value: isEnabled,
                activeColor: AppColors.primaryDark,
                onChanged: _isSavingEmergencyHealthSettings
                    ? null
                    : (value) => _toggleEmergencyHealthEnabled(value),
              ),
              if (settings?.consentGivenAt != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.verified_outlined,
                        color: Colors.green[700],
                        size: 18,
                      ),
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
                style: AppTextStyles.bodyMedium.copyWith(
                  fontWeight: FontWeight.bold,
                  color: NeumorphicTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              NeumorphicSlider(
                value: _emergencyHealthReleaseDelayMinutes.toDouble().clamp(
                  1,
                  120,
                ),
                min: 1,
                max: 120,
                divisions: 119,
                label: '$_emergencyHealthReleaseDelayMinutes นาที',
                activeColor: AppColors.primaryDark,
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
                  Text(
                    '1 นาที',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: NeumorphicTheme.textSecondary,
                    ),
                  ),
                  Text(
                    '$_emergencyHealthReleaseDelayMinutes นาที',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.primaryDark,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    '120 นาที',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: NeumorphicTheme.textSecondary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'ข้อมูลที่จะแชร์',
                style: AppTextStyles.bodyMedium.copyWith(
                  fontWeight: FontWeight.bold,
                  color: NeumorphicTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _emergencyFieldOptions.map((option) {
                  final key = option['key']!;
                  final label = option['label']!;
                  final selected = _emergencyHealthEnabledFields.contains(key);
                  return NeumorphicChoiceChip(
                    label: label,
                    selected: selected,
                    accentColor: AppColors.primaryDark,
                    onSelected: _isSavingEmergencyHealthSettings
                        ? (_) {}
                        : (value) => _toggleEmergencyField(key, value),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              Text(
                'เงื่อนไขการปลดล็อก',
                style: AppTextStyles.bodyMedium.copyWith(
                  fontWeight: FontWeight.bold,
                  color: NeumorphicTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              _buildEmergencyBooleanSetting(
                title: 'ต้องมี responder ที่ active',
                subtitle:
                    'เปิดไว้เพื่อให้ข้อมูลปลดล็อกเฉพาะเมื่อมีผู้ช่วยเหลือที่ยัง active',
                value: _emergencyHealthRequireActiveResponder,
                onChanged: (value) =>
                    _saveEmergencyBooleanSetting(requireActiveResponder: value),
              ),
              const SizedBox(height: 10),
              _buildEmergencyBooleanSetting(
                title: 'ต้องเป็นสายอาชีพแพทย์/สาธารณสุข',
                subtitle: 'ใช้กรองผู้ช่วยเหลือที่มีสิทธิ์พิเศษด้านการรักษา',
                value: _emergencyHealthRequireMedicalProfession,
                onChanged: (value) => _saveEmergencyBooleanSetting(
                  requireMedicalProfession: value,
                ),
              ),
              const SizedBox(height: 10),
              _buildEmergencyBooleanSetting(
                title: 'ต้องยืนยันตัวตนแล้ว',
                subtitle: 'จำกัดการเข้าถึงเฉพาะผู้ใช้ที่ยืนยันตัวตนแล้ว',
                value: _emergencyHealthRequireVerified,
                onChanged: (value) =>
                    _saveEmergencyBooleanSetting(requireVerified: value),
              ),
              const SizedBox(height: 10),
              _buildEmergencyBooleanSetting(
                title: 'เปิด fallback หากไม่มีคนผ่านเงื่อนไข',
                subtitle:
                    'ขยายสิทธิ์อัตโนมัติเมื่อไม่มี responder ที่ตรงตามเงื่อนไข',
                value: _emergencyHealthEmergencyFallback,
                onChanged: (value) =>
                    _saveEmergencyBooleanSetting(emergencyFallback: value),
              ),
              if (_isLoadingEmergencyHealthSettings ||
                  _isSavingEmergencyHealthSettings) ...[
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
    return _buildNeuCard(
      borderRadius: 14,
      depth: 3,
      blur: 6,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: NeumorphicSwitchTile(
        title: title,
        subtitle: subtitle,
        value: value,
        activeColor: AppColors.primaryDark,
        onChanged: _isSavingEmergencyHealthSettings ? null : onChanged,
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
      _emergencyHealthSettings =
          (_emergencyHealthSettings ?? EmergencyHealthSettings.defaults())
              .copyWith(
                isEnabled: enabled,
                consentGivenAt: enabled
                    ? (_emergencyHealthSettings?.consentGivenAt ??
                          DateTime.now())
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
      setState(
        () => _emergencyHealthRequireActiveResponder = requireActiveResponder,
      );
    }
    if (requireMedicalProfession != null) {
      setState(
        () =>
            _emergencyHealthRequireMedicalProfession = requireMedicalProfession,
      );
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
          backgroundColor: NeumorphicTheme.baseColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
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

    final current =
        _emergencyHealthSettings ?? EmergencyHealthSettings.defaults();
    final updated = current.copyWith(
      isEnabled: isEnabled ?? current.isEnabled,
      releaseDelayMinutes:
          releaseDelayMinutes ?? _emergencyHealthReleaseDelayMinutes,
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
        _emergencyHealthEnabledFields = List<String>.from(
          updated.enabledFields,
        );
        _emergencyHealthRequireActiveResponder = updated.requireActiveResponder;
        _emergencyHealthRequireMedicalProfession =
            updated.requireMedicalProfession;
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
      final settings =
          await ServiceLocator.instance.emergencyHealthSettingsRepository
              .fetchSettings(userId) ??
          EmergencyHealthSettings.defaults();

      if (!mounted) return;
      setState(() {
        _emergencyHealthSettings = settings;
        _emergencyHealthReleaseDelayMinutes = settings.releaseDelayMinutes;
        _emergencyHealthEnabledFields = List<String>.from(
          settings.enabledFields,
        );
        _emergencyHealthRequireActiveResponder =
            settings.requireActiveResponder;
        _emergencyHealthRequireMedicalProfession =
            settings.requireMedicalProfession;
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
    return _buildNeuCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _neuIconBadge(Icons.visibility, Colors.red),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'สิทธิ์ดูวิดีโอต้นฉบับ',
                      style: AppTextStyles.bodyMedium.copyWith(
                        fontWeight: FontWeight.bold,
                        color: NeumorphicTheme.textPrimary,
                      ),
                    ),
                    Text(
                      'เลือกอาชีพจิตอาสาที่อนุญาตให้เห็นภาพ/วิดีโอไม่ผ่านการเบลอ',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: NeumorphicTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (_isSavingUnblurred)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.red),
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
              style: AppTextStyles.bodySmall.copyWith(
                color: NeumorphicTheme.textSecondary,
              ),
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
                    child: NeumorphicChoiceChip(
                      label: cat.displayName,
                      selected: isSelected,
                      accentColor: AppColors.primaryDark,
                      onSelected: (val) {
                        if (val) setState(() => _selectedCategory = cat.id);
                      },
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 16),
            // 2. ส่วนเลือกอาชีพในกลุ่มที่เลือก (Professions in Selected Category)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _allVolunteerProfessions
                  .where((p) => p.category.id == _selectedCategory)
                  .map((p) {
                    final isSelected = _selectedUnblurredIds.contains(p.id);
                    Color chipColor = AppColors.primaryDark;
                    if (p.colorHex != null && p.colorHex!.isNotEmpty) {
                      try {
                        chipColor = Color(
                          int.parse(p.colorHex!.replaceFirst('#', '0xFF')),
                        );
                      } catch (_) {}
                    }
                    return NeumorphicChoiceChip(
                      label: p.name,
                      selected: isSelected,
                      accentColor: chipColor,
                      onSelected: _isSavingUnblurred
                          ? (_) {}
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
            const SizedBox(height: 10),
            Text(
              'หมายเหตุ: อาชีพที่ไม่ได้เลือกจะเห็นเพียงภาพเบลอ (Privacy Mode)',
              style: AppTextStyles.bodySmall.copyWith(
                color: NeumorphicTheme.textSecondary.withValues(alpha: 0.8),
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
      backgroundColor: NeumorphicTheme.baseColor,
      clipBehavior: Clip.antiAlias,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) => SafeArea(
        child: NeumorphicFormSheetShell(
          title: 'เปลี่ยนรูปโปรไฟล์',
          icon: Icons.camera_alt_outlined,
          onClose: () => Navigator.pop(sheetContext),
          children: [
            _buildImagePickerOption(
              icon: Icons.camera_alt,
              label: 'ถ่ายรูป (Camera)',
              onTap: () {
                Navigator.pop(sheetContext);
                _processAndUploadAvatar(ImageSource.camera);
              },
            ),
            const SizedBox(height: 12),
            _buildImagePickerOption(
              icon: Icons.photo_library,
              label: 'เลือกจากคลังภาพ (Gallery)',
              onTap: () {
                Navigator.pop(sheetContext);
                _processAndUploadAvatar(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImagePickerOption({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: NeumorphicContainer(
          borderRadius: 16,
          depth: 4,
          blur: 8,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              _neuIconBadge(icon, NeumorphicTheme.primaryBlue, size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: AppTextStyles.bodyMedium.copyWith(
                    fontWeight: FontWeight.w600,
                    color: NeumorphicTheme.textPrimary,
                  ),
                ),
              ),
              const Icon(
                Icons.chevron_right,
                color: NeumorphicTheme.textSecondary,
              ),
            ],
          ),
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
      // 1. บีบอัดไฟล์ (Compress) — บน web compressImageToBytes คืน bytes ต้นฉบับ
      final imageBytes = await compressImageToBytes(
        pickedFile,
        quality: 70, // ลดคุณภาพลงเหลือ 70%
        maxDimension: 800, // จำกัดความกว้าง/สูงสูงสุด
      );

      // 2. อัปโหลดลง Storage
      final userId = _user!.id;
      final fileName =
          'profiles/$userId/avatar_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final supabase = Supabase.instance.client;

      // upload(File) → uploadBinary: storage_client อ่าน bytes อยู่แล้ว (W0.4)
      await supabase.storage.from('avatars').uploadBinary(
            fileName,
            imageBytes,
            fileOptions: FileOptions(
              contentType: contentTypeFor(fileName),
            ),
          );
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
        intervalMinutes:
            checkInIntervalMinutes ?? _deadManCheckInIntervalMinutes,
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

  // =====================================================
  // CHANGE PASSWORD
  // =====================================================

  Future<void> _openChangePasswordBottomSheet() async {
    final result = await showModalBottomSheet<PasswordChangeResult?>(
      context: context,
      isScrollControlled: true,
      isDismissible: true,
      enableDrag: true,
      backgroundColor: NeumorphicTheme.baseColor,
      clipBehavior: Clip.antiAlias,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) => const ChangePasswordBottomSheet(),
    );

    if (result == PasswordChangeResult.success) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('เปลี่ยนรหัสผ่านเรียบร้อยแล้ว'),
            backgroundColor: AppColors.success,
          ),
        );
      }
      await _loadProfile();
    }
  }

  Widget _buildChangePasswordTile() {
    final isLocalOnly = AppConfig.databaseMode == DatabaseMode.localOnly;
    final noPassword = !_hasPassword;
    final disabled = isLocalOnly || noPassword;

    return Opacity(
      opacity: disabled ? 0.55 : 1.0,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: disabled ? null : _openChangePasswordBottomSheet,
          borderRadius: BorderRadius.circular(20),
          child: _buildNeuCard(
            child: Row(
              children: [
                NeumorphicContainer(
                  width: 44,
                  height: 44,
                  borderRadius: 14,
                  depth: 3,
                  blur: 6,
                  child: Icon(
                    Icons.key,
                    color: disabled
                        ? NeumorphicTheme.textSecondary
                        : NeumorphicTheme.primaryBlue,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'เปลี่ยนรหัสผ่าน',
                        style: AppTextStyles.bodyMedium.copyWith(
                          fontWeight: FontWeight.bold,
                          color: disabled
                              ? NeumorphicTheme.textSecondary
                              : NeumorphicTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        isLocalOnly
                            ? 'ฟีเจอร์นี้ต้องเชื่อมต่ออินเทอร์เน็ต ไม่รองรับในโหมด Local Only'
                            : noPassword
                            ? 'บัญชีนี้ยังไม่ได้ตั้งรหัสผ่าน'
                            : 'เปลี่ยนรหัสผ่านเพื่อรักษาความปลอดภัยของบัญชี',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: NeumorphicTheme.textSecondary,
                        ),
                      ),
                      // §8 R5: แจ้งเตือนเมื่อถูกบังคับให้เปลี่ยนรหัสผ่าน
                      // (ต้องกรอกรหัสผ่านเดิมให้ถูกต้องก่อนเสมอ — §6.5 ปกติ)
                      if (!noPassword &&
                          (_user?.requiresPasswordReset ?? false)) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(
                              Icons.warning_amber_rounded,
                              size: 16,
                              color: Colors.orange,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'จำเป็นต้องเปลี่ยนรหัสผ่านเพื่อความปลอดภัยของบัญชี',
                                style: AppTextStyles.bodySmall.copyWith(
                                  color: Colors.orange.shade800,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                if (!disabled)
                  const Icon(
                    Icons.chevron_right,
                    color: NeumorphicTheme.textSecondary,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
