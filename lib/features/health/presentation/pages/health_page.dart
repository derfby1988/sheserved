import 'dart:math' as math;
import 'package:flutter/material.dart';
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

/// Health Page - Health Dashboard
/// แสดงข้อมูลสุขภาพ อุปกรณ์ที่เชื่อมต่อ และคะแนนสุขภาพ
class HealthPage extends StatefulWidget {
  const HealthPage({super.key});

  @override
  State<HealthPage> createState() => _HealthPageState();
}

class _HealthPageState extends State<HealthPage> with SingleTickerProviderStateMixin {
  int _selectedTabIndex = 0;
  ConsumerProfile? _profile;
  bool _isLoadingProfile = false;
  
  late AnimationController _scoreController;
  late Animation<double> _scoreAnimation;
  double _targetScore = 0;
  
  final List<String> _tabs = ['ทั่วไป', 'ออกแบบ\nโปรแกรม', 'คอร์ส\nVIP', 'บทความ\nสุขภาพ'];

  @override
  void initState() {
    super.initState();
    
    // Initialize animation with 0, will update after loading profile
    _scoreController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    
    _scoreAnimation = Tween<double>(
      begin: 0,
      end: 0,
    ).animate(_scoreController);

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
        final profile = await userRepository.getConsumerProfile(authService.currentUser!.id);
        
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
             if (gender == null || gender.toString().isEmpty ||
                 age == null ||
                 weight == null || (weight is num && weight <= 0) ||
                 height == null || (height is num && height <= 0)) {
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
            
            // Extract score from profile
            final healthInfo = profile!.healthInfo; // มั่นใจว่ามีค่าเพราะผ่าน check data missing แล้ว
            if (healthInfo != null && healthInfo['health_score'] != null) {
              _targetScore = (healthInfo['health_score'] as num).toDouble();
            } else {
              _targetScore = 0;
            }

            // Update animation with new target
            _scoreAnimation = Tween<double>(
              begin: 0,
              end: _targetScore,
            ).animate(CurvedAnimation(
              parent: _scoreController,
              curve: Curves.easeOutCubic,
            ));
            
            if (_targetScore > 0) {
              _scoreController.reset();
              _scoreController.forward();
            }
          });
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
    if (healthInfo != null && healthInfo.containsKey('age') && healthInfo['age'] != null) {
      return healthInfo['age'].toString();
    }

    // Priority 2: Fallback to calculation from birthday (ถ้า healthInfo['age'] เป็น null หรือไม่มี)
    if (_profile == null || _profile!.birthday == null) {
      return 'ระบุ';
    }
    
    final birthday = _profile!.birthday!;
    final today = DateTime.now();
    int age = today.year - birthday.year;
    
    if (today.month < birthday.month || (today.month == birthday.month && today.day < birthday.day)) {
      age--;
    }
    
