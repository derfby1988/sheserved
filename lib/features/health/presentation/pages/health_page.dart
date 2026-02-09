import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../../shared/widgets/widgets.dart';
import '../../../../services/service_locator.dart';
import '../../../../services/auth_service.dart';
import '../../../auth/data/repositories/user_repository.dart';
import '../../../auth/data/models/user_model.dart';

/// Health Page - Health Dashboard
/// แสดงข้อมูลสุขภาพ อุปกรณ์ที่เชื่อมต่อ และคะแนนสุขภาพ
class HealthPage extends StatefulWidget {
  const HealthPage({super.key});

  @override
  State<HealthPage> createState() => _HealthPageState();
}

class _HealthPageState extends State<HealthPage> {
  int _selectedTabIndex = 0;
  ConsumerProfile? _profile;
  bool _isLoadingProfile = false;
  
  final List<String> _tabs = ['ทั่วไป', 'ออกแบบ\nโปรแกรม', 'คอร์ส\nVIP', 'บทความ\nสุขภาพ'];

  @override
  void initState() {
    super.initState();
    _loadUserProfile();
  }

  Future<void> _loadUserProfile() async {
    final authService = AuthService.instance;
    if (authService.isLoggedIn) {
      setState(() => _isLoadingProfile = true);
      try {
        final userRepository = ServiceLocator.get<UserRepository>();
        final profile = await userRepository.getConsumerProfile(authService.currentUser!.id);
        if (mounted) {
          setState(() {
            _profile = profile;
            _isLoadingProfile = false;
          });
        }
      } catch (e) {
        if (mounted) setState(() => _isLoadingProfile = false);
      }
    }
  }

