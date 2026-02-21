import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../data/repositories/user_repository.dart';
import '../../data/models/user_model.dart';
import '../widgets/social_login_button.dart';

/// Register Page
/// หน้าลงทะเบียน - Dark Gold Theme ตามภาพตัวอย่าง
class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage>
    with SingleTickerProviderStateMixin {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _isLoading = false;
  bool _acceptTerms = false;

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  // Dark Gold Theme Colors
  static const Color _bgDark = Color(0xFF1A1200);
  static const Color _bgGold = Color(0xFF8B6000);
  static const Color _goldAccent = Color(0xFFF5A623);
  static const Color _goldBright = Color(0xFFFFBF00);
  static const Color _cardBg = Color(0xFFFFFDF5);

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.25),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutCubic,
    ));

    _animationController.forward();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Background Gradient - Dark Gold
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFFD4900A),
                  Color(0xFF8B6000),
                  _bgDark,
                ],
                stops: [0.0, 0.5, 1.0],
              ),
            ),
          ),

          // Subtle glow overlay
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: MediaQuery.of(context).size.height * 0.35,
            child: CustomPaint(
              painter: _GlowGridPainter(),
            ),
          ),

          // Content
          SafeArea(
            child: Column(
              children: [
                // Top Section - Logo & Title
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Column(
                    children: [
                      // App Logo
                      Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const RadialGradient(
                            colors: [Color(0xFFFFD700), Color(0xFFB8860B)],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: _goldAccent.withOpacity(0.5),
                              blurRadius: 20,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.local_hospital_rounded,
                          color: Colors.white,
                          size: 36,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'สร้างบัญชีใหม่',
                        style: AppTextStyles.heading2.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 24,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'เริ่มต้นดูแลสุขภาพกับเรา',
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: Colors.white.withOpacity(0.7),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Bottom Card - Register Form (Scrollable)
                Expanded(
                  child: FadeTransition(
                    opacity: _fadeAnimation,
                    child: SlideTransition(
                      position: _slideAnimation,
                      child: Container(
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: _cardBg,
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(36),
                            topRight: Radius.circular(36),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.3),
                              blurRadius: 24,
                              offset: const Offset(0, -4),
                            ),
                          ],
                        ),
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
                          child: Form(
                            key: _formKey,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                // Name Field
                                _buildFieldLabel('ชื่อ-นามสกุล'),
                                const SizedBox(height: 6),
                                _buildInputField(
                                  controller: _nameController,
                                  hintText: 'กรอกชื่อ-นามสกุล',
                                  prefixIcon: Icons.person_outline_rounded,
                                  keyboardType: TextInputType.name,
                                ),
                                const SizedBox(height: 14),

                                // Phone Field
                                _buildFieldLabel('เบอร์โทรศัพท์ *'),
                                const SizedBox(height: 6),
                                _buildInputField(
                                  controller: _phoneController,
                                  hintText: '0xx-xxx-xxxx',
                                  prefixIcon: Icons.phone_outlined,
                                  keyboardType: TextInputType.phone,
                                ),
                                const SizedBox(height: 14),

                                // Email Field
                                _buildFieldLabel('อีเมล์ (ไม่บังคับ)'),
                                const SizedBox(height: 6),
                                _buildInputField(
                                  controller: _emailController,
                                  hintText: 'example@email.com',
                                  prefixIcon: Icons.email_outlined,
                                  keyboardType: TextInputType.emailAddress,
                                ),
                                const SizedBox(height: 14),

                                // Password Field
                                _buildFieldLabel('รหัสผ่าน'),
                                const SizedBox(height: 6),
                                _buildInputField(
                                  controller: _passwordController,
                                  hintText: '••••••••',
                                  prefixIcon: Icons.lock_outline_rounded,
                                  obscureText: _obscurePassword,
                                  suffixIcon: IconButton(
                                    onPressed: () {
                                      setState(() {
                                        _obscurePassword = !_obscurePassword;
                                      });
                                    },
                                    icon: Icon(
                                      _obscurePassword
                                          ? Icons.visibility_outlined
                                          : Icons.visibility_off_outlined,
                                      color: Colors.grey[500],
                                      size: 22,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 14),

                                // Confirm Password Field
                                _buildFieldLabel('ยืนยันรหัสผ่าน'),
                                const SizedBox(height: 6),
                                _buildInputField(
                                  controller: _confirmPasswordController,
                                  hintText: '••••••••',
                                  prefixIcon: Icons.lock_outline_rounded,
                                  obscureText: _obscureConfirmPassword,
                                  suffixIcon: IconButton(
                                    onPressed: () {
                                      setState(() {
                                        _obscureConfirmPassword =
                                            !_obscureConfirmPassword;
                                      });
                                    },
                                    icon: Icon(
                                      _obscureConfirmPassword
                                          ? Icons.visibility_outlined
                                          : Icons.visibility_off_outlined,
                                      color: Colors.grey[500],
                                      size: 22,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 16),

                                // Terms Checkbox
                                GestureDetector(
                                  onTap: () {
                                    setState(() {
                                      _acceptTerms = !_acceptTerms;
                                    });
                                  },
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                    children: [
                                      SizedBox(
                                        width: 22,
                                        height: 22,
                                        child: Checkbox(
                                          value: _acceptTerms,
                                          onChanged: (value) {
                                            setState(() {
                                              _acceptTerms = value ?? false;
                                            });
                                          },
                                          activeColor: _goldBright,
                                          checkColor: Colors.black,
                                          side: BorderSide(
                                            color: Colors.grey[400]!,
                                            width: 1.5,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(4),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: RichText(
                                          text: TextSpan(
                                            style:
                                                AppTextStyles.bodySmall.copyWith(
                                              color: Colors.grey[600],
                                              fontSize: 12.5,
                                            ),
                                            children: [
                                              const TextSpan(text: 'ฉันยอมรับ '),
                                              TextSpan(
                                                text: 'ข้อกำหนดการใช้งาน',
                                                style: TextStyle(
                                                  color: _goldAccent,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                              const TextSpan(text: ' และ '),
                                              TextSpan(
                                                text: 'นโยบายความเป็นส่วนตัว',
                                                style: TextStyle(
                                                  color: _goldAccent,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 22),

                                // Register Button - Gold
                                SizedBox(
                                  height: 54,
                                  child: ElevatedButton(
                                    onPressed: (_isLoading || !_acceptTerms)
                                        ? null
                                        : _handleRegister,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: _goldBright,
                                      foregroundColor: Colors.black,
                                      disabledBackgroundColor: Colors.grey[300],
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(28),
                                      ),
                                      elevation: 4,
                                      shadowColor: _goldAccent.withOpacity(0.5),
                                    ),
                                    child: _isLoading
                                        ? const SizedBox(
                                            width: 24,
                                            height: 24,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2.5,
                                              valueColor:
                                                  AlwaysStoppedAnimation<Color>(
                                                Colors.black54,
                                              ),
                                            ),
                                          )
                                        : Text(
                                            'ลงทะเบียน',
                                            style: AppTextStyles.button.copyWith(
                                              color: Colors.black,
                                              fontSize: 17,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                  ),
                                ),
                                const SizedBox(height: 20),

                                // Divider
                                Row(
                                  children: [
                                    Expanded(
                                      child: Divider(
                                        color: Colors.grey[300],
                                        thickness: 1,
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 12),
                                      child: Text(
                                        'หรือลงทะเบียนด้วย',
                                        style: AppTextStyles.bodySmall.copyWith(
                                          color: Colors.grey[500],
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: Divider(
                                        color: Colors.grey[300],
                                        thickness: 1,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),

                                // Social Login Icons
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    _buildSocialButton(
                                      SocialProvider.google,
                                      onPressed: () => _handleSocialRegister(
                                          SocialProvider.google),
                                    ),
                                    const SizedBox(width: 14),
                                    _buildSocialButton(
                                      SocialProvider.facebook,
                                      onPressed: () => _handleSocialRegister(
                                          SocialProvider.facebook),
                                    ),
                                    const SizedBox(width: 14),
                                    _buildSocialButton(
                                      SocialProvider.apple,
                                      onPressed: () => _handleSocialRegister(
                                          SocialProvider.apple),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 20),

                                // Login Link
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      'มีบัญชีอยู่แล้ว? ',
                                      style: AppTextStyles.bodyMedium.copyWith(
                                        color: Colors.grey[600],
                                        fontSize: 14,
                                      ),
                                    ),
                                    GestureDetector(
                                      onTap: _handleGoToLogin,
                                      child: Text(
                                        'เข้าสู่ระบบ',
                                        style: AppTextStyles.bodyMedium.copyWith(
                                          color: _goldAccent,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Back Button
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.pop(context),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  child: const Icon(
                    Icons.arrow_back_ios_new,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFieldLabel(String label) {
    return Text(
      label,
      style: AppTextStyles.bodySmall.copyWith(
        color: Colors.grey[700],
        fontWeight: FontWeight.w600,
        fontSize: 13,
      ),
    );
  }

  /// Build custom input field - White bg, subtle border, rounded
  Widget _buildInputField({
    required TextEditingController controller,
    required String hintText,
    required IconData prefixIcon,
    TextInputType? keyboardType,
    bool obscureText = false,
    Widget? suffixIcon,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: Colors.grey[200]!,
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        obscureText: obscureText,
        style: AppTextStyles.bodyMedium.copyWith(
          color: AppColors.textPrimary,
          fontSize: 15,
        ),
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: AppTextStyles.bodyMedium.copyWith(
            color: Colors.grey[400],
            fontSize: 14,
          ),
          prefixIcon: Icon(
            prefixIcon,
            color: Colors.grey[500],
            size: 22,
          ),
          suffixIcon: suffixIcon,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 16,
          ),
        ),
      ),
    );
  }

  /// Build social login button
  Widget _buildSocialButton(
    SocialProvider provider, {
    required VoidCallback onPressed,
  }) {
    Widget iconWidget;
    Color backgroundColor;
    Color? borderColor;

    switch (provider) {
      case SocialProvider.google:
        backgroundColor = Colors.white;
        borderColor = Colors.grey[200];
        iconWidget = _buildGoogleIcon();
        break;
      case SocialProvider.facebook:
        backgroundColor = const Color(0xFF1877F2);
        borderColor = null;
        iconWidget = const Text(
          'f',
          style: TextStyle(
            color: Colors.white,
            fontSize: 26,
            fontWeight: FontWeight.bold,
            fontFamily: 'Arial',
          ),
        );
        break;
      case SocialProvider.apple:
        backgroundColor = Colors.black;
        borderColor = null;
        iconWidget = const Icon(Icons.apple, color: Colors.white, size: 26);
        break;
      default:
        backgroundColor = Colors.grey;
        borderColor = null;
        iconWidget = const SizedBox.shrink();
    }

    return InkWell(
      onTap: _isLoading ? null : onPressed,
      borderRadius: BorderRadius.circular(28),
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: backgroundColor,
          shape: BoxShape.circle,
          border: borderColor != null
              ? Border.all(color: borderColor, width: 1.5)
              : null,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.10),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Center(child: iconWidget),
      ),
    );
  }

  Widget _buildGoogleIcon() {
    return CustomPaint(
      size: const Size(26, 26),
      painter: _GoogleIconPainter(),
    );
  }

  void _handleRegister() async {
    if (_nameController.text.isEmpty) {
      _showSnackBar('กรุณากรอกชื่อ-นามสกุล');
      return;
    }
    if (_phoneController.text.isEmpty) {
      _showSnackBar('กรุณากรอกเบอร์โทรศัพท์');
      return;
    }
    final phoneRegex = RegExp(r'^0[0-9]{8,9}$');
    if (!phoneRegex.hasMatch(
        _phoneController.text.replaceAll('-', '').replaceAll(' ', ''))) {
      _showSnackBar('รูปแบบเบอร์โทรศัพท์ไม่ถูกต้อง');
      return;
    }
    if (_emailController.text.isNotEmpty) {
      final emailRegex =
          RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$');
      if (!emailRegex.hasMatch(_emailController.text)) {
        _showSnackBar('รูปแบบอีเมลไม่ถูกต้อง');
        return;
      }
    }
    if (_passwordController.text.isEmpty) {
      _showSnackBar('กรุณากรอกรหัสผ่าน');
      return;
    }
    if (_passwordController.text.length < 6) {
      _showSnackBar('รหัสผ่านต้องมีอย่างน้อย 6 ตัวอักษร');
      return;
    }
    if (_passwordController.text != _confirmPasswordController.text) {
      _showSnackBar('รหัสผ่านไม่ตรงกัน');
      return;
    }
    if (!_acceptTerms) {
      _showSnackBar('กรุณายอมรับข้อกำหนดการใช้งาน');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final supabase = Supabase.instance.client;
      final userRepo = UserRepository(supabase);

      final nameParts = _nameController.text.trim().split(' ');
      final firstName = nameParts[0];
      final lastName =
          nameParts.length > 1 ? nameParts.sublist(1).join(' ') : '';

      final phone =
          _phoneController.text.replaceAll(RegExp(r'[^0-9]'), '');

      final phoneExists = await userRepo.isPhoneExists(phone);
      if (phoneExists) {
        throw Exception('เบอร์โทรศัพท์นี้ถูกใช้งานแล้ว');
      }

      await userRepo.createUser(
        userType: UserType.consumer,
        firstName: firstName,
        lastName: lastName,
        username: phone,
        password: _passwordController.text,
        phone: phone,
        email: _emailController.text.trim().isEmpty
            ? null
            : _emailController.text.trim(),
      );

      if (mounted) {
        setState(() {
          _isLoading = false;
        });

        _showSnackBar('ลงทะเบียนสำเร็จ! กรุณาเข้าสู่ระบบ');
        Navigator.pushReplacementNamed(context, '/login');
      }
    } catch (e) {
      debugPrint('Registration error: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        _showSnackBar(
            'เกิดข้อผิดพลาด: ${e.toString().replaceAll('Exception: ', '')}');
      }
    }
  }

  void _handleSocialRegister(SocialProvider provider) async {
    setState(() {
      _isLoading = true;
    });

    // TODO: Implement social register logic
    await Future.delayed(const Duration(seconds: 1));

    if (mounted) {
      setState(() {
        _isLoading = false;
      });

      _showSnackBar('${provider.name} login จะเปิดใช้งานเร็วๆ นี้');
    }
  }

  void _handleGoToLogin() {
    Navigator.pushReplacementNamed(context, '/login');
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
        backgroundColor: _bgGold,
      ),
    );
  }
}

/// Subtle glow/grid background painter
class _GlowGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFFFBF00).withOpacity(0.04)
      ..strokeWidth = 0.8
      ..style = PaintingStyle.stroke;

    const spacing = 32.0;
    for (double x = 0; x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }

    final glowPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFFFFBF00).withOpacity(0.12),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(
        center: Offset(size.width / 2, size.height * 0.3),
        radius: size.width * 0.5,
      ));
    canvas.drawCircle(
      Offset(size.width / 2, size.height * 0.3),
      size.width * 0.5,
      glowPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Custom Painter for Google "G" icon with colors
class _GoogleIconPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 2;

    const red = Color(0xFFEA4335);
    const yellow = Color(0xFFFBBC05);
    const green = Color(0xFF34A853);
    const blue = Color(0xFF4285F4);

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.15
      ..strokeCap = StrokeCap.butt;

    paint.color = red;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -2.4,
      0.8,
      false,
      paint,
    );

    paint.color = yellow;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      2.0,
      1.0,
      false,
      paint,
    );

    paint.color = green;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      0.7,
      1.3,
      false,
      paint,
    );

    paint.color = blue;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -1.6,
      1.2,
      false,
      paint,
    );

    final barPaint = Paint()
      ..color = blue
      ..style = PaintingStyle.fill;
    canvas.drawRect(
      Rect.fromLTWH(
        center.dx - 1,
        center.dy - size.height * 0.08,
        size.width * 0.45,
        size.height * 0.16,
      ),
      barPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