    return age.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white, // พื้นหลังสีขาว
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
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minHeight: constraints.maxHeight,
                          ),
                          child: IntrinsicHeight(
                            child: Column(
                              children: [
                                const SizedBox(height: 16),
                                
                                // Connected Devices Section
                                _isLoadingProfile
                                  ? _buildShimmerDevicesSection(context)
                                  : _buildConnectedDevicesSection(context),
                                
                                // Dynamic Spacer to push Health Score to center of remaining space
                                const Spacer(),
                                
                                // Health Score Section
                                _isLoadingProfile
                                  ? _buildShimmerScoreSection(context)
                                  : _buildHealthScoreSection(context),
                                
                                // Dynamic Spacer at bottom to keep it centered
                                const Spacer(),
                                
                                const SizedBox(height: 16),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                
                // Bottom Tabs - อยู่กับที่ (ไม่ scroll)
                Container(
                  color: Colors.white,
                  child: _buildBottomTabs(context),
                ),
                
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ],
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
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('QR Scanner')),
          );
        },
        onNotificationTap: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Notifications')),
          );
        },
        onCartTap: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Cart')),
          );
        },
      ),
    );
  }

  /// Health Stats Card - Card สีขาวแสดงข้อมูลสุขภาพ
  Widget _buildHealthStatsCard(BuildContext context) {
    final healthInfo = _profile?.healthInfo;
    final bmi = healthInfo?['bmi'] != null ? (healthInfo!['bmi'] as num).toStringAsFixed(1) : 'ระบุ';
    final weight = healthInfo?['weight'] != null ? (healthInfo!['weight'] as num).toStringAsFixed(1) : 'ระบุ';
    final height = healthInfo?['height'] != null ? (healthInfo!['height'] as num).toStringAsFixed(1) : 'ระบุ';

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
                    Container(
                      width: 1,
                      height: 50,
                      color: AppColors.divider,
                    ),
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
                    Container(
                      width: 1,
                      height: 50,
                      color: AppColors.divider,
                    ),
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
                      border: Border.all(
                        color: AppColors.divider,
                        width: 2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Icon(
                      Icons.person,
                      size: 32,
                      color: AppColors.textHint,
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
        }
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
      final logs = await healthRepository.getHealthHistoryLog(userId, fieldType);
      
      // Complete to 100% before closing
      percentage = 100;
      await Future.delayed(const Duration(milliseconds: 200));

      if (mounted) {
        Navigator.of(context).pop(); // Close loading
        
        showDialog(
          context: context,
          barrierColor: Colors.black.withOpacity(0.2), // Dim background slightly
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

  Widget _buildStatItem(String value, String unit, String label, {VoidCallback? onTap}) {
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
                      color: isPlaceholder ? const Color(0xFF7FA2C2) : const Color(0xFF58910F),
                      fontWeight: FontWeight.bold,
                      fontSize: isPlaceholder ? 14 : 24,
                      decoration: onTap != null ? TextDecoration.underline : null,
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
                const Icon(
                  Icons.history,
                  size: 12,
                  color: Color(0xFF7FA2C2),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  /// Connected Devices Section
  Widget _buildConnectedDevicesSection(BuildContext context) {
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
                onPressed: () {},
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
                _buildDeviceItem(Icons.monitor_weight, 'เครื่องชั่ง'),
                const SizedBox(width: 80),
                _buildDeviceItem(Icons.watch, 'นาฬิกา'),
                const SizedBox(width: 80),
                _buildDeviceItem(Icons.directions_run, 'ลู่วิ่ง'),
                const SizedBox(width: 80),
                _buildDeviceItem(Icons.ice_skating, 'รองเท้า', isEmpty: true),
                const SizedBox(width: 80),
                _buildDeviceItem(Icons.favorite, 'สายรัดหน้าอก', isEmpty: true),
                const SizedBox(width: 80),
                _buildDeviceItem(Icons.bluetooth, 'อุปกรณ์อื่นๆ', isEmpty: true),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Device Item Widget
  Widget _buildDeviceItem(IconData icon, String label, {bool isEmpty = false}) {
    return Column(
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: isEmpty ? Colors.white : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: isEmpty 
              ? Border.all(color: AppColors.divider, width: 1)
              : null,
            boxShadow: isEmpty ? null : [
              BoxShadow(
                color: Colors.black.withOpacity(0.08), 
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
              BoxShadow(
                color: const Color(0xFF5B9A8B).withOpacity(0.1),
                blurRadius: 4,
                spreadRadius: -2,
              ),
            ],
          ),
          child: Icon(
            icon,
            color: isEmpty ? AppColors.textHint : const Color(0xFF5B9A8B),
            size: 28,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: AppTextStyles.caption.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }

  /// Health Score Section
  Widget _buildHealthScoreSection(BuildContext context) {
    if (_targetScore <= 0) return const SizedBox.shrink();

    final screenWidth = MediaQuery.of(context).size.width;
    final circleSize = screenWidth * 0.55; // Reduced from 0.35
    
    return AnimatedBuilder(
      animation: _scoreAnimation,
      builder: (context, child) {
        final currentScore = _scoreAnimation.value;
        final color = _getScoreColor(currentScore);
        
        return Center(
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
                    SizedBox(
                      width: circleSize * 0.9,
                      child: Text(
                        'คะแนนสุขภาพ',
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: AppColors.textSecondary,
                          fontSize: 10,
                          height: 1.2,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Bottom Tabs - รูปทรงสี่เหลี่ยมจัตุรัส
  /// ในแนวนอนจะไม่ขยายเต็มพื้นที่เพื่อไม่ให้บดบัง Expanded
  Widget _buildBottomTabs(BuildContext context) {
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
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
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    
    return GestureDetector(
      onTap: () {
        if (index == 3) {
          Navigator.pushNamed(context, '/health/article');
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
            children: List.generate(4, (index) => Padding(
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
            )),
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
