import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_text_styles.dart';

/// Drawer Menu Item Model
class DrawerMenuItem {
  final String title;
  final IconData icon;
  final VoidCallback? onTap;
  final bool isUnderlined;

  const DrawerMenuItem({
    required this.title,
    required this.icon,
    this.onTap,
    this.isUnderlined = false,
  });
}

/// App Drawer Widget - Based on Med Design
/// Side menu with curved green background
/// รองรับการปัดไปทางซ้ายเพื่อปิด drawer พร้อม animation
class TlzDrawer extends StatefulWidget {
  final VoidCallback? onClose;
  final VoidCallback? onLogout;

  const TlzDrawer({
    super.key,
    this.onClose,
    this.onLogout,
  });

  @override
  State<TlzDrawer> createState() => _TlzDrawerState();
}

class _TlzDrawerState extends State<TlzDrawer> with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;
  
  // Threshold สำหรับการปัด (30% ของความกว้าง)
  static const double _swipeThreshold = 0.3;
  
  @override
  void initState() {
    super.initState();
    
    // Initialize animation controller
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    
    // Slide animation: เลื่อนไปทางซ้าย
    _slideAnimation = Tween<Offset>(
      begin: Offset.zero,
      end: const Offset(-1.0, 0.0), // เลื่อนไปทางซ้ายเต็มความกว้าง
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));
    
    // Fade animation: จางหายไป
    _fadeAnimation = Tween<double>(
      begin: 1.0,
      end: 0.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));
  }
  
  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }
  
  void _closeDrawer() {
    if (widget.onClose != null) {
      widget.onClose!();
    } else {
      Navigator.of(context).pop();
    }
  }
  
  void _handleSwipeEnd(DragEndDetails details) {
    // ตรวจสอบความเร็วและระยะทางของการปัด
    final velocity = details.velocity.pixelsPerSecond.dx;
    final currentProgress = _animationController.value;
    
    // ถ้าปัดเร็วไปทางซ้าย (negative velocity) หรือปัดเกิน threshold (30%)
    if (velocity < -500 || currentProgress > _swipeThreshold) {
      // เริ่ม animation ปิด drawer
      _animationController.forward().then((_) {
        _closeDrawer();
      });
    } else {
      // ถ้าไม่ถึง threshold ให้กลับมา
      _animationController.reverse();
    }
  }
  
  void _handleSwipeUpdate(DragUpdateDetails details) {
    // คำนวณระยะทางที่ปัด (เป็นเปอร์เซ็นต์ของความกว้างหน้าจอ)
    final screenWidth = MediaQuery.of(context).size.width;
    final delta = details.delta.dx;
    
    // คำนวณ progress ใหม่ (delta เป็นลบเมื่อปัดไปทางซ้าย)
    final progressDelta = -delta / screenWidth; // เปลี่ยนเป็นบวกเมื่อปัดไปทางซ้าย
    final currentProgress = _animationController.value;
    final newProgress = (currentProgress + progressDelta).clamp(0.0, 1.0);
    
    // อัพเดท animation progress
    _animationController.value = newProgress;
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: Colors.transparent,
      child: GestureDetector(
        onHorizontalDragUpdate: _handleSwipeUpdate,
        onHorizontalDragEnd: _handleSwipeEnd,
        child: SlideTransition(
          position: _slideAnimation,
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: Stack(
        children: [
          // White background
          Container(
            color: AppColors.backgroundWhite,
          ),
          
          // Green curved background on left
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: CustomPaint(
              size: Size(80, MediaQuery.of(context).size.height),
              painter: _DrawerCurvePainter(),
            ),
          ),
          
          // Content
          SafeArea(
            child: Column(
              children: [
                // Close button
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: GestureDetector(
                      onTap: () {
                        // เริ่ม animation ปิด drawer
                        _animationController.forward().then((_) {
                          _closeDrawer();
                        });
                      },
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: AppColors.backgroundWhite,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.shadow,
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.close,
                          size: 18,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ),
                ),
                
                // Menu items
                Expanded(
                  child: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.only(left: 60, right: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          // Home
                          _buildMenuItem(
                            context,
                            title: 'หน้าหลัก',
                            icon: Icons.arrow_forward,
                            onTap: () => _navigateTo(context, '/home'),
                          ),
                          
                          const SizedBox(height: 24),
                          
                          // Section 1: Medical Services
                          _buildMenuItem(
                            context,
                            title: 'ปรึกษา คุณหมอ',
                            icon: Icons.people_outline,
                            isUnderlined: true,
                            underlineText: 'ปรึกษา',
                            onTap: () => _navigateTo(context, '/consult-doctor'),
                          ),
                          _buildMenuItem(
                            context,
                            title: 'คลินิก / ร้านยา / ศูนย์',
                            icon: Icons.people_outline,
                            onTap: () => _navigateTo(context, '/clinic'),
                          ),
                          _buildMenuItem(
                            context,
                            title: 'บทความเพื่อสุขภาพ',
                            icon: Icons.people_outline,
                            isUnderlined: true,
                            underlineText: 'บทความ',
                            onTap: () => _navigateTo(context, '/articles'),
                          ),
                          _buildMenuItem(
                            context,
                            title: 'สินค้า',
                            icon: Icons.people_outline,
                            onTap: () => _navigateTo(context, '/products'),
                          ),
                          _buildMenuItem(
                            context,
                            title: 'โปรแกรมการรักษา',
                            icon: Icons.people_outline,
                            onTap: () => _navigateTo(context, '/care-programs'),
                          ),
                          
                          const SizedBox(height: 16),
                          const Divider(color: AppColors.divider),
                          const SizedBox(height: 16),
                          
                          // Section 2: Community
                          _buildMenuItem(
                            context,
                            title: 'แจ้งเหตุ / ร้องเรียน',
                            icon: Icons.people_outline,
                            isUnderlined: true,
                            underlineText: 'แจ้ง',
                            onTap: () => _navigateTo(context, '/news'),
                          ),
                          _buildMenuItem(
                            context,
                            title: 'บริจาค / ส่งกำลังใจ',
                            icon: Icons.people_outline,
                            onTap: () => _navigateTo(context, '/donate'),
                          ),
                          _buildMenuItem(
                            context,
                            title: 'มองหางาน',
                            icon: Icons.people_outline,
                            onTap: () => _navigateTo(context, '/jobs'),
                          ),
                          _buildMenuItem(
                            context,
                            title: 'คัดกรอง',
                            icon: Icons.people_outline,
                            onTap: () => _navigateTo(context, '/screening'),
                          ),
                          
                          const SizedBox(height: 16),
                          const Divider(color: AppColors.divider),
                          const SizedBox(height: 16),
                          
                          // Section 3: Help & About
                          _buildMenuItem(
                            context,
                            title: 'คู่มือการใช้',
                            icon: Icons.family_restroom,
                            onTap: () => _navigateTo(context, '/user-guide'),
                          ),
                          _buildMenuItem(
                            context,
                            title: 'ร่วมงานกับเรา',
                            icon: Icons.family_restroom,
                            onTap: () => _navigateTo(context, '/careers'),
                          ),
                          
                          const SizedBox(height: 16),
                          const Divider(color: AppColors.divider),
                          const SizedBox(height: 16),
                          
                          // Section 4: Settings
                          _buildMenuItem(
                            context,
                            title: 'ช่องทางชำระเงิน',
                            icon: Icons.credit_card,
                            onTap: () => _navigateTo(context, '/payment-methods'),
                          ),
                          _buildMenuItem(
                            context,
                            title: 'จัดการบัญชี',
                            icon: Icons.people_outline,
                            onTap: () => _navigateTo(context, '/account'),
                          ),
                          _buildMenuItem(
                            context,
                            title: 'ตั้งค่าระบบ',
                            icon: Icons.settings,
                            onTap: () => _navigateTo(context, '/settings'),
                          ),
                          
                          const SizedBox(height: 32),
                        ],
                      ),
                    ),
                  ),
                ),
                
                // Logout button
                Padding(
                  padding: const EdgeInsets.only(left: 60, right: 16, bottom: 32),
                  child: _buildMenuItem(
                    context,
                    title: 'ออกจากระบบ',
                    icon: Icons.logout,
                    onTap: widget.onLogout ?? () {
                      // TODO: Implement logout
                      debugPrint('Logout pressed');
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMenuItem(
    BuildContext context, {
    required String title,
    required IconData icon,
    VoidCallback? onTap,
    bool isUnderlined = false,
    String? underlineText,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            if (isUnderlined && underlineText != null)
              RichText(
                text: TextSpan(
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.textPrimary,
                  ),
                  children: [
                    TextSpan(
                      text: underlineText,
                      style: const TextStyle(
                        decoration: TextDecoration.underline,
                        decorationColor: AppColors.textPrimary,
                      ),
                    ),
                    TextSpan(
                      text: title.replaceFirst(underlineText, ''),
                    ),
                  ],
                ),
              )
            else
              Text(
                title,
                style: AppTextStyles.bodyMedium.copyWith(
                  color: AppColors.textPrimary,
                ),
              ),
            const SizedBox(width: 12),
            Icon(
              icon,
              size: 24,
              color: AppColors.primary,
            ),
          ],
        ),
      ),
    );
  }

  void _navigateTo(BuildContext context, String route) {
    // เริ่ม animation ปิด drawer ก่อน navigate
    _animationController.forward().then((_) {
      Navigator.of(context).pop(); // Close drawer first
      // TODO: Implement navigation
      debugPrint('Navigate to: $route');
    });
  }
}

/// Custom Painter for Drawer Curved Background
class _DrawerCurvePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.primary
      ..style = PaintingStyle.fill;

    final path = Path();
    
    // Start from bottom left
    path.moveTo(0, size.height);
    
    // Line to top left
    path.lineTo(0, 0);
    
    // Line to top (with some width)
    path.lineTo(size.width * 0.3, 0);
    
    // Curve down to bottom
    path.quadraticBezierTo(
      size.width * 1.2, // Control point X
      size.height * 0.5, // Control point Y
      size.width * 0.3, // End X
      size.height, // End Y
    );
    
    // Close the path
    path.close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
