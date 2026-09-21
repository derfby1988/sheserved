import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sheserved/core/constants/password_policy.dart';
import '../../data/repositories/user_repository.dart';
import '../../data/models/user_model.dart';
import '../widgets/social_login_button.dart';
import '../../../../shared/widgets/widgets.dart';

/// Register Page
/// หน้าลงทะเบียน - ออกแบบ UI และ UX ในสไตล์ Neumorphism ตามรูปต้นฉบับ
/// (ใช้ชุด Widget ส่วนกลางจาก shared/widgets/neumorphic)
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
  bool _isLoading = false;

  // ช่องยืนยันจะแสดงค้างไว้เมื่อมีค่าที่ผู้ใช้กรอกแล้ว
  bool get _showConfirmPasswordField =>
      _obscurePassword || _confirmPasswordController.text.isNotEmpty;
  bool _acceptTerms = false;

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );

    _slideAnimation =
        Tween<Offset>(begin: const Offset(0, 0.15), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _animationController,
            curve: Curves.easeOutCubic,
          ),
        );

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
      backgroundColor: NeumorphicTheme.baseColor,
      body: Stack(
        children: [
          // วงกลม Neumorphic ลอยเป็นพื้นหลังตาม CSS .bg-circle ในภาพต้นฉบับ
          Positioned(top: -60, left: -60, child: _buildBackgroundCircle(220)),
          Positioned(
            bottom: -70,
            right: -70,
            child: _buildBackgroundCircle(240),
          ),

          // เนื้อหาหลัก - การ์ด Neumorphic Form Panel
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 24,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: FadeTransition(
                    opacity: _fadeAnimation,
                    child: SlideTransition(
                      position: _slideAnimation,
                      child: NeumorphicContainer(
                        color: NeumorphicTheme.baseColor,
                        // ค่าตาม CSS .form-panel { border-radius: 35px; }
                        borderRadius: 35.0,
                        depth: 20.0,
                        blur: 40.0,
                        padding: const EdgeInsets.fromLTRB(30, 32, 30, 30),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // ไอคอนแม่กุญแจสีทองในวงกลมนูน Neumorphic ด้านบนตามภาพต้นฉบับ
                              const Center(
                                child: NeumorphicLockBadge(
                                  size: 82,
                                  iconSize: 38,
                                ),
                              ),
                              const SizedBox(height: 18),

                              // หัวข้อ "สร้างบัญชีใหม่"
                              const Text(
                                'สร้างบัญชีใหม่',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w800,
                                  color: NeumorphicTheme.textPrimary,
                                  letterSpacing: -0.2,
                                ),
                              ),
                              const SizedBox(height: 6),

                              // คำอธิบายรอง
                              const Text(
                                'เริ่มต้นดูแลสุขภาพกับเรา',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w400,
                                  color: NeumorphicTheme.textSecondary,
                                ),
                              ),
                              const SizedBox(height: 24),

                              // Name Field
                              _buildFieldLabel('ชื่อ-นามสกุล'),
                              const SizedBox(height: 8),
                              NeumorphicInputField(
                                controller: _nameController,
                                hintText: 'กรอกชื่อ-นามสกุล',
                                prefixIcon: Icons.person_outline_rounded,
                                keyboardType: TextInputType.name,
                                textInputAction: TextInputAction.next,
                              ),
                              const SizedBox(height: 16),

                              // Phone Field
                              _buildFieldLabel('เบอร์โทรศัพท์ *'),
                              const SizedBox(height: 8),
                              NeumorphicInputField(
                                controller: _phoneController,
                                hintText: '0xx-xxx-xxxx',
                                prefixIcon: Icons.phone_outlined,
                                keyboardType: TextInputType.phone,
                                textInputAction: TextInputAction.next,
                              ),
                              const SizedBox(height: 16),

                              // Email Field
                              _buildFieldLabel('อีเมล์ (ไม่บังคับ)'),
                              const SizedBox(height: 8),
                              NeumorphicInputField(
                                controller: _emailController,
                                hintText: 'example@email.com',
                                prefixIcon: Icons.email_outlined,
                                keyboardType: TextInputType.emailAddress,
                                textInputAction: TextInputAction.next,
                              ),
                              const SizedBox(height: 16),

                              // Password Field
                              _buildFieldLabel('รหัสผ่าน'),
                              const SizedBox(height: 8),
                              NeumorphicInputField(
                                controller: _passwordController,
                                hintText: '••••••••',
                                prefixIcon: Icons.lock_outline_rounded,
                                obscureText: _obscurePassword,
                                textInputAction: TextInputAction.next,
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
                                    color: NeumorphicTheme.textSecondary,
                                    size: 20,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),

                              // Confirm Password Field
                              AnimatedSize(
                                duration: const Duration(milliseconds: 220),
                                curve: Curves.easeInOut,
                                child: _showConfirmPasswordField
                                    ? Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          _buildFieldLabel('ยืนยันรหัสผ่าน'),
                                          const SizedBox(height: 8),
                                          NeumorphicInputField(
                                            controller:
                                                _confirmPasswordController,
                                            hintText: '••••••••',
                                            prefixIcon:
                                                Icons.lock_outline_rounded,
                                            obscureText: _obscurePassword,
                                            textInputAction:
                                                TextInputAction.done,
                                            onChanged: (_) => setState(() {}),
                                            suffixIcon: IconButton(
                                              onPressed: () {
                                                setState(() {
                                                  _obscurePassword =
                                                      !_obscurePassword;
                                                });
                                              },
                                              icon: Icon(
                                                _obscurePassword
                                                    ? Icons.visibility_outlined
                                                    : Icons
                                                          .visibility_off_outlined,
                                                color: NeumorphicTheme
                                                    .textSecondary,
                                                size: 20,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 16),
                                        ],
                                      )
                                    : const SizedBox.shrink(),
                              ),

                              // Terms Checkbox
                              GestureDetector(
                                onTap: () {
                                  setState(() {
                                    _acceptTerms = !_acceptTerms;
                                  });
                                },
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
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
                                        activeColor:
                                            NeumorphicTheme.primaryBlue,
                                        checkColor: Colors.white,
                                        side: const BorderSide(
                                          color: Color(0xFF94A3B8),
                                          width: 1.5,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            4,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: RichText(
                                        text: const TextSpan(
                                          style: TextStyle(
                                            color:
                                                NeumorphicTheme.textSecondary,
                                            fontSize: 12.5,
                                          ),
                                          children: [
                                            TextSpan(text: 'ฉันยอมรับ '),
                                            TextSpan(
                                              text: 'ข้อกำหนดการใช้งาน',
                                              style: TextStyle(
                                                color: Color(0xFF0284C7),
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            TextSpan(text: ' และ '),
                                            TextSpan(
                                              text: 'นโยบายความเป็นส่วนตัว',
                                              style: TextStyle(
                                                color: Color(0xFF0284C7),
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

                              // Register Button - Vibrant Gradient Pill Button
                              NeumorphicVerifyButton(
                                key: const Key('register_submit'),
                                text: 'ลงทะเบียน',
                                isLoading: _isLoading,
                                isEnabled: !_isLoading && _acceptTerms,
                                onPressed: _handleRegister,
                              ),
                              const SizedBox(height: 22),

                              // เส้นคั่น "หรือลงทะเบียนด้วย"
                              Row(
                                children: [
                                  Expanded(
                                    child: Container(
                                      height: 1,
                                      color: const Color(0xFFCBD5E1),
                                    ),
                                  ),
                                  const Padding(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 12,
                                    ),
                                    child: Text(
                                      'หรือลงทะเบียนด้วย',
                                      style: TextStyle(
                                        color: NeumorphicTheme.textSecondary,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: Container(
                                      height: 1,
                                      color: const Color(0xFFCBD5E1),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 18),

                              // ปุ่ม Social Login สไตล์ Neumorphic
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  _buildSocialButton(
                                    SocialProvider.google,
                                    onPressed: () => _handleSocialRegister(
                                      SocialProvider.google,
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  _buildSocialButton(
                                    SocialProvider.facebook,
                                    onPressed: () => _handleSocialRegister(
                                      SocialProvider.facebook,
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  _buildSocialButton(
                                    SocialProvider.apple,
                                    onPressed: () => _handleSocialRegister(
                                      SocialProvider.apple,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 22),

                              // ลิงก์เข้าสู่ระบบ
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Text(
                                    'มีบัญชีอยู่แล้ว? ',
                                    style: TextStyle(
                                      color: NeumorphicTheme.textSecondary,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w400,
                                    ),
                                  ),
                                  GestureDetector(
                                    onTap: _handleGoToLogin,
                                    child: const Text(
                                      'เข้าสู่ระบบ',
                                      style: TextStyle(
                                        color: Color(0xFF0284C7),
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

          // ปุ่มย้อนกลับ (Neumorphic Circle Back Button)
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.pop(context),
                child: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: NeumorphicTheme.baseColor,
                    shape: BoxShape.circle,
                    boxShadow: NeumorphicTheme.smallShadows(
                      distance: 4,
                      blur: 8,
                    ),
                  ),
                  child: const Icon(
                    Icons.arrow_back_ios_new,
                    color: NeumorphicTheme.textPrimary,
                    size: 18,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// วงกลม Neumorphic ลอยเป็นพื้นหลังตาม CSS .bg-circle
  Widget _buildBackgroundCircle(double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: NeumorphicTheme.baseColor,
        boxShadow: [
          BoxShadow(
            color: NeumorphicTheme.shadowDark.withValues(alpha: 0.55),
            offset: const Offset(15, 15),
            blurRadius: 30,
          ),
          const BoxShadow(
            color: NeumorphicTheme.shadowLight,
            offset: Offset(-15, -15),
            blurRadius: 30,
          ),
        ],
      ),
    );
  }

  Widget _buildFieldLabel(String label) {
    return Text(
      label,
      style: const TextStyle(
        color: NeumorphicTheme.textPrimary,
        fontWeight: FontWeight.w600,
        fontSize: 13,
      ),
    );
  }

  /// สร้างปุ่ม Social Login วงกลมนูนสไตล์ Neumorphic
  Widget _buildSocialButton(
    SocialProvider provider, {
    required VoidCallback onPressed,
  }) {
    Widget iconWidget;
    Color iconBgColor;

    switch (provider) {
      case SocialProvider.google:
        iconBgColor = Colors.white;
        iconWidget = _buildGoogleIcon();
        break;
      case SocialProvider.facebook:
        iconBgColor = const Color(0xFF1877F2);
        iconWidget = const Icon(Icons.facebook, color: Colors.white, size: 24);
        break;
      case SocialProvider.apple:
        iconBgColor = Colors.black;
        iconWidget = const Icon(Icons.apple, color: Colors.white, size: 24);
        break;
      default:
        iconBgColor = Colors.grey;
        iconWidget = const SizedBox.shrink();
    }

    return GestureDetector(
      onTap: _isLoading ? null : onPressed,
      child: Container(
        width: 50,
        height: 50,
        decoration: BoxDecoration(
          color: NeumorphicTheme.baseColor,
          shape: BoxShape.circle,
          boxShadow: NeumorphicTheme.smallShadows(distance: 4, blur: 8),
        ),
        child: Center(
          child: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: iconBgColor,
              shape: BoxShape.circle,
            ),
            child: Center(child: iconWidget),
          ),
        ),
      ),
    );
  }

  Widget _buildGoogleIcon() {
    return CustomPaint(size: const Size(22, 22), painter: _GoogleIconPainter());
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
      _phoneController.text.replaceAll('-', '').replaceAll(' ', ''),
    )) {
      _showSnackBar('รูปแบบเบอร์โทรศัพท์ไม่ถูกต้อง');
      return;
    }
    if (_emailController.text.isNotEmpty) {
      final emailRegex = RegExp(
        r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
      );
      if (!emailRegex.hasMatch(_emailController.text)) {
        _showSnackBar('รูปแบบอีเมลไม่ถูกต้อง');
        return;
      }
    }
    if (_passwordController.text.isEmpty) {
      _showSnackBar('กรุณากรอกรหัสผ่าน');
      return;
    }
    if (_passwordController.text.length < PasswordPolicy.minLength) {
      _showSnackBar(PasswordPolicy.minLengthMessage);
      return;
    }
    // หากช่องยืนยันถูกซ่อน แปลว่าผู้ใช้เลือกแสดงรหัสผ่านแล้ว
    // จึงไม่ต้องบังคับตรวจสอบรหัสซ้ำ
    if (_showConfirmPasswordField &&
        _passwordController.text != _confirmPasswordController.text) {
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
      final lastName = nameParts.length > 1
          ? nameParts.sublist(1).join(' ')
          : '';

      final phone = _phoneController.text.replaceAll(RegExp(r'[^0-9]'), '');

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
          'เกิดข้อผิดพลาด: ${e.toString().replaceAll('Exception: ', '')}',
        );
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
        backgroundColor: NeumorphicTheme.textPrimary,
      ),
    );
  }
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
