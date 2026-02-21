import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'dart:ui';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_text_styles.dart';
import '../../services/auth_service.dart';
import '../../features/consultation/presentation/logic/consultation_guard.dart';


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
  
  // สถานะการย่อ/ขยายของแต่ละกลุ่มเมนู
  final Map<String, bool> _expandedGroups = {
    'medical': true,
    'community': true,
    'settings': false,
    'admin': false,
    'help': false,
  };
  
  // Scroll Controller สำหรับจัดการ Dynamic Curve
  late ScrollController _scrollController;
  double _scrollOffset = 0.0;
  
  @override
  void initState() {
    super.initState();
    
    _scrollController = ScrollController();
    _scrollController.addListener(() {
      setState(() {
        _scrollOffset = _scrollController.offset;
      });
    });
    
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
    _scrollController.dispose();
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
    final screenWidth = MediaQuery.of(context).size.width;
    final drawerWidth = screenWidth * 0.50;

    return SizedBox(
      width: drawerWidth, // กำหนดความกว้างเป็น 50% ตามต้องการ
      child: Container(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 30,
              spreadRadius: 5,
              offset: const Offset(10, 0), // สาดเงาออกไปทางขวา (หน้า Home) ทีนอกตัว Drawer
            ),
          ],
        ),
        child: Drawer(
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
                Positioned.fill(
                  child: ClipRect(
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.7),
                          border: Border(
                            left: BorderSide(color: Colors.white.withOpacity(0.2), width: 1.5),
                            right: BorderSide(color: Colors.white.withOpacity(0.1), width: 0.5),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                
                // Green curved background on left
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  child: CustomPaint(
                    size: Size(60, MediaQuery.of(context).size.height),
                    painter: _DrawerCurvePainter(scrollOffset: _scrollOffset),
                  ),
                ),
                
                // Content
                SafeArea(
            child: Column(
              children: [
                // Header Section: Close Button & Profile Image
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Close button
                      GestureDetector(
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
                      
                      // Profile Image
                      GestureDetector(
                        onTap: () => _navigateTo(context, '/profile'),
                        child: Container(
                          width: 45,
                          height: 45,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: AppColors.primaryLight, width: 2),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.shadow,
                                blurRadius: 6,
                                offset: const Offset(0, 3),
                              ),
                            ],
                            image: const DecorationImage(
                              image: NetworkImage('https://i.pravatar.cc/150?img=32'),
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                
                // Fixed Home item
                Padding(
                  padding: const EdgeInsets.only(left: 60, right: 16),
                  child: _buildMenuItem(
                    context,
                    title: 'หน้าหลัก',
                    icon: Icons.arrow_forward,
                    onTap: () {
                      _animationController.forward().then((_) {
                        Navigator.of(context).pop(); // Close drawer
                        // Navigate to Home and clear stack
                        Navigator.of(context).pushNamedAndRemoveUntil(
                          '/',
                          (route) => false,
                        );
                      });
                    },
                  ),
                ),

                const SizedBox(height: 12),
                
                // Scrollable menu items
                Expanded(
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 60, right: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          const SizedBox(height: 12),
                          
                          // Section 1: Medical Services


                          
                          _buildGroupHeader(
                            context,
                            title: 'บริการทางการแพทย์',
                            isExpanded: _expandedGroups['medical']!,
                            onTap: () => setState(() => _expandedGroups['medical'] = !_expandedGroups['medical']!),
                          ),
                          if (_expandedGroups['medical']!) ...[
                            _buildMenuItem(
                              context,
                              title: 'สุขภาพ',
                              icon: Icons.favorite_outline,
                              onTap: () {
                                Navigator.of(context).pop();
                                Navigator.pushNamed(context, '/health');
                              },
                              isSubItem: true,
                            ),
                            _buildMenuItem(
                              context,
                              title: 'ปรึกษา คุณหมอ',
                              icon: Icons.people_outline,
                              isUnderlined: true,
                              underlineText: 'ปรึกษา',
                              onTap: () {
                                Navigator.pop(context); // close drawer first
                                ConsultationGuard.startConsultation(context);
                              },
                              isSubItem: true,
                            ),
                            _buildMenuItem(
                              context,
                              title: 'คลินิก / ร้านยา / ศูนย์',
                              icon: Icons.people_outline,
                              onTap: () => _navigateTo(context, '/clinic'),
                              isSubItem: true,
                            ),
                            _buildMenuItem(
                              context,
                              title: 'บทความเพื่อสุขภาพ',
                              icon: Icons.article_outlined,
                              isUnderlined: true,
                              underlineText: 'บทความ',
                              onTap: () {
                                _animationController.forward().then((_) {
                                  Navigator.of(context).pop();
                                  Navigator.pushNamed(context, '/articles');
                                });
                              },
                              isSubItem: true,
                            ),
                            _buildMenuItem(
                              context,
                              title: 'แชท / สนทนา',
                              icon: Icons.chat_bubble_outline,
                              isUnderlined: true,
                              underlineText: 'แชท',
                              onTap: () {
                                _animationController.forward().then((_) {
                                  Navigator.of(context).pop();
                                  Navigator.pushNamed(context, '/chat-list');
                                });
                              },
                              isSubItem: true,
                            ),

                            _buildMenuItem(
                              context,
                              title: 'สินค้า',
                              icon: Icons.people_outline,
                              onTap: () => _navigateTo(context, '/products'),
                              isSubItem: true,
                            ),
                            _buildMenuItem(
                              context,
                              title: 'โปรแกรมการรักษา',
                              icon: Icons.people_outline,
                              onTap: () => _navigateTo(context, '/care-programs'),
                              isSubItem: true,
                            ),
                          ],
                          
                          const SizedBox(height: 16),
                          const Divider(color: AppColors.divider),
                          const SizedBox(height: 16),
                          
                          // Section 2: Community
                          _buildGroupHeader(
                            context,
                            title: 'ชุมชน',
                            isExpanded: _expandedGroups['community']!,
                            onTap: () => setState(() => _expandedGroups['community'] = !_expandedGroups['community']!),
                          ),
                          if (_expandedGroups['community']!) ...[
                            _buildMenuItem(
                              context,
                              title: 'แจ้งเหตุ / ร้องเรียน',
                              icon: Icons.people_outline,
                              isUnderlined: true,
                              underlineText: 'แจ้ง',
                              onTap: () => _navigateTo(context, '/news'),
                              isSubItem: true,
                            ),
                            _buildMenuItem(
                              context,
                              title: 'บริจาค / ส่งกำลังใจ',
                              icon: Icons.people_outline,
                              onTap: () => _navigateTo(context, '/donate'),
                              isSubItem: true,
                            ),
                            _buildMenuItem(
                              context,
                              title: 'ดูแลผู้สูงอายุ',
                              icon: Icons.people_outline,
                              onTap: () => _navigateTo(context, '/jobs'),
                              isSubItem: true,
                            ),
                            _buildMenuItem(
                              context,
                              title: 'คัดกรองเข้าพื้นที่',
                              icon: Icons.people_outline,
                              onTap: () => _navigateTo(context, '/screening'),
                              isSubItem: true,
                            ),
                          ],
                          
                          const SizedBox(height: 16),
                          const Divider(color: AppColors.divider),
                          const SizedBox(height: 16),
                          
                          // Section 3: Help & About
                          _buildGroupHeader(
                            context,
                            title: 'ช่วยเหลือและเกี่ยวกับเรา',
                            isExpanded: _expandedGroups['help']!,
                            onTap: () => setState(() => _expandedGroups['help'] = !_expandedGroups['help']!),
                          ),
                          if (_expandedGroups['help']!) ...[
                            _buildMenuItem(
                              context,
                              title: 'คู่มือการใช้',
                              icon: Icons.family_restroom,
                              onTap: () => _navigateTo(context, '/user-guide'),
                              isSubItem: true,
                            ),
                            _buildMenuItem(
                              context,
                              title: 'ร่วมงานกับเรา',
                              icon: Icons.family_restroom,
                              onTap: () => _navigateTo(context, '/careers'),
                              isSubItem: true,
                            ),
                          ],
                          
                          const SizedBox(height: 16),
                          const Divider(color: AppColors.divider),
                          const SizedBox(height: 16),
                          
                          // Section 4: Settings
                          _buildGroupHeader(
                            context,
                            title: 'การตั้งค่า',
                            isExpanded: _expandedGroups['settings']!,
                            onTap: () => setState(() => _expandedGroups['settings'] = !_expandedGroups['settings']!),
                          ),
                          if (_expandedGroups['settings']!) ...[
                            _buildMenuItem(
                              context,
                              title: 'ช่องทางชำระเงิน',
                              icon: Icons.credit_card,
                              onTap: () => _navigateTo(context, '/payment-methods'),
                              isSubItem: true,
                            ),
                            _buildMenuItem(
                              context,
                              title: 'จัดการบัญชี',
                              icon: Icons.people_outline,
                              onTap: () => _navigateTo(context, '/account'),
                              isSubItem: true,
                            ),
                            _buildMenuItem(
                              context,
                              title: 'ตั้งค่าระบบ',
                              icon: Icons.settings,
                              onTap: () => _navigateTo(context, '/settings'),
                              isSubItem: true,
                            ),
                            _buildMenuItem(
                              context,
                              title: 'ตั้งค่า Sync',
                              icon: Icons.sync,
                              onTap: () => _navigateTo(context, '/settings/sync'),
                              isSubItem: true,
                            ),
                          ],
                          
                          const SizedBox(height: 16),
                          const Divider(color: AppColors.divider),
                          const SizedBox(height: 16),
                          
                          // Section 5: Admin
                          _buildGroupHeader(
                            context,
                            title: 'ผู้ดูแลระบบ',
                            isExpanded: _expandedGroups['admin']!,
                            onTap: () => setState(() => _expandedGroups['admin'] = !_expandedGroups['admin']!),
                          ),
                          if (_expandedGroups['admin']!) ...[
                            _buildMenuItem(
                              context,
                              title: 'จัดการอาชีพ',
                              icon: Icons.admin_panel_settings,
                              onTap: () => _navigateTo(context, '/admin/professions'),
                              isSubItem: true,
                            ),
                            _buildMenuItem(
                              context,
                              title: 'ตรวจสอบผู้สมัคร',
                              icon: Icons.verified_user_outlined,
                              onTap: () => _navigateTo(context, '/admin/applications'),
                              isSubItem: true,
                            ),
                          ],
                            const SizedBox(height: 32),
                          ],
                        ),
                      ),
                    ),
                  ),
                  
                  // Auth button
                  Padding(
                    padding: const EdgeInsets.only(left: 60, right: 16, bottom: 32),
                    child: _buildMenuItem(
                      context,
                      title: AuthService.instance.isLoggedIn ? 'ออกจากระบบ' : 'ลงชื่อเข้าใช้',
                      icon: AuthService.instance.isLoggedIn ? Icons.exit_to_app : Icons.login,
                      onTap: () {
                        _animationController.forward().then((_) {
                          if (AuthService.instance.isLoggedIn) {
                            if (widget.onLogout != null) {
                              widget.onLogout!();
                            } else {
                              AuthService.instance.logout();
                              Navigator.of(context).pop();
                              Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
                            }
                          } else {
                            Navigator.of(context).pop();
                            Navigator.of(context).pushNamed('/login');
                          }
                        });
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
    bool isSubItem = false,
    double? fontSize,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.only(
          top: 8,
          bottom: 8,
          right: isSubItem ? 4 : 0, 
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Flexible(
              child: isUnderlined && underlineText != null
                ? RichText(
                    textAlign: TextAlign.right,
                    text: TextSpan(
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: AppColors.textPrimary,
                        fontSize: fontSize ?? (isSubItem ? 12 : 14),
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
                : Text(
                    title,
                    textAlign: TextAlign.right,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 2,
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: AppColors.textPrimary,
                      fontSize: fontSize ?? (isSubItem ? 12 : 14),
                    ),
                  ),
            ),
            const SizedBox(width: 8),
            Icon(
              icon,
              size: isSubItem ? 16 : 20,
              color: AppColors.primary,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGroupHeader(
    BuildContext context, {
    required String title,
    required bool isExpanded,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Flexible(
              child: Text(
                title,
                textAlign: TextAlign.right,
                overflow: TextOverflow.ellipsis,
                maxLines: 2, // อนุญาตให้ขึ้นบรรทัดใหม่ได้สูงสุด 2 บรรทัด
                style: AppTextStyles.bodyLarge.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
            ),
            const SizedBox(width: 4),
            // ตกแต่งจุดกลมๆ ข้างหน้ากลุ่ม
            Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
              ),
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
      // Navigate to the route
      Navigator.pushNamed(context, route).catchError((error) {
        // ถ้า route ไม่มี ให้แสดง SnackBar
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('หน้า $route จะเปิดใช้งานเร็วๆ นี้'),
            duration: const Duration(seconds: 2),
          ),
        );
        return null;
      });
    });
  }
}

/// Custom Painter for Drawer Curved Background
class _DrawerCurvePainter extends CustomPainter {
  final double scrollOffset;

  _DrawerCurvePainter({this.scrollOffset = 0.0});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.primary.withOpacity(0.9) // ปรับให้โปร่งใสแบบแก้ว
      ..style = PaintingStyle.fill;

    final path = Path();
    
    // คำนวณความพริ้วไหวจากค่า Scroll (ใช้ Math.sin เพื่อให้เกิดคลื่น)
    // ขยับ Control Point X ตามการเลื่อน
    final waveAmplitude = 15.0; // ความกว้างของคลื่น
    final waveFrequency = 0.01; // ความถี่ของคลื่น
    final sway = math.sin(scrollOffset * waveFrequency) * waveAmplitude;
    
    // Start from bottom left
    path.moveTo(0, size.height);
    
    // Line to top left
    path.lineTo(0, 0);
    
    // Line to top (with some width)
    path.lineTo(size.width * 0.3, 0);
    
    // Curve down to bottom พร้อมลูกเล่นความพริ้ว
    path.quadraticBezierTo(
      size.width * 1.2 + sway, // Control point X (ขยับตาม scroll)
      size.height * 0.5 + (sway * 2), // Control point Y (ขยับตาม scroll)
      size.width * 0.3, // End X
      size.height, // End Y
    );
    
    // Close the path
    path.close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _DrawerCurvePainter oldDelegate) {
    return oldDelegate.scrollOffset != scrollOffset;
  }
}
