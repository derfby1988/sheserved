import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../../shared/widgets/widgets.dart';

/// Health Page - Health Dashboard
/// แสดงข้อมูลสุขภาพ อุปกรณ์ที่เชื่อมต่อ และคะแนนสุขภาพ
class HealthPage extends StatefulWidget {
  const HealthPage({super.key});

  @override
  State<HealthPage> createState() => _HealthPageState();
}

class _HealthPageState extends State<HealthPage> {
  int _selectedTabIndex = 0;
  
  final List<String> _tabs = ['ทั่วไป', 'ออกแบบ\nโปรแกรม', 'คอร์ส\nVIP', 'บทความ\nสุขภาพ'];

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
                color: const Color(0xFF5B9A8B),
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
                
                // Scrollable Content (เฉพาะส่วนนี้ scroll ได้)
                Expanded(
                  child: Container(
                    color: Colors.white,
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                          const SizedBox(height: 24),
                          
                          // Connected Devices Section
                          _buildConnectedDevicesSection(context),
                          
                          const SizedBox(height: 24),
                          
                          // Health Score Circle
                          _buildHealthScoreSection(context),
                          
                          const SizedBox(height: 24),
                        ],
                      ),
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
        color: Color(0xFF5B9A8B), // พื้นหลังสีเขียวเข้ม
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
                      child: _buildStatItem('26', 'ปีอายุ'),
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
          
          // Center Avatar
          Positioned(
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
          
          // Back Arrow
          Positioned(
            left: -8,
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
        ],
      ),
    );
  }

  /// Stat Item Widget
  Widget _buildStatItem(String value, String label) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        RichText(
          text: TextSpan(
            children: [
              TextSpan(
                text: value,
                style: AppTextStyles.heading3.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
              TextSpan(
                text: ' $label',
                style: AppTextStyles.bodyMedium.copyWith(
                  color: AppColors.primary,
                ),
              ),
            ],
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
        
        // Devices Row
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildDeviceItem(Icons.monitor_weight, 'เครื่องชั่ง'),
              _buildDeviceItem(Icons.watch, 'นาฬิกา'),
              _buildDeviceItem(Icons.directions_run, 'ลู่วิ่ง'),
              _buildDeviceItem(Icons.ice_skating, 'รองเท้า', isEmpty: true),
            ],
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
    final circleSize = screenWidth * 0.5; // 50% ของความกว้างหน้าจอ
    
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
                    fontSize: 64,
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
      padding: const EdgeInsets.symmetric(horizontal: 16),
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
              width: isLandscape ? 100 : null, // ขนาดคงที่ในแนวนอน
              height: isLandscape ? 100 : null,
              child: isLandscape
                ? Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                  )
                : AspectRatio(
                    aspectRatio: 1, // สี่เหลี่ยมจัตุรัส (1:1)
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                    ),
                  ),
            ),
            const SizedBox(height: 8),
            // Tab Label
            Text(
              _tabs[index],
              textAlign: TextAlign.center,
              style: AppTextStyles.caption.copyWith(
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
  final Color color;
  
  _CurvedTopBackgroundPainter({required this.color});
  
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
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
