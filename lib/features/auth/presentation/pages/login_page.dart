import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../config/app_config.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../data/repositories/user_repository.dart';
import '../../data/services/social_auth_service.dart';
import '../widgets/social_login_button.dart';
import '../../../../services/auth_service.dart';

/// Login Page
/// หน้าลงชื่อเข้าใช้ - Dark Gold Theme ตามภาพตัวอย่าง
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage>
    with SingleTickerProviderStateMixin {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _obscurePassword = true;
  bool _isLoading = false;
  SocialProvider? _loadingProvider;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  // Services (nullable - may not be initialized if Supabase not configured)
  UserRepository? _userRepository;
  SocialAuthService? _socialAuthService;

  // Dark Gold Theme Colors
  static const Color _bgDark = Color(0xFF1A1200);
  static const Color _bgGold = Color(0xFF8B6000);
  static const Color _goldAccent = Color(0xFFF5A623);
  static const Color _goldBright = Color(0xFFFFBF00);
  static const Color _cardBg = Color(0xFFFFFDF5);

  @override
  void initState() {
    super.initState();

    if (AppConfig.isSupabaseConfigured) {
      try {
        final supabaseClient = Supabase.instance.client;
        _userRepository = UserRepository(supabaseClient);
        _socialAuthService = SocialAuthService(_userRepository!, supabaseClient);
      } catch (e) {
        debugPrint('LoginPage: Supabase not initialized - $e');
      }
    }

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
    _usernameController.dispose();
    _passwordController.dispose();
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

          // Subtle grid/glow overlay
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: MediaQuery.of(context).size.height * 0.55,
            child: CustomPaint(
              painter: _GlowGridPainter(),
            ),
          ),

          // Content
          SafeArea(
            child: Column(
              children: [
                // Top Section - Logo & Welcome
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // App Logo / Icon
                        Container(
                          width: 90,
                          height: 90,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: const RadialGradient(
                              colors: [Color(0xFFFFD700), Color(0xFFB8860B)],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: _goldAccent.withOpacity(0.5),
                                blurRadius: 24,
                                spreadRadius: 4,
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.local_hospital_rounded,
                            color: Colors.white,
                            size: 46,
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Welcome Text
                        Text(
                          'ยินดีต้อนรับ!',
                          style: AppTextStyles.heading2.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 28,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'เข้าสู่ระบบเพื่อเริ่มต้นใช้งาน',
                          style: AppTextStyles.bodyMedium.copyWith(
                            color: Colors.white.withOpacity(0.75),
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Bottom Card - Login Form
                FadeTransition(
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
                      padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Username/Phone Field
                            _buildFieldLabel('ชื่อผู้ใช้ / เบอร์โทรศัพท์'),
                            const SizedBox(height: 6),
                            _buildInputField(
                              controller: _usernameController,
                              hintText: 'กรอกชื่อผู้ใช้หรือเบอร์โทร',
                              prefixIcon: Icons.person_outline_rounded,
                              keyboardType: TextInputType.text,
                            ),
                            const SizedBox(height: 16),

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
                            const SizedBox(height: 28),

                            // Login Button - Gold
                            SizedBox(
                              height: 54,
                              child: ElevatedButton(
                                onPressed: _isLoading ? null : _handleLogin,
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
                                          valueColor: AlwaysStoppedAnimation<Color>(
                                            Colors.black54,
                                          ),
                                        ),
                                      )
                                    : Text(
                                        'เข้าสู่ระบบ',
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
                                  padding: const EdgeInsets.symmetric(horizontal: 12),
                                  child: Text(
                                    'หรือเข้าสู่ระบบด้วย',
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
                                  onPressed: () =>
                                      _handleSocialLogin(SocialProvider.google),
                                ),
                                const SizedBox(width: 14),
                                _buildSocialButton(
                                  SocialProvider.facebook,
                                  onPressed: () =>
                                      _handleSocialLogin(SocialProvider.facebook),
                                ),
                                const SizedBox(width: 14),
                                _buildSocialButton(
                                  SocialProvider.apple,
                                  onPressed: () =>
                                      _handleSocialLogin(SocialProvider.apple),
                                ),
                                const SizedBox(width: 14),
                                _buildSocialButton(
                                  SocialProvider.line,
                                  onPressed: () =>
                                      _handleSocialLogin(SocialProvider.line),
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),

                            // Register Link
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  'ยังไม่มีบัญชี? ',
                                  style: AppTextStyles.bodyMedium.copyWith(
                                    color: Colors.grey[600],
                                    fontSize: 14,
                                  ),
                                ),
                                GestureDetector(
                                  onTap: _handleSignUp,
                                  child: Text(
                                    'ลงทะเบียน',
                                    style: AppTextStyles.bodyMedium.copyWith(
                                      color: _goldAccent,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                          ],
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
                onTap: () {
                  if (Navigator.of(context).canPop()) {
                    Navigator.of(context).pop();
                  } else {
                    Navigator.pushReplacementNamed(context, '/');
                  }
                },
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
        iconWidget = const Icon(Icons.facebook, color: Colors.white, size: 26);
        break;
      case SocialProvider.apple:
        backgroundColor = Colors.black;
        borderColor = null;
        iconWidget = const Icon(Icons.apple, color: Colors.white, size: 26);
        break;
      case SocialProvider.line:
        backgroundColor = const Color(0xFF00C300);
        borderColor = null;
        iconWidget = const Text(
          'L',
          style: TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        );
        break;
      case SocialProvider.tiktok:
        backgroundColor = Colors.black;
        borderColor = null;
        iconWidget = const Text(
          'T',
          style: TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        );
        break;
    }

    final isLoadingThis = _isLoading && _loadingProvider == provider;

    return InkWell(
      onTap: _isLoading ? null : onPressed,
      borderRadius: BorderRadius.circular(26),
      child: Container(
        width: 52,
        height: 52,
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
        child: Center(
          child: isLoadingThis
              ? SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      provider == SocialProvider.google
                          ? _goldAccent
                          : Colors.white,
                    ),
                  ),
                )
              : iconWidget,
        ),
      ),
    );
  }

  Widget _buildGoogleIcon() {
    return CustomPaint(
      size: const Size(26, 26),
      painter: _GoogleIconPainter(),
    );
  }

  void _handleLogin() async {
    if (_userRepository == null) {
      _showSnackBar('ระบบยังไม่พร้อมใช้งาน (Supabase not configured)');
      return;
    }

    if (_usernameController.text.isEmpty) {
      _showSnackBar('กรุณากรอกชื่อผู้ใช้หรือเบอร์โทรศัพท์');
      return;
    }
    if (_passwordController.text.isEmpty) {
      _showSnackBar('กรุณากรอกรหัสผ่าน');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final user = await _userRepository!.login(
        _usernameController.text.trim(),
        _passwordController.text,
      );

      if (!mounted) return;

      if (user != null) {
        AuthService.instance.login(user);
        _showSnackBar('เข้าสู่ระบบสำเร็จ');
        await Future.delayed(const Duration(milliseconds: 500));

        if (!mounted) return;
        setState(() {
          _isLoading = false;
        });

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final args = ModalRoute.of(context)?.settings.arguments;

          if (args is String && args.isNotEmpty) {
            Navigator.pushReplacementNamed(context, args);
          } else if (args is Map<String, dynamic>) {
            final route = args['route'] as String?;
            final routeArgs = args['arguments'];
            if (route != null) {
              Navigator.pushReplacementNamed(context, route, arguments: routeArgs);
            } else {
              Navigator.pop(context);
            }
          } else if (Navigator.canPop(context)) {
            Navigator.pop(context);
          } else {
            Navigator.pushReplacementNamed(context, '/');
          }
        });
      } else {
        _showSnackBar('ชื่อผู้ใช้หรือรหัสผ่านไม่ถูกต้อง');
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      debugPrint('Login error: $e');
      if (mounted) {
        _showSnackBar('เกิดข้อผิดพลาดในการเข้าสู่ระบบ');
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _handleSocialLogin(SocialProvider provider) async {
    if (_socialAuthService == null) {
      _showSnackBar('ระบบยังไม่พร้อมใช้งาน (Supabase not configured)');
      return;
    }

    setState(() {
      _isLoading = true;
      _loadingProvider = provider;
    });

    try {
      SocialAuthResult result;

      switch (provider) {
        case SocialProvider.google:
          result = await _socialAuthService!.signInWithGoogle();
          break;
        case SocialProvider.facebook:
          result = await _socialAuthService!.signInWithFacebook();
          break;
        case SocialProvider.apple:
          result = await _socialAuthService!.signInWithApple();
          break;
        case SocialProvider.line:
          result = await _socialAuthService!.signInWithLine();
          break;
        case SocialProvider.tiktok:
          result = await _socialAuthService!.signInWithTikTok();
          break;
      }

      if (!mounted) return;

      if (result.success && result.user != null) {
        AuthService.instance.login(result.user!);

        if (result.isNewUser) {
          _showSnackBar('ยินดีต้อนรับ ${result.user!.fullName}');
        } else {
          _showSnackBar('เข้าสู่ระบบสำเร็จ');
        }

        await Future.delayed(const Duration(milliseconds: 500));

        if (!mounted) return;
        setState(() {
          _isLoading = false;
          _loadingProvider = null;
        });

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final redirectRoute =
              ModalRoute.of(context)?.settings.arguments as String?;

          if (redirectRoute != null && redirectRoute.isNotEmpty) {
            Navigator.pushReplacementNamed(context, redirectRoute);
          } else if (Navigator.canPop(context)) {
            Navigator.pop(context);
          } else {
            Navigator.pushReplacementNamed(context, '/');
          }
        });
      } else {
        _showSnackBar(result.errorMessage ?? 'เกิดข้อผิดพลาด');
        if (mounted) {
          setState(() {
            _isLoading = false;
            _loadingProvider = null;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar('เกิดข้อผิดพลาดในการเข้าสู่ระบบ');
        setState(() {
          _isLoading = false;
          _loadingProvider = null;
        });
      }
    }
  }

  void _handleSignUp() {
    Navigator.pushNamed(context, '/register');
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

    // Center glow
    final glowPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFFFFBF00).withOpacity(0.15),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(
        center: Offset(size.width / 2, size.height * 0.4),
        radius: size.width * 0.6,
      ));
    canvas.drawCircle(
      Offset(size.width / 2, size.height * 0.4),
      size.width * 0.6,
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
