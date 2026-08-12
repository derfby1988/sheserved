import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:shimmer/shimmer.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../../shared/widgets/widgets.dart';
import '../../../../services/service_locator.dart';
import '../../../../services/auth_service.dart';
import '../../../auth/data/repositories/user_repository.dart';
import '../../../auth/data/models/user_model.dart';
import '../../data/models/health_data_change_log.dart';
import '../../data/models/health_data_change_log.dart';
import '../../data/repositories/health_repository.dart';
import '../widgets/health_history_dialog.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../shared/widgets/tlz_bottom_navigation_bar.dart';
import '../providers/health_provider.dart';

/// Health Page - Health Dashboard
/// แสดงข้อมูลสุขภาพ อุปกรณ์ที่เชื่อมต่อ และคะแนนสุขภาพ
class HealthPage extends ConsumerStatefulWidget {
  const HealthPage({super.key});

  @override
  ConsumerState<HealthPage> createState() => _HealthPageState();
}

class _HealthPageState extends ConsumerState<HealthPage>
    with SingleTickerProviderStateMixin {
  int _selectedTabIndex = 0;
  ConsumerProfile? _profile;
  bool _isLoadingProfile = false;
  bool _isNavBarVisible = true;

  late AnimationController _scoreController;
  late Animation<double> _scoreAnimation;
  double _targetScore = 0;

  final List<String> _tabs = [
    'หาก๊วน\nออกกำลังกาย',
    'ออกแบบ\nโปรแกรม',
    'คอร์ส\nVIP',
    'บทความ\nสุขภาพ',
  ];

  @override
  void initState() {
    super.initState();

    // Initialize animation with 0, will update after loading profile
    _scoreController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    _scoreAnimation = Tween<double>(begin: 0, end: 0).animate(_scoreController);

    // Listen for auth state changes to refresh profile
    AuthService.instance.addListener(_loadUserProfile);

    _loadUserProfile();
  }

  @override
  void dispose() {
    _scoreController.dispose();
    AuthService.instance.removeListener(_loadUserProfile);
    super.dispose();
  }

  Color _getScoreColor(double score) {
    if (score >= 80) return const Color(0xFF4CAF50); // Green
    if (score >= 60) return const Color(0xFF8BC34A); // Light Green
    if (score >= 40) return const Color(0xFFFFC107); // Yellow/Amber
    return const Color(0xFFF44336); // Red
  }

  void _updateDynamicScore(HealthState healthState) {
    final healthInfo = _profile?.healthInfo;
    if (healthInfo == null) return;

    double parseDouble(dynamic value) {
      if (value == null) return 0.0;
      if (value is num) return value.toDouble();
      if (value is String) return double.tryParse(value) ?? 0.0;
      return 0.0;
    }

    final bmi = healthInfo['bmi'] != null
        ? parseDouble(healthInfo['bmi'])
        : 21.4;

    // 1. Body Composition (30 points max)
    double bodyScore = 30.0;
    if (bmi < 18.5) {
      bodyScore -= (18.5 - bmi) * 3;
    } else if (bmi >= 23 && bmi < 30) {
      bodyScore -= (bmi - 22.9) * 2;
    } else if (bmi >= 30) {
      bodyScore -= (bmi - 22.9) * 4;
    }
    bodyScore = bodyScore.clamp(0.0, 30.0);

    // 2. Activity (30 points max)
    final steps = (healthState.todaySteps > 0) ? healthState.todaySteps : 8000;
    final calories =
        (healthState.todayActiveCalories != null &&
            healthState.todayActiveCalories! > 0)
        ? healthState.todayActiveCalories!
        : 300.0;

    double stepsScore = (steps / 8000.0) * 15.0;
    stepsScore = stepsScore.clamp(0.0, 15.0);

    double calScore = (calories / 300.0) * 15.0;
    calScore = calScore.clamp(0.0, 15.0);

    final double activityScore = stepsScore + calScore;

    // 3. Cardio (20 points max)
    final heartRate =
        (healthState.latestHeartRate != null &&
            healthState.latestHeartRate! > 0)
        ? healthState.latestHeartRate!
        : 72;
    final hrv = (healthState.latestHRV != null && healthState.latestHRV! > 0)
        ? healthState.latestHRV!
        : 40.0;

    double hrScore = 10.0;
    if (heartRate < 60) {
      hrScore -= (60 - heartRate) * 0.5;
    } else if (heartRate > 80) {
      hrScore -= (heartRate - 80) * 0.5;
    }
    hrScore = hrScore.clamp(0.0, 10.0);

    double hrvScore = (hrv / 40.0) * 10.0;
    hrvScore = hrvScore.clamp(0.0, 10.0);

    final double cardioScore = hrScore + hrvScore;

    // 4. Sleep (20 points max)
    final sleepMins =
        (healthState.lastSleepDuration != null &&
            healthState.lastSleepDuration! > 0)
        ? healthState.lastSleepDuration!
        : 420;
    double sleepScore = (sleepMins / 420.0) * 20.0;
    sleepScore = sleepScore.clamp(0.0, 20.0);

    final double totalCalculated =
        bodyScore + activityScore + cardioScore + sleepScore;
    final int newScore = totalCalculated.round().clamp(0, 100);

    if (newScore.toDouble() != _targetScore) {
      setState(() {
        _targetScore = newScore.toDouble();
        _scoreAnimation =
            Tween<double>(
              begin: _scoreAnimation.value,
              end: _targetScore,
            ).animate(
              CurvedAnimation(
                parent: _scoreController,
                curve: Curves.easeOutCubic,
              ),
            );
      });
      _scoreController.reset();
      _scoreController.forward();
    }
  }

  void _showScoreBreakdownDialog(
    BuildContext context,
    HealthState healthState,
  ) {
    final healthInfo = _profile?.healthInfo;
    if (healthInfo == null) return;

    double parseDouble(dynamic value) {
      if (value == null) return 0.0;
      if (value is num) return value.toDouble();
      if (value is String) return double.tryParse(value) ?? 0.0;
      return 0.0;
    }

    final bmi = healthInfo['bmi'] != null
        ? parseDouble(healthInfo['bmi'])
        : 21.4;

    // 1. Body Composition (30 points max)
    double bodyScore = 30.0;
    if (bmi < 18.5) {
      bodyScore -= (18.5 - bmi) * 3;
    } else if (bmi >= 23 && bmi < 30) {
      bodyScore -= (bmi - 22.9) * 2;
    } else if (bmi >= 30) {
      bodyScore -= (bmi - 22.9) * 4;
    }
    bodyScore = bodyScore.clamp(0.0, 30.0);

    // 2. Activity (30 points max)
    final steps = (healthState.todaySteps > 0) ? healthState.todaySteps : 8000;
    final calories =
        (healthState.todayActiveCalories != null &&
            healthState.todayActiveCalories! > 0)
        ? healthState.todayActiveCalories!
        : 300.0;

    double stepsScore = (steps / 8000.0) * 15.0;
    stepsScore = stepsScore.clamp(0.0, 15.0);

    double calScore = (calories / 300.0) * 15.0;
    calScore = calScore.clamp(0.0, 15.0);

    final double activityScore = stepsScore + calScore;

    // 3. Cardio (20 points max)
    final heartRate =
        (healthState.latestHeartRate != null &&
            healthState.latestHeartRate! > 0)
        ? healthState.latestHeartRate!
        : 72;
    final hrv = (healthState.latestHRV != null && healthState.latestHRV! > 0)
        ? healthState.latestHRV!
        : 40.0;

    double hrScore = 10.0;
    if (heartRate < 60) {
      hrScore -= (60 - heartRate) * 0.5;
    } else if (heartRate > 80) {
      hrScore -= (heartRate - 80) * 0.5;
    }
    hrScore = hrScore.clamp(0.0, 10.0);

    double hrvScore = (hrv / 40.0) * 10.0;
    hrvScore = hrvScore.clamp(0.0, 10.0);

    final double cardioScore = hrScore + hrvScore;

    // 4. Sleep (20 points max)
    final sleepMins =
        (healthState.lastSleepDuration != null &&
            healthState.lastSleepDuration! > 0)
        ? healthState.lastSleepDuration!
        : 420;
    double sleepScore = (sleepMins / 420.0) * 20.0;
    sleepScore = sleepScore.clamp(0.0, 20.0);

    final double totalCalculated =
        bodyScore + activityScore + cardioScore + sleepScore;
    final int newScore = totalCalculated.round().clamp(0, 100);
    final Color scoreColor = _getScoreColor(newScore.toDouble());

    Widget _buildDimensionRow({
      required IconData icon,
      required Color color,
      required String title,
      required double score,
      required double maxScore,
      required String subtitle,
    }) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF333333),
                    ),
                  ),
                ),
                Text(
                  '${score.toStringAsFixed(1)} / ${maxScore.toInt()} คะแนน',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: score / maxScore,
                backgroundColor: Colors.grey.shade200,
                valueColor: AlwaysStoppedAnimation<Color>(color),
                minHeight: 8,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            ),
          ],
        ),
      );
    }

    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 400),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
            ),
            padding: const EdgeInsets.all(20),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'เจาะลึกคะแนนสุขภาพ',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF333333),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const Divider(),
                  const SizedBox(height: 8),

                  // Big Score
                  Container(
                    width: 90,
                    height: 90,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: scoreColor.withOpacity(0.1),
                      border: Border.all(color: scoreColor, width: 3),
                    ),
                    child: Center(
                      child: Text(
                        '$newScore%',
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                          color: scoreColor,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'คะแนนสุขภาพคำนวณแบบ 4 มิติ',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Dimensions
                  _buildDimensionRow(
                    icon: Icons.accessibility_new,
                    color: Colors.teal,
                    title: '1. สัดส่วนร่างกาย (30%)',
                    score: bodyScore,
                    maxScore: 30,
                    subtitle:
                        'ดัชนีมวลกาย (BMI) = ${bmi.toStringAsFixed(1)} ${bmi < 18.5
                            ? "(ต่ำกว่าเกณฑ์ หัก ${(18.5 - bmi).toStringAsFixed(1)} คะแนน)"
                            : bmi >= 23
                            ? "(เกินเกณฑ์ปกติ)"
                            : "(ปกติ)"}',
                  ),
                  _buildDimensionRow(
                    icon: Icons.directions_walk,
                    color: Colors.orange,
                    title: '2. การเคลื่อนไหว (30%)',
                    score: activityScore,
                    maxScore: 30,
                    subtitle:
                        'ก้าวเดิน: $steps/8,000 ก้าว, เผาผลาญ: ${calories.toInt()}/300 kcal',
                  ),
                  _buildDimensionRow(
                    icon: Icons.favorite,
                    color: Colors.redAccent,
                    title: '3. ความแข็งแรงหัวใจ (20%)',
                    score: cardioScore,
                    maxScore: 20,
                    subtitle:
                        'ชีพจร: $heartRate bpm (เกณฑ์ 60-80), HRV: ${hrv.toInt()} ms',
                  ),
                  _buildDimensionRow(
                    icon: Icons.bedtime,
                    color: Colors.indigo,
                    title: '4. การนอนพักผ่อน (20%)',
                    score: sleepScore,
                    maxScore: 20,
                    subtitle:
                        'นอนหลับ: ${(sleepMins / 60).toStringAsFixed(1)} ชั่วโมง (เป้าหมาย 7 ชั่วโมง)',
                  ),

                  const SizedBox(height: 20),
                  const Divider(),
                  const SizedBox(height: 8),

                  // Footer Status
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        (healthState.connectionState ==
                                    HealthConnectionState.connected ||
                                healthState.todaySteps > 0)
                            ? Icons.check_circle
                            : Icons.info,
                        size: 14,
                        color:
                            (healthState.connectionState ==
                                    HealthConnectionState.connected ||
                                healthState.todaySteps > 0)
                            ? Colors.green
                            : Colors.amber,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        (healthState.connectionState ==
                                    HealthConnectionState.connected ||
                                healthState.todaySteps > 0)
                            ? 'ข้อมูลล่าสุดจากตารางสุขภาพจริงในระบบ (ซิงค์แล้ว)'
                            : 'ไม่ได้เชื่อมต่อสมาร์ทวอทช์ (ใช้ค่าปกติ)',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color:
                              (healthState.connectionState ==
                                      HealthConnectionState.connected ||
                                  healthState.todaySteps > 0)
                              ? Colors.green
                              : Colors.amber.shade800,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      onPressed: () => Navigator.pop(context),
                      child: const Text(
                        'รับทราบข้อมูล',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _loadUserProfile() async {
    final authService = AuthService.instance;

    // Guest Mode Check: Redirect to Login
    if (!authService.isLoggedIn) {
      if (mounted) {
        Future.delayed(Duration.zero, () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('กรุณาเข้าสู่ระบบเพื่อใช้งานฟีเจอร์สุขภาพ'),
              behavior: SnackBarBehavior.floating,
              backgroundColor: Colors.redAccent,
            ),
          );
          Navigator.pushReplacementNamed(
            context,
            '/login',
            arguments: '/health', // กลับมาหน้านี้หลังจาก Login สำเร็จ
          );
        });
      }
      return;
    }

    // Logged In User: Load Profile
    if (authService.isLoggedIn) {
      setState(() => _isLoadingProfile = true);
      try {
        final userRepository = ServiceLocator.get<UserRepository>();
        final profile = await userRepository.getConsumerProfile(
          authService.currentUser!.id,
        );

        if (mounted) {
          // ตรวจสอบว่ามีข้อมูลสุขภาพครบถ้วนหรือไม่ (เพศ, อายุ, น้ำหนัก, ส่วนสูง)
          final healthInfo = profile?.healthInfo;
          bool isDataMissing = healthInfo == null;

          if (!isDataMissing) {
            final gender = healthInfo!['gender'];
            final age = healthInfo['age'];
            final weight = healthInfo['weight'];
            final height = healthInfo['height'];

            // ตรวจสอบข้อมูลแต่ละตัว
            if (gender == null ||
                gender.toString().isEmpty ||
                age == null ||
                weight == null ||
                (weight is num && weight <= 0) ||
                height == null ||
                (height is num && height <= 0)) {
              isDataMissing = true;
            }
          }

          if (isDataMissing) {
            // ถ้าข้อมูลไม่ครบ ไม่ต้อง setState _profile (เพื่อให้หน้าจอ Loading ค้างไว้)
            // และ Redirect ทันที
            Future.delayed(Duration.zero, () {
              if (mounted) {
                Navigator.pushReplacementNamed(context, '/health-data-entry');
              }
            });
            return;
          }

          setState(() {
            _profile = profile;
            _isLoadingProfile = false;
          });
          _updateDynamicScore(ref.read(healthProvider));
        }
      } catch (e) {
        if (mounted) setState(() => _isLoadingProfile = false);
      }
    }
  }

  String _calculateAge() {
    // Priority 1: Check age in health_info
    final healthInfo = _profile?.healthInfo;

    // ถ้ามี age ใน healthInfo ให้ใช้เลย
    if (healthInfo != null &&
        healthInfo.containsKey('age') &&
        healthInfo['age'] != null) {
      return healthInfo['age'].toString();
    }

    // Priority 2: Fallback to calculation from birthday (ถ้า healthInfo['age'] เป็น null หรือไม่มี)
    if (_profile == null || _profile!.birthday == null) {
      return 'ระบุ';
    }

    final birthday = _profile!.birthday!;
    final today = DateTime.now();
    int age = today.year - birthday.year;

    if (today.month < birthday.month ||
        (today.month == birthday.month && today.day < birthday.day)) {
      age--;
    }

    return age.toString();
  }

  @override
  Widget build(BuildContext context) {
    final healthState = ref.watch(healthProvider);

    ref.listen<HealthState>(healthProvider, (previous, next) {
      _updateDynamicScore(next);
      if (next.errorMessage != null &&
          next.errorMessage!.isNotEmpty &&
          previous?.errorMessage != next.errorMessage) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next.errorMessage!),
            backgroundColor: Colors.red,
          ),
        );
      } else if (next.connectionState == HealthConnectionState.connected &&
          previous?.connectionState != HealthConnectionState.connected) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('เชื่อมต่ออุปกรณ์สุขภาพสำเร็จ'),
            backgroundColor: Colors.green,
          ),
        );
      }
    });

    return Scaffold(
      backgroundColor: Colors.white, // พื้นหลังสีขาว
      extendBody: true,
      drawer: const TlzDrawer(),
      body: Stack(
        children: [
          // Layer 1: Curved Shape Background - สีเขียวโค้งด้านบน
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: CustomPaint(
              size: Size(MediaQuery.of(context).size.width, 265),
              painter: _CurvedTopBackgroundPainter(
                gradientColors: const [Color(0xFF87B17F), Color(0xFF007FAD)],
              ),
            ),
          ),

          // Layer 2: Content
          Positioned.fill(
            child: SafeArea(
              bottom: false,
              child: Column(
                children: [
                  // Top Navigation Bar - อยู่กับที่
                  _buildTopNavigationBar(context),

                  // Health Stats Card - อยู่กับที่ (ไม่ scroll)
                  _isLoadingProfile
                      ? _buildShimmerStatsCard(context)
                      : _buildHealthStatsCard(context),

                  // Content Section - Make it scrollable and center components
                  Expanded(
                    child: NotificationListener<UserScrollNotification>(
                      onNotification: (notification) {
                        if (notification.direction == ScrollDirection.reverse) {
                          if (_isNavBarVisible) {
                            setState(() => _isNavBarVisible = false);
                          }
                        } else if (notification.direction == ScrollDirection.forward) {
                          if (!_isNavBarVisible) {
                            setState(() => _isNavBarVisible = true);
                          }
                        }
                        return false;
                      },
                      child: SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        child: Column(
                          children: [
                          const SizedBox(height: 16),

                          // Connected Devices Section
                          _isLoadingProfile
                              ? _buildShimmerDevicesSection(context)
                              : _buildConnectedDevicesSection(
                                  context,
                                  healthState,
                                ),

                          const SizedBox(height: 24),

                          // Health Score Section
                          _isLoadingProfile
                              ? _buildShimmerScoreSection(context)
                              : _buildHealthScoreSection(
                                  context,
                                  healthState,
                                ),

                          const SizedBox(height: 24),

                          // Bottom Tabs - ใน scroll
                          Container(
                            color: Colors.white,
                            child: _buildBottomTabs(context),
                          ),

                          const SizedBox(height: 120),
                        ],
                      ),
                    ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: TlzBottomNavigationBar(
        isVisible: _isNavBarVisible,
        currentIndex: -1,
        onIndexChanged: (index) {
          if (index == 2) return;
          Navigator.pushReplacementNamed(
            context,
            '/main-app',
            arguments: {'index': index},
          );
        },
        onAddPressed: () async {
          if (AuthService.instance.currentUser == null) {
            Navigator.pushNamed(context, '/login', arguments: '/emergency-live');
            return;
          }
          Navigator.pushNamed(context, '/emergency-live');
        },
      ),
    );
  }

  /// Top Navigation Bar - ใช้ TlzAppTopBar เหมือนหน้า Home
  Widget _buildTopNavigationBar(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: Colors.transparent, // ทำให้โปร่งใสเพื่อโชว์พื้นหลังไล่สีด้านหลัง
      ),
      child: TlzAppTopBar.onPrimary(
        notificationCount: 1,
        searchHintText: 'ค้นหาข้อมูลสุขภาพ...',
        onQRTap: () {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('QR Scanner')));
        },
        onNotificationTap: () {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Notifications')));
        },
        onCartTap: () {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Cart')));
        },
      ),
    );
  }

  /// Health Stats Card - Card สีขาวแสดงข้อมูลสุขภาพ
  Widget _buildHealthStatsCard(BuildContext context) {
    final healthInfo = _profile?.healthInfo;
    final bmi = healthInfo?['bmi'] != null
        ? (healthInfo!['bmi'] as num).toStringAsFixed(1)
        : 'ระบุ';
    final weight = healthInfo?['weight'] != null
        ? (healthInfo!['weight'] as num).toStringAsFixed(1)
        : 'ระบุ';
    final height = healthInfo?['height'] != null
        ? (healthInfo!['height'] as num).toStringAsFixed(1)
        : 'ระบุ';

    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          // Soft ambient shadow
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
          // Deeper bottom shadow for dimension
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 24,
            offset: const Offset(0, 12),
            spreadRadius: -4,
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Stats Grid
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min, // Added
              children: [
                // Top Row: Age & BMI
                Row(
                  children: [
                    Expanded(
                      child: _buildStatItem(
                        _calculateAge(),
                        'ปี',
                        'อายุ',
                        onTap: () => _showHistoryDialog('อายุ', 'age'),
                      ),
                    ),
                    Container(width: 1, height: 50, color: AppColors.divider),
                    Expanded(
                      child: _buildStatItem(
                        bmi,
                        '',
                        'BMI',
                        onTap: () => _showHistoryDialog(' BMI', 'bmi'),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // Bottom Row: Weight & Height
                Row(
                  children: [
                    Expanded(
                      child: _buildStatItem(
                        weight,
                        'กก.',
                        'น้ำหนัก',
                        onTap: () => _showHistoryDialog('น้ำหนัก', 'weight'),
                      ),
                    ),
                    Container(width: 1, height: 50, color: AppColors.divider),
                    Expanded(
                      child: _buildStatItem(
                        height,
                        'ซม.',
                        'ส่วนสูง',
                        onTap: () => _showHistoryDialog('ส่วนสูง', 'height'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Center Avatar & Name
          Positioned(
            child: Stack(
              alignment: Alignment.bottomCenter,
              clipBehavior: Clip.none,
              children: [
                GestureDetector(
                  onTap: () {
                    if (AuthService.instance.isLoggedIn) {
                      Navigator.pushNamed(context, '/health-data-entry');
                    } else {
                      Navigator.pushNamed(
                        context,
                        '/login',
                        arguments: '/health-data-entry',
                      );
                    }
                  },
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.divider, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: ClipOval(
                      child: (AuthService.instance.currentUser?.profileImageUrl?.isNotEmpty ?? false)
                          ? Image.network(
                              AuthService.instance.currentUser!.profileImageUrl!,
                              width: 80,
                              height: 80,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) => Icon(
                                Icons.person,
                                size: 32,
                                color: AppColors.textHint,
                              ),
                            )
                          : Icon(
                              Icons.person,
                              size: 32,
                              color: AppColors.textHint,
                            ),
                    ),
                  ),
                ),
                // User Name overlapping the bottom border
                // User Name under the avatar
                if (AuthService.instance.currentUser != null)
                  Positioned(
                    bottom: -5, // วางทับด้านบนเส้นขอบล่างของรูปโปรไฟล์
                    child: GestureDetector(
                      onTap: () {
                        if (AuthService.instance.isLoggedIn) {
                          Navigator.pushNamed(context, '/health-data-entry');
                        } else {
                          Navigator.pushNamed(
                            context,
                            '/login',
                            arguments: '/health-data-entry',
                          );
                        }
                      },
                      child: Text(
                        AuthService.instance.currentUser!.fullName,
                        style: AppTextStyles.bodySmall.copyWith(
                          color: const Color(0xFF7FA2C2),
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                          shadows: [
                            Shadow(
                              color: Colors.white.withOpacity(0.8),
                              offset: const Offset(0, 1),
                              blurRadius: 2,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // Back Arrow - Centered vertically
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: Center(
              child: GestureDetector(
                onTap: () {
                  // Navigate back or to home page
                  if (Navigator.of(context).canPop()) {
                    Navigator.of(context).pop();
                  } else {
                    Navigator.pushReplacementNamed(context, '/');
                  }
                },
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: const BoxDecoration(
                    color: Color(0xFF5B9A8B),
                    borderRadius: BorderRadius.only(
                      topRight: Radius.circular(8),
                      bottomRight: Radius.circular(8),
                    ),
                  ),
                  child: const Icon(
                    Icons.chevron_left,
                    color: Colors.white,
                    size: 16,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showHistoryDialog(String title, String fieldType) async {
    // Percentage loading state
    double percentage = 0;

    // Show loading with percentage
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          // Simulate progress
          Future.delayed(const Duration(milliseconds: 100), () {
            if (percentage < 95 && mounted) {
              setDialogState(() {
                percentage += 5 + (DateTime.now().millisecond % 10);
                if (percentage > 95) percentage = 95;
              });
            }
          });

          return Center(
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(color: Color(0xFF679E83)),
                  const SizedBox(height: 16),
                  Text(
                    'กำลังโหลด... ${percentage.toInt()}%',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF679E83),
                      decoration: TextDecoration.none,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );

    try {
      final authService = AuthService.instance;
      if (!authService.isLoggedIn) {
        Navigator.of(context).pop(); // Close loading
        return;
      }

      final userId = authService.currentUser!.id;
      final healthRepository = ServiceLocator.get<HealthRepository>();

      // Fetch real data from database
      final logs = await healthRepository.getHealthHistoryLog(
        userId,
        fieldType,
      );

      // Complete to 100% before closing
      percentage = 100;
      await Future.delayed(const Duration(milliseconds: 200));

      if (mounted) {
        Navigator.of(context).pop(); // Close loading

        showDialog(
          context: context,
          barrierColor: Colors.black.withOpacity(
            0.2,
          ), // Dim background slightly
          builder: (context) => HealthHistoryDialog(
            title: 'ประวัติ$title',
            fieldType: fieldType,
            historyLogs: logs,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop(); // Close loading
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('เกิดข้อผิดพลาดในการดึงข้อมูล: $e')),
        );
      }
    }
  }

  Widget _buildStatItem(
    String value,
    String unit,
    String label, {
    VoidCallback? onTap,
  }) {
    bool isPlaceholder = value == 'ระบุ';
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: RichText(
              textAlign: TextAlign.center,
              text: TextSpan(
                children: [
                  TextSpan(
                    text: value,
                    style: AppTextStyles.heading2.copyWith(
                      color: isPlaceholder
                          ? const Color(0xFF7FA2C2)
                          : const Color(0xFF58910F),
                      fontWeight: FontWeight.bold,
                      fontSize: isPlaceholder ? 14 : 24,
                      decoration: onTap != null
                          ? TextDecoration.underline
                          : null,
                      decorationColor: const Color(0xFF58910F).withOpacity(0.3),
                      decorationStyle: TextDecorationStyle.dashed,
                    ),
                  ),
                  if (!isPlaceholder && unit.isNotEmpty)
                    TextSpan(
                      text: ' $unit',
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: const Color(0xFF58910F),
                        fontWeight: FontWeight.w500,
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: AppTextStyles.bodyMedium.copyWith(
                  color: const Color(0xFF7FA2C2),
                  fontWeight: FontWeight.w500,
                  fontSize: 12,
                ),
              ),
              if (onTap != null) ...[
                const SizedBox(width: 4),
                const Icon(Icons.history, size: 12, color: Color(0xFF7FA2C2)),
              ],
            ],
          ),
        ],
      ),
    );
  }

  /// Connected Devices Section
  Widget _buildConnectedDevicesSection(
    BuildContext context,
    HealthState healthState,
  ) {
    return Column(
      children: [
        // Section Header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'อุปกรณ์ที่เชื่อมต่อ',
                style: AppTextStyles.heading5.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.bold,
                ),
              ),
              TextButton(
                onPressed: () {
                  _showAddDeviceBottomSheet(context);
                },
                child: Text(
                  'เพิ่ม',
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),

        // Devices Row - Scrollable
        Scrollbar(
          thumbVisibility: false, // จะปรากฏขึ้นเมื่อมีการเลื่อน
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                _buildDeviceItem(
                  Icons.monitor_weight,
                  'เครื่องชั่ง',
                  onTap: () {},
                ),
                const SizedBox(width: 80),
                _buildDeviceItem(
                  Icons.watch,
                  'นาฬิกา',
                  connectionState: healthState.connectionState,
                  onTap: () {
                    if (healthState.connectionState ==
                        HealthConnectionState.connected) {
                      _showDeviceDetailsBottomSheet(context, healthState);
                    } else {
                      _showAddDeviceBottomSheet(context);
                    }
                  },
                ),
                const SizedBox(width: 80),
                _buildDeviceItem(Icons.directions_run, 'ลู่วิ่ง', onTap: () {}),
                const SizedBox(width: 80),
                _buildDeviceItem(
                  Icons.ice_skating,
                  'รองเท้า',
                  isEmpty: true,
                  onTap: () {},
                ),
                const SizedBox(width: 80),
                _buildDeviceItem(
                  Icons.favorite,
                  'สายรัดหน้าอก',
                  isEmpty: true,
                  onTap: () {},
                ),
                const SizedBox(width: 80),
                _buildDeviceItem(
                  Icons.bluetooth,
                  'อุปกรณ์อื่นๆ',
                  isEmpty: true,
                  onTap: () {},
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Device Item Widget
  Widget _buildDeviceItem(
    IconData icon,
    String label, {
    bool isEmpty = false,
    HealthConnectionState? connectionState,
    VoidCallback? onTap,
  }) {
    Color iconColor = isEmpty ? AppColors.textHint : const Color(0xFF5B9A8B);
    Widget iconWidget = Icon(icon, color: iconColor, size: 28);

    if (connectionState != null) {
      if (connectionState == HealthConnectionState.checking) {
        iconWidget = const SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Color(0xFF5B9A8B),
          ),
        );
      } else if (connectionState == HealthConnectionState.connected) {
        iconColor = const Color(0xFF5B9A8B);
        iconWidget = Icon(icon, color: iconColor, size: 28);
      } else if (connectionState == HealthConnectionState.error) {
        iconColor = Colors.red;
        iconWidget = Icon(icon, color: iconColor, size: 28);
      } else if (connectionState == HealthConnectionState.disconnected) {
        iconColor = Colors.grey;
        iconWidget = Icon(icon, color: iconColor, size: 28);
      }
    }

    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border:
                  isEmpty ||
                      connectionState == HealthConnectionState.disconnected ||
                      connectionState == HealthConnectionState.initial
                  ? Border.all(color: AppColors.divider, width: 1)
                  : null,
              boxShadow:
                  (isEmpty ||
                      connectionState == HealthConnectionState.disconnected ||
                      connectionState == HealthConnectionState.initial)
                  ? null
                  : [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.08),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                      BoxShadow(
                        color: iconColor.withOpacity(0.1),
                        blurRadius: 4,
                        spreadRadius: -2,
                      ),
                    ],
            ),
            child: Center(child: iconWidget),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: AppTextStyles.caption.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  void _showAddDeviceBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        final isIOS = Theme.of(context).platform == TargetPlatform.iOS;
        final sourceName = isIOS ? 'Apple Health' : 'Health Connect';
        final iconData = isIOS ? Icons.apple : Icons.health_and_safety;

        return Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'เพิ่มอุปกรณ์สุขภาพ',
                style: AppTextStyles.heading4.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 24),
              ListTile(
                leading: Icon(iconData, size: 32, color: AppColors.primary),
                title: Text('เชื่อมต่อกับ $sourceName'),
                subtitle: const Text('ซิงค์ข้อมูลก้าวเดินและการนอนหลับ'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.pop(context);
                  ref.read(healthProvider.notifier).requestAccess();
                },
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  void _showDeviceDetailsBottomSheet(
    BuildContext context,
    HealthState healthState,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return Consumer(
          builder: (context, ref, child) {
            final s = ref.watch(healthProvider);
            final sourceName = s.activeSource?.sourceName ?? 'Unknown Source';

            // Helper functions
            String intStr(int? v) => v != null ? '$v' : '--';
            String dblStr(double? v, {int decimals = 1}) =>
                v != null ? v.toStringAsFixed(decimals) : '--';
            String sleepStr(int? min) =>
                min != null ? '${min ~/ 60}h ${min % 60}m' : '--';
            String distStr(double? m) =>
                m != null ? '${(m / 1000).toStringAsFixed(2)} km' : '--';

            return Padding(
              padding: EdgeInsets.only(
                left: 24,
                right: 24,
                top: 24,
                bottom: MediaQuery.of(context).viewInsets.bottom + 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Header
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF5B9A8B).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Icon(
                          Icons.watch,
                          size: 30,
                          color: Color(0xFF5B9A8B),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'นาฬิกาสุขภาพ',
                              style: AppTextStyles.heading4.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                const Icon(
                                  Icons.link,
                                  size: 14,
                                  color: Color(0xFF5B9A8B),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'Linked via $sourceName',
                                  style: AppTextStyles.caption.copyWith(
                                    color: const Color(0xFF5B9A8B),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      if (s.isSyncing)
                        const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Color(0xFF5B9A8B),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Container(height: 1, color: AppColors.divider),
                  const SizedBox(height: 20),

                  // Metrics Grid: Row 1
                  _buildMetricRow([
                    _MetricCell(
                      value: intStr(s.todaySteps),
                      label: 'ก้าวเดิน',
                      unit: 'steps',
                      color: AppColors.primary,
                      icon: Icons.directions_walk,
                    ),
                    _MetricCell(
                      value: intStr(s.latestHeartRate),
                      label: 'ชีพจร',
                      unit: 'BPM',
                      color: Colors.redAccent,
                      icon: Icons.favorite,
                    ),
                    _MetricCell(
                      value: sleepStr(s.lastSleepDuration),
                      label: 'การนอน',
                      unit: '',
                      color: Colors.indigoAccent,
                      icon: Icons.bedtime,
                    ),
                    _MetricCell(
                      value: dblStr(s.todayActiveCalories, decimals: 0),
                      label: 'แคลอรี่',
                      unit: 'kcal',
                      color: Colors.deepOrangeAccent,
                      icon: Icons.local_fire_department,
                    ),
                  ]),

                  const SizedBox(height: 20),

                  // Metrics Grid: Row 2
                  _buildMetricRow([
                    _MetricCell(
                      value: distStr(s.todayDistance),
                      label: 'ระยะทาง',
                      unit: '',
                      color: Colors.teal,
                      icon: Icons.map_outlined,
                    ),
                    _MetricCell(
                      value: dblStr(s.latestBloodOxygen),
                      label: 'ออกซิเจน',
                      unit: '%',
                      color: Colors.blue,
                      icon: Icons.air,
                    ),
                    _MetricCell(
                      value: dblStr(s.latestHRV),
                      label: 'HRV',
                      unit: 'ms',
                      color: Colors.purple,
                      icon: Icons.graphic_eq,
                    ),
                    _MetricCell(
                      value: intStr(s.todayExerciseTime),
                      label: 'ออกกำลัง',
                      unit: 'นาที',
                      color: Colors.green,
                      icon: Icons.fitness_center,
                    ),
                  ]),

                  const SizedBox(height: 16),

                  // Last sync time
                  if (s.lastSyncedAt != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.sync,
                            size: 12,
                            color: Color(0xFF9E9E9E),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'ซิงค์ล่าสุด: ${_formatSyncTime(s.lastSyncedAt!)}',
                            style: AppTextStyles.caption.copyWith(
                              color: AppColors.textHint,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ),

                  const SizedBox(height: 20),

                  // Buttons Section
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: s.isSyncing
                                ? Colors.grey.shade200
                                : Colors.grey.shade100,
                            foregroundColor: s.isSyncing
                                ? AppColors.textHint
                                : AppColors.textPrimary,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: s.isSyncing
                              ? null
                              : () {
                                  ref.read(healthProvider.notifier).forceSync();
                                },
                          child: s.isSyncing
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Color(0xFF5B9A8B),
                                  ),
                                )
                              : const Text(
                                  'ซิงค์ข้อมูลเดี๋ยวนี้',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red.shade50,
                            foregroundColor: Colors.red,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: s.isSyncing
                              ? null
                              : () {
                                  Navigator.pop(context);
                                  ref
                                      .read(healthProvider.notifier)
                                      .disconnect();
                                },
                          child: const Text(
                            'ยกเลิกการเชื่อมต่อ',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'จัดการสิทธิ์เพิ่มเติมได้ที่ การตั้งค่า > สุขภาพ > การเข้าถึงข้อมูล',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.textHint,
                      fontSize: 10,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildMetricRow(List<_MetricCell> cells) {
    return Row(
      children: cells.map((cell) {
        final isLast = cells.indexOf(cell) == cells.length - 1;
        return Expanded(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  children: [
                    Icon(cell.icon, size: 20, color: cell.color),
                    const SizedBox(height: 6),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        cell.value,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: cell.value == '--'
                              ? AppColors.textHint
                              : cell.color,
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    if (cell.unit.isNotEmpty)
                      Text(
                        cell.unit,
                        style: AppTextStyles.caption.copyWith(
                          fontSize: 9,
                          color: AppColors.textHint,
                        ),
                      ),
                    Text(
                      cell.label,
                      style: AppTextStyles.caption.copyWith(
                        fontSize: 10,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (!isLast)
                Container(width: 1, height: 48, color: AppColors.divider),
            ],
          ),
        );
      }).toList(),
    );
  }

  String _formatSyncTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'เมื่อสักครู่';
    if (diff.inMinutes < 60) return '${diff.inMinutes} นาทีที่แล้ว';
    if (diff.inHours < 24) return '${diff.inHours} ชั่วโมงที่แล้ว';
    return '${diff.inDays} วันที่แล้ว';
  }

  /// Health Score Section
  Widget _buildHealthScoreSection(
    BuildContext context,
    HealthState healthState,
  ) {
    if (_targetScore <= 0) return const SizedBox.shrink();

    final screenWidth = MediaQuery.of(context).size.width;
    final circleSize = screenWidth * 0.55; // Reduced from 0.35

    return AnimatedBuilder(
      animation: _scoreAnimation,
      builder: (context, child) {
        final currentScore = _scoreAnimation.value;
        final color = _getScoreColor(currentScore);

        return Center(
          child: GestureDetector(
            onTap: () => _showScoreBreakdownDialog(context, healthState),
            behavior: HitTestBehavior.opaque,
            child: SizedBox(
              width: circleSize,
              height: circleSize,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Background Circle (Light)
                  SizedBox(
                    width: circleSize,
                    height: circleSize,
                    child: CustomPaint(
                      painter: _HealthScorePainter(
                        score: 100,
                        color: AppColors.divider.withOpacity(0.3),
                        strokeWidth: 12,
                      ),
                    ),
                  ),
                  // Progress Circle (Animated)
                  SizedBox(
                    width: circleSize,
                    height: circleSize,
                    child: CustomPaint(
                      painter: _HealthScorePainter(
                        score: currentScore,
                        color: color,
                        strokeWidth: 14,
                      ),
                    ),
                  ),
                  // Text Center
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: circleSize * 0.8,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            '${currentScore.toInt()} %',
                            style: AppTextStyles.heading1.copyWith(
                              color: color,
                              fontSize: 34,
                              fontWeight: FontWeight.bold, // More emphasis
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      SizedBox(
                        width: circleSize * 0.9,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'คะแนนสุขภาพ',
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.bodyMedium.copyWith(
                                color: AppColors.textSecondary,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                height: 1.2,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '(แตะดูมิติสุขภาพ 4 ด้าน)',
                              textAlign: TextAlign.center,
                              style: AppTextStyles.caption.copyWith(
                                color: AppColors.primary,
                                fontSize: 8.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// Bottom Tabs - รูปทรงสี่เหลี่ยมจัตุรัส
  /// ในแนวนอนจะไม่ขยายเต็มพื้นที่เพื่อไม่ให้บดบัง Expanded
  Widget _buildBottomTabs(BuildContext context) {
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    final screenWidth = MediaQuery.of(context).size.width;

    // ในแนวนอน จำกัดความกว้างไม่เกิน 50% ของหน้าจอ
    final maxWidth = isLandscape ? screenWidth * 0.5 : double.infinity;

    Widget tabsContent = Row(
      mainAxisSize: isLandscape ? MainAxisSize.min : MainAxisSize.max,
      children: List.generate(_tabs.length, (index) {
        return isLandscape
            ? _buildTabItem(index) // ขนาดคงที่ในแนวนอน
            : Expanded(child: _buildTabItem(index)); // ขยายเต็มในแนวตั้ง
      }),
    );

    if (isLandscape) {
      return Center(
        child: Container(
          constraints: BoxConstraints(maxWidth: maxWidth),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: tabsContent,
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24), // Reduced from 80
      child: tabsContent,
    );
  }

  /// Tab Item Widget
  Widget _buildTabItem(int index) {
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

    return GestureDetector(
      onTap: () {
        if (index == 0) {
          Navigator.pushNamed(context, '/sport-club');
        } else if (index == 3) {
          Navigator.pushNamed(context, '/articles', arguments: 'แนะนำ');
        } else {
          setState(() {
            _selectedTabIndex = index;
          });
        }
      },
      child: Padding(
        padding: EdgeInsets.only(
          left: index == 0 ? 0 : 6,
          right: index == _tabs.length - 1 ? 0 : 6,
        ),
        child: Column(
          children: [
            // Tab Icon/Image placeholder - สี่เหลี่ยมจัตุรัส
            Container(
              width: 40, // Reduced from 48
              height: 40,
              padding: EdgeInsets.zero,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10), // Reduced from 12
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 3,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6), // Reduced from 8
            // Tab Label
            Text(
              _tabs[index],
              textAlign: TextAlign.center,
              style: AppTextStyles.caption.copyWith(
                fontSize: 11, // Reduced from 12
                height: 1.1,
                color: _selectedTabIndex == index
                    ? AppColors.primary
                    : AppColors.textSecondary,
                fontWeight: _selectedTabIndex == index
                    ? FontWeight.bold
                    : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Shimmer for Health Stats Card
  Widget _buildShimmerStatsCard(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: Colors.grey[300]!,
      highlightColor: Colors.grey[100]!,
      child: Container(
        margin: const EdgeInsets.all(16),
        height: 180,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
      ),
    );
  }

  /// Shimmer for Connected Devices Section
  Widget _buildShimmerDevicesSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Shimmer.fromColors(
            baseColor: Colors.grey[300]!,
            highlightColor: Colors.grey[100]!,
            child: Container(
              width: 150,
              height: 24,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: List.generate(
              4,
              (index) => Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Shimmer.fromColors(
                  baseColor: Colors.grey[300]!,
                  highlightColor: Colors.grey[100]!,
                  child: Column(
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: 40,
                        height: 12,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Shimmer for Health Score Section
  Widget _buildShimmerScoreSection(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final circleSize = screenWidth * 0.55;

    return Shimmer.fromColors(
      baseColor: Colors.grey[300]!,
      highlightColor: Colors.grey[100]!,
      child: Center(
        child: Container(
          width: circleSize,
          height: circleSize,
          decoration: const BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}

/// Health Score Circle Painter
class _HealthScorePainter extends CustomPainter {
  final double score;
  final Color color;
  final double strokeWidth;

  _HealthScorePainter({
    required this.score,
    required this.color,
    this.strokeWidth = 15,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    // Draw arc starting from top (-90 degrees)
    const startAngle = -math.pi / 2;
    final sweepAngle = (score / 100) * 2 * math.pi;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle,
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Curved Top Background Painter - วาดพื้นหลังโค้งสีเขียวด้านบน
class _CurvedTopBackgroundPainter extends CustomPainter {
  final List<Color> gradientColors;

  _CurvedTopBackgroundPainter({required this.gradientColors});

  @override
  void paint(Canvas canvas, Size size) {
    final Rect rect = Offset.zero & size;
    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: gradientColors,
      ).createShader(rect)
      ..style = PaintingStyle.fill;

    final path = Path();

    // Start from top left
    path.moveTo(0, 0);

    // Line to top right
    path.lineTo(size.width, 0);

    // Line down on right side (75% ของความสูง)
    path.lineTo(size.width, size.height * 0.75);

    // Curve to bottom left - โค้งลงมาที่จุดกึ่งกลางด้านล่างสุด (100% ของความสูง)
    path.quadraticBezierTo(
      size.width / 2, // Control point X (center)
      size.height, // Control point Y (bottom of the area)
      0, // End X
      size.height * 0.75, // End Y
    );

    // Close the path back to top left
    path.close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _MetricCell {
  final String value;
  final String label;
  final String unit;
  final Color color;
  final IconData icon;

  const _MetricCell({
    required this.value,
    required this.label,
    required this.unit,
    required this.color,
    required this.icon,
  });
}