  String _calculateAge() {
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
              size: Size(MediaQuery.of(context).size.width, 320),
              painter: _CurvedTopBackgroundPainter(
                gradientColors: const [Color(0xFF87B17F), Color(0xFF007FAD)],
              ),
            ),
          ),
          
          // Layer 2: Content
          SafeArea(
            child: Column(
              children: [
                // Top Navigation Bar - อยู่กับที่
                _buildTopNavigationBar(context),
                
                // Health Stats Card - อยู่กับที่ (ไม่ scroll)
                _buildHealthStatsCard(context),
                
                // Content Section
                Expanded(
                  child: Container(
                    color: Colors.white,
                    child: Column(
                      children: [
                        const SizedBox(height: 24),
                        
                        // Connected Devices Section - อยู่ด้านบน
                        _buildConnectedDevicesSection(context),
                        
                        // กึ่งกลางระหว่าง Connected Devices และ Top Tabs
                        Expanded(
                          child: Center(
                            child: _buildHealthScoreSection(context),
                          ),
                        ),
                      ],
                    ),
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
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Stats Grid
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                // Top Row: Age & BMI
                Row(
                  children: [
                    Expanded(
                      child: _buildStatItem(_calculateAge(), 'อายุ'),
                    ),
                    Container(
                      width: 1,
                      height: 50,
                      color: AppColors.divider,
                    ),
                    Expanded(
                      child: _buildStatItem('22', 'BMI'),
                    ),
                  ],
                ),
                
                const SizedBox(height: 40), // Space for avatar
                
                // Bottom Row: Weight & Height
                Row(
                  children: [
                    Expanded(
                      child: _buildStatItem('64', 'กก.น้ำหนัก'),
                    ),
                    Container(
                      width: 1,
                      height: 50,
                      color: AppColors.divider,
                    ),
                    Expanded(
                      child: _buildStatItem('174', 'ช.ม.ส่วนสูง'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          
          // Name - Positioned between avatar and top of card
          if (AuthService.instance.currentUser != null)
            Positioned(
              top: 12,
              left: 0,
              right: 0,
              child: Text(
                AuthService.instance.currentUser!.fullName,
                textAlign: TextAlign.center,
                style: AppTextStyles.bodySmall.copyWith(
                  color: const Color(0xFF58910F),
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),

          // Center Avatar
          Positioned(
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
                  size: 40,
                  color: AppColors.textHint,
                ),
              ),
            ),
          ),
          
          // Back Arrow
          Positioned(
            left: -8,
            child: GestureDetector(
              onTap: () {
                // Navigate back or to home page
                if (Navigator.canPop(context)) {
                  Navigator.pop(context);
                } else {
                  Navigator.pushReplacementNamed(context, '/');
                }
              },
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF5B9A8B),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.chevron_left,
                  color: Colors.white,
                  size: 20,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String value, String label) {
    bool isPlaceholder = value == 'ระบุ';
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        RichText(
          textAlign: TextAlign.center,
          text: TextSpan(
            children: [
              TextSpan(
                text: value,
                style: AppTextStyles.heading2.copyWith(
                  color: isPlaceholder ? const Color(0xFF7FA2C2) : const Color(0xFF58910F),
                  fontWeight: FontWeight.bold,
                  fontSize: isPlaceholder ? 14 : 28, // ปรับขนาดถ้าเป็นข้อความตัวหนังสือ
                ),
              ),
              if (!isPlaceholder)
                TextSpan(
                  text: ' $label',
                  style: AppTextStyles.bodyLarge.copyWith(
                    color: const Color(0xFF58910F),
                    fontWeight: FontWeight.w500,
                  ),
                ),
            ],
          ),
        ),
        if (isPlaceholder)
          Text(
            label,
            style: AppTextStyles.bodyLarge.copyWith(
              color: const Color(0xFF7FA2C2),
              fontWeight: FontWeight.w500,
            ),
          ),
      ],
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
                color: Colors.black.withOpacity(0.05),
                blurRadius: 4,
                offset: const Offset(0, 2),
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
    final screenWidth = MediaQuery.of(context).size.width;
    final circleSize = screenWidth * 0.40; // ปรับขนาดเป็น 40% ตามต้องการ (เดิม 35%)
    
    return Center(
      child: SizedBox(
        width: circleSize,
        height: circleSize,
        child: CustomPaint(
          painter: _HealthScorePainter(
            score: 91,
            segments: [
              _ScoreSegment(0.30, const Color(0xFFF5D5D5)), // Light pink
              _ScoreSegment(0.25, const Color(0xFFF8A88C)), // Orange/peach
              _ScoreSegment(0.36, Colors.white), // White/empty
            ],
          ),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '91 %',
                  style: AppTextStyles.heading1.copyWith(
                    color: AppColors.primary,
                    fontSize: 74, // ลดขนาดตัวเลข (เดิม 64)
                    fontWeight: FontWeight.w300,
                  ),
                ),
                Text(
                  'คะแนนสุขภาพ',
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
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
      padding: const EdgeInsets.symmetric(horizontal: 80), // เพิ่ม padding เป็น 80 เพื่อให้ tabs เล็กจิ๋วลงอีก
      child: tabsContent,
    );
  }
  
  /// Tab Item Widget
  Widget _buildTabItem(int index) {
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedTabIndex = index;
        });
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
              width: 48, // ปรับเป็น 48 ตามต้องการ
              height: 48,
              padding: EdgeInsets.zero,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12), // ปรับความโค้งให้สมดุลกับขนาด 48
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12), // เพิ่มระยะห่างระหว่างปุ่มกับข้อความ
            // Tab Label
            Text(
              _tabs[index],
              textAlign: TextAlign.center,
              style: AppTextStyles.caption.copyWith(
                fontSize: 20,
                height: 1.0,
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
}

/// Score Segment Data
class _ScoreSegment {
  final double percentage;
  final Color color;
  
  _ScoreSegment(this.percentage, this.color);
}

/// Health Score Circle Painter
class _HealthScorePainter extends CustomPainter {
  final int score;
  final List<_ScoreSegment> segments;
  
  _HealthScorePainter({
    required this.score,
    required this.segments,
  });
  
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - 40) / 2;
    const strokeWidth = 24.0;
    
    // Draw background circle (dotted)
    final dottedPaint = Paint()
      ..color = const Color(0xFFE0E0E0)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    
    // Draw dotted circle
    const dashWidth = 8.0;
    const dashSpace = 6.0;
    final circumference = 2 * math.pi * radius;
    final dashCount = (circumference / (dashWidth + dashSpace)).floor();
    final anglePerDash = (2 * math.pi) / dashCount;
    
    for (int i = 0; i < dashCount; i++) {
      final startAngle = i * anglePerDash - math.pi / 2;
      final sweepAngle = anglePerDash * 0.6;
      
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle,
        false,
        dottedPaint,
      );
    }
    
    // Draw colored segments
    double startAngle = -math.pi / 2; // Start from top
    
    for (final segment in segments) {
      if (segment.color != Colors.white) {
        final segmentPaint = Paint()
          ..color = segment.color
          ..strokeWidth = strokeWidth
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round;
        
        final sweepAngle = 2 * math.pi * segment.percentage;
        
        canvas.drawArc(
          Rect.fromCircle(center: center, radius: radius),
          startAngle,
          sweepAngle,
          false,
          segmentPaint,
        );
      }
      
      startAngle += 2 * math.pi * segment.percentage;
    }
    
    // Draw indicator dots
    final dotPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    
    final dotBorderPaint = Paint()
      ..color = const Color(0xFFE0E0E0)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    
    // Top dot
    final topDotCenter = Offset(center.dx, center.dy - radius);
    canvas.drawCircle(topDotCenter, 8, dotPaint);
    canvas.drawCircle(topDotCenter, 8, dotBorderPaint);
    
    // Right dot (end of orange segment)
    final rightAngle = -math.pi / 2 + 2 * math.pi * 0.55;
    final rightDotCenter = Offset(
      center.dx + radius * math.cos(rightAngle),
      center.dy + radius * math.sin(rightAngle),
    );
    canvas.drawCircle(rightDotCenter, 8, dotPaint);
    canvas.drawCircle(rightDotCenter, 8, dotBorderPaint);
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
    
    // Line down on right side (ประมาณ 70% ของความสูง)
    path.lineTo(size.width, size.height * 0.7);
    
    // Curve to bottom left - โค้งลงมา
    path.quadraticBezierTo(
      size.width / 2, // Control point X (center)
      size.height * 1.1, // Control point Y (below bottom for curve)
      0, // End X
      size.height * 0.7, // End Y
    );
    
    // Close the path back to top left
    path.close();
    
    canvas.drawPath(path, paint);
  }
  
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
