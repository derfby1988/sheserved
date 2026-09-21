import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../config/app_config.dart';
import '../../data/repositories/user_repository.dart';
import '../../data/services/social_auth_service.dart';
import '../widgets/social_login_button.dart';
import '../../../../services/auth_service.dart';
import '../../../../shared/widgets/widgets.dart';

/// Login Page
/// หน้าลงชื่อเข้าใช้ - ออกแบบ UI และ UX ใหม่ในสไตล์ Neumorphism ตามรูปต้นฉบับ
class LoginPage extends StatefulWidget {
  final UserRepository? userRepository;

  const LoginPage({super.key, this.userRepository});

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
  int _failedLoginAttempts = 0;
  DateTime? _loginCooldownUntil;
  Timer? _loginCooldownTimer;
  int _loginCooldownRemainingSeconds = 0;
  SocialProvider? _loadingProvider;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  // Services (nullable - may not be initialized if Supabase not configured)
  UserRepository? _userRepository;
  SocialAuthService? _socialAuthService;

  @override
  void initState() {
    super.initState();

    if (widget.userRepository != null) {
      _userRepository = widget.userRepository;
    } else if (AppConfig.isSupabaseConfigured) {
      try {
        final supabaseClient = Supabase.instance.client;
        _userRepository = UserRepository(supabaseClient);
        _socialAuthService = SocialAuthService(
          _userRepository!,
          supabaseClient,
        );
      } catch (e) {
        debugPrint('LoginPage: Supabase not initialized - $e');
      }
    }

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
    _loginCooldownTimer?.cancel();
    _usernameController.dispose();
    _passwordController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NeumorphicTheme.baseColor,
      body: Stack(
        children: [
          // 1. วงกลม Neumorphic ลอยเป็นพื้นหลังตาม CSS .bg-circle ในภาพต้นฉบับ
          Positioned(
            top: -60,
            left: -60,
            child: Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: NeumorphicTheme.baseColor,
                boxShadow: [
                  BoxShadow(
                    color: NeumorphicTheme.shadowDark.withValues(alpha: 0.55),
                    offset: const Offset(15, 15),
                    blurRadius: 30,
                  ),
                  BoxShadow(
                    color: NeumorphicTheme.shadowLight,
                    offset: const Offset(-15, -15),
                    blurRadius: 30,
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            bottom: -70,
            right: -70,
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: NeumorphicTheme.baseColor,
                boxShadow: [
                  BoxShadow(
                    color: NeumorphicTheme.shadowDark.withValues(alpha: 0.55),
                    offset: const Offset(15, 15),
                    blurRadius: 30,
                  ),
                  BoxShadow(
                    color: NeumorphicTheme.shadowLight,
                    offset: const Offset(-15, -15),
                    blurRadius: 30,
                  ),
                ],
              ),
            ),
          ),

          // 2. เนื้อหาหลัก - การ์ด Neumorphic Form Panel
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: FadeTransition(
                    opacity: _fadeAnimation,
                    child: SlideTransition(
                      position: _slideAnimation,
                      child: NeumorphicContainer(
                        color: NeumorphicTheme.baseColor,
                        // ค่าตาม CSS .form-panel { border-radius: 35px; padding: 40px 38px; }
                        borderRadius: 35.0,
                        depth: 20.0,
                        blur: 40.0,
                        padding: const EdgeInsets.fromLTRB(30, 36, 30, 30),
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
                              const SizedBox(height: 20),

                              // หัวข้อ "ยินดีต้อนรับ!"
                              const Text(
                                'ยินดีต้อนรับ!',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w800,
                                  color: NeumorphicTheme.textPrimary,
                                  letterSpacing: -0.2,
                                ),
                              ),
                              const SizedBox(height: 6),

                              // คำอธิบายรอง "เข้าสู่ระบบเพื่อเริ่มต้นใช้งาน"
                              const Text(
                                'เข้าสู่ระบบเพื่อเริ่มต้นใช้งาน',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w400,
                                  color: NeumorphicTheme.textSecondary,
                                ),
                              ),
                              const SizedBox(height: 26),

                              // ฟิลด์ชื่อผู้ใช้ / เบอร์โทรศัพท์ (Neumorphic Input)
                              _buildFieldLabel('ชื่อผู้ใช้ / เบอร์โทรศัพท์'),
                              const SizedBox(height: 8),
                              NeumorphicInputField(
                                controller: _usernameController,
                                hintText: 'กรอกชื่อผู้ใช้หรือเบอร์โทร',
                                prefixIcon: Icons.person_outline_rounded,
                                keyboardType: TextInputType.text,
                                textInputAction: TextInputAction.next,
                                onSubmitted: (_) {
                                  FocusScope.of(context).nextFocus();
                                },
                              ),
                              const SizedBox(height: 18),

                              // ฟิลด์รหัสผ่าน (Neumorphic Input)
                              _buildFieldLabel('รหัสผ่าน'),
                              const SizedBox(height: 8),
                              NeumorphicInputField(
                                controller: _passwordController,
                                hintText: '••••••••',
                                prefixIcon: Icons.lock_outline_rounded,
                                obscureText: _obscurePassword,
                                textInputAction: TextInputAction.done,
                                onSubmitted: (_) {
                                  if (_isLoading || _isLoginCooldownActive) return;
                                  _handleLogin();
                                },
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
                              const SizedBox(height: 28),

                              // ปุ่มเข้าสู่ระบบ (Vibrant Gradient Pill Button แบบ Neumorphic)
                              NeumorphicVerifyButton(
                                key: const Key('login_submit'),
                                text: _isLoginCooldownActive
                                    ? 'รอ $_loginCooldownRemainingSeconds วิ'
                                    : 'เข้าสู่ระบบ',
                                isLoading: _isLoading,
                                isEnabled: !_isLoading && !_isLoginCooldownActive,
                                onPressed: _handleLogin,
                              ),
                              const SizedBox(height: 24),

                              // เส้นคั่น "หรือเข้าสู่ระบบด้วย"
                              Row(
                                children: [
                                  Expanded(
                                    child: Container(
                                      height: 1,
                                      color: const Color(0xFFCBD5E1),
                                    ),
                                  ),
                                  const Padding(
                                    padding: EdgeInsets.symmetric(horizontal: 12),
                                    child: Text(
                                      'หรือเข้าสู่ระบบด้วย',
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
                                    onPressed: () => _handleSocialLogin(
                                      SocialProvider.google,
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  _buildSocialButton(
                                    SocialProvider.facebook,
                                    onPressed: () => _handleSocialLogin(
                                      SocialProvider.facebook,
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  _buildSocialButton(
                                    SocialProvider.apple,
                                    onPressed: () => _handleSocialLogin(
                                      SocialProvider.apple,
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  _buildSocialButton(
                                    SocialProvider.line,
                                    onPressed: () => _handleSocialLogin(
                                      SocialProvider.line,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 24),

                              // ลิงก์ลงทะเบียน (สไตล์เดียวกับ Resend OTP ในภาพ)
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Text(
                                    'ยังไม่มีบัญชี? ',
                                    style: TextStyle(
                                      color: NeumorphicTheme.textSecondary,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w400,
                                    ),
                                  ),
                                  GestureDetector(
                                    onTap: _handleSignUp,
                                    child: const Text(
                                      'ลงทะเบียน',
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
                onTap: () {
                  if (Navigator.of(context).canPop()) {
                    Navigator.of(context).pop();
                  } else {
                    Navigator.pushReplacementNamed(context, '/');
                  }
                },
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
      case SocialProvider.line:
        iconBgColor = const Color(0xFF00C300);
        iconWidget = const Text(
          'L',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        );
        break;
      case SocialProvider.tiktok:
        iconBgColor = Colors.black;
        iconWidget = const Text(
          'T',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        );
        break;
    }

    final isLoadingThis = _isLoading && _loadingProvider == provider;

    return GestureDetector(
      onTap: _isLoading ? null : onPressed,
      child: Container(
        width: 50,
        height: 50,
        decoration: BoxDecoration(
          color: NeumorphicTheme.baseColor,
          shape: BoxShape.circle,
          boxShadow: NeumorphicTheme.smallShadows(
            distance: 4,
            blur: 8,
          ),
        ),
        child: Center(
          child: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: iconBgColor,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: isLoadingThis
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : iconWidget,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGoogleIcon() {
    return CustomPaint(size: const Size(22, 22), painter: _GoogleIconPainter());
  }

  bool get _isLoginCooldownActive =>
      _loginCooldownUntil != null && _loginCooldownRemainingSeconds > 0;

  void _startLoginCooldownTimer() {
    _loginCooldownTimer?.cancel();
    _loginCooldownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;

      if (_loginCooldownRemainingSeconds <= 1) {
        _loginCooldownTimer?.cancel();
        setState(() {
          _loginCooldownUntil = null;
          _loginCooldownRemainingSeconds = 0;
          _failedLoginAttempts = 0;
        });
      } else {
        setState(() => _loginCooldownRemainingSeconds--);
      }
    });
  }

  bool _recordFailedLogin() {
    final nextAttempt = _failedLoginAttempts + 1;
    final shouldStartCooldown = nextAttempt >= 3;

    setState(() {
      _failedLoginAttempts = nextAttempt;
      if (shouldStartCooldown) {
        _loginCooldownUntil = DateTime.now().add(const Duration(seconds: 30));
        _loginCooldownRemainingSeconds = 30;
      }
    });

    if (shouldStartCooldown) {
      _startLoginCooldownTimer();
    }
    return shouldStartCooldown;
  }

  void _resetFailedLoginAttempts() {
    _loginCooldownTimer?.cancel();
    _loginCooldownTimer = null;
    _failedLoginAttempts = 0;
    _loginCooldownUntil = null;
    _loginCooldownRemainingSeconds = 0;
  }

  void _handleLogin() async {
    if (_isLoginCooldownActive) {
      return;
    }
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
      debugPrint('LoginPage: calling _userRepository.login()');
      final user = await _userRepository!.login(
        _usernameController.text.trim(),
        _passwordController.text,
      );
      debugPrint('LoginPage: _userRepository.login() returned user=${user != null}');

      if (!mounted) return;

      if (user != null) {
        _resetFailedLoginAttempts();
        debugPrint('LoginPage: calling AuthService.instance.login()');
        await AuthService.instance.login(user).timeout(
          const Duration(seconds: 3),
          onTimeout: () {
            debugPrint('LoginPage: AuthService.login() timeout! Proceeding anyway.');
          },
        );
        debugPrint('LoginPage: AuthService.instance.login() completed');
        if (mounted) _showSnackBar('เข้าสู่ระบบสำเร็จ');

        if (!mounted) return;
        setState(() {
          _isLoading = false;
        });
        debugPrint('LoginPage: _isLoading set to false');

        debugPrint('LoginPage: scheduling navigation');
        WidgetsBinding.instance.addPostFrameCallback((_) {
          try {
            if (!mounted) {
              debugPrint('LoginPage: not mounted, skipping navigation');
              return;
            }
            final args = ModalRoute.of(context)?.settings.arguments;
            debugPrint('LoginPage: args = $args');
            if (args is Map<String, dynamic>) {
              if (args['returnAfterLogin'] == true) {
                debugPrint('LoginPage: returnAfterLogin, popping back');
                Navigator.pop(context);
                return;
              }
              final String? target = args['redirect'] ?? args['route'];
              final dynamic targetArgs = args['args'] ?? args['arguments'];
              if (target != null) {
                debugPrint('LoginPage: navigating to $target');
                Navigator.pushReplacementNamed(context, target, arguments: targetArgs);
              } else {
                debugPrint('LoginPage: no target, going to /');
                Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
              }
            } else if (args is String) {
              debugPrint('LoginPage: navigating to $args');
              Navigator.pushReplacementNamed(context, args);
            } else {
              debugPrint('LoginPage: no args, going to /');
              Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
            }
          } catch (e, stack) {
            debugPrint('LoginPage navigation error: $e');
            debugPrint(stack.toString());
          }
        });
      } else {
        final cooldownStarted = _recordFailedLogin();
        if (!cooldownStarted) {
          _showSnackBar('ชื่อผู้ใช้หรือรหัสผ่านไม่ถูกต้อง');
        }
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      debugPrint('LoginPage: login request failed (${e.runtimeType})');
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
        debugPrint('LoginPage: social calling AuthService.instance.login()');
        await AuthService.instance.login(result.user!).timeout(
          const Duration(seconds: 3),
          onTimeout: () {
            debugPrint('LoginPage: social AuthService.login() timeout! Proceeding anyway.');
          },
        );
        debugPrint('LoginPage: social AuthService.instance.login() completed');

        if (mounted) {
          if (result.isNewUser) {
            _showSnackBar('ยินดีต้อนรับ ${result.user!.fullName}');
          } else {
            _showSnackBar('เข้าสู่ระบบสำเร็จ');
          }
        }

        if (!mounted) return;
        setState(() {
          _isLoading = false;
          _loadingProvider = null;
        });
        debugPrint('LoginPage: social _isLoading set to false');

        debugPrint('LoginPage: Social login success, scheduling navigation');
        WidgetsBinding.instance.addPostFrameCallback((_) {
          try {
            if (!mounted) {
              debugPrint('LoginPage: not mounted, skipping navigation');
              return;
            }
            final args = ModalRoute.of(context)?.settings.arguments;
            debugPrint('LoginPage: social args = $args');
            if (args is Map<String, dynamic>) {
              if (args['returnAfterLogin'] == true) {
                debugPrint('LoginPage: social returnAfterLogin, popping back');
                Navigator.pop(context);
                return;
              }
              final String? target = args['redirect'] ?? args['route'];
              final dynamic targetArgs = args['args'] ?? args['arguments'];
              if (target != null) {
                debugPrint('LoginPage: navigating to $target');
                Navigator.pushReplacementNamed(context, target, arguments: targetArgs);
              } else {
                debugPrint('LoginPage: no target, going to /');
                Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
              }
            } else if (args is String) {
              debugPrint('LoginPage: navigating to $args');
              Navigator.pushReplacementNamed(context, args);
            } else {
              debugPrint('LoginPage: no args, going to /');
              Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
            }
          } catch (e, stack) {
            debugPrint('LoginPage social navigation error: $e');
            debugPrint(stack.toString());
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
        backgroundColor: const Color(0xFF1E293B),
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
