import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../config/app_config.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../../shared/widgets/tlz_text_field.dart';
import '../../data/repositories/user_repository.dart';
import '../../data/services/social_auth_service.dart';
import '../widgets/social_login_button.dart';
import '../../../../services/auth_service.dart';

/// Login Page
/// หน้าลงชื่อเข้าใช้ตาม UI Design - พื้นหลังเขียว + Card ขาวด้านล่าง
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

  @override
  void initState() {
    super.initState();

    // Initialize services (only if Supabase is configured)
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
      duration: const Duration(milliseconds: 600),
    );

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.2),
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
      backgroundColor: AppColors.primary,
      body: Stack(
        children: [
          // Content
          SafeArea(
            child: CustomScrollView(
              slivers: [
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Column(
                    children: [
                      // Spacer to push card to bottom
                      const Spacer(),
      
                      // Bottom Card - Login Form
                      FadeTransition(
                        opacity: _fadeAnimation,
                        child: SlideTransition(
                          position: _slideAnimation,
                          child: Container(
                            width: double.infinity,
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.only(
                                topLeft: Radius.circular(32),
                                topRight: Radius.circular(32),
                              ),
                            ),
                            padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
                            child: Form(
                              key: _formKey,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // Title
                                  Text(
                                    'ลงชื่อเข้าใช้',
                                    textAlign: TextAlign.center,
                                    style: AppTextStyles.heading3.copyWith(
                                      color: AppColors.textPrimary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 32),
      
                                  // Username/Phone Field
                                  _buildInputField(
                                    controller: _usernameController,
                                    hintText: 'ชื่อผู้ใช้ หรือ เบอร์โทรศัพท์',
                                    prefixIcon: Icons.person_outline,
                                    keyboardType: TextInputType.text,
                                  ),
                                  const SizedBox(height: 16),
      
                                  // Password Field
                                  _buildInputField(
                                    controller: _passwordController,
                                    hintText: 'รหัสผ่าน',
                                    prefixIcon: Icons.lock_outline,
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
                                        color: AppColors.textHint,
                                        size: 22,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 24),
      
                                  // Submit Button - BLACK
                                  SizedBox(
                                    height: 52,
                                    child: ElevatedButton(
                                      onPressed: _isLoading ? null : _handleLogin,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.black,
                                        foregroundColor: Colors.white,
                                        disabledBackgroundColor: Colors.grey[400],
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(26),
                                        ),
                                        elevation: 0,
                                      ),
                                      child: _isLoading
                                          ? const SizedBox(
                                              width: 24,
                                              height: 24,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2.5,
                                                valueColor: AlwaysStoppedAnimation<Color>(
                                                  Colors.white,
                                                ),
                                              ),
                                            )
                                          : Text(
                                              'ตกลง',
                                              style: AppTextStyles.button.copyWith(
                                                color: Colors.white,
                                                fontSize: 18,
                                              ),
                                            ),
                                    ),
                                  ),
                                  const SizedBox(height: 24),
      
                                  // Divider with "หรือ"
                                  Text(
                                    'หรือ',
                                    textAlign: TextAlign.center,
                                    style: AppTextStyles.bodyMedium.copyWith(
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                  const SizedBox(height: 20),
      
                                  // Social Login Icons
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      _buildSocialButton(
                                        SocialProvider.google,
                                        onPressed: () =>
                                            _handleSocialLogin(SocialProvider.google),
                                      ),
                                      const SizedBox(width: 12),
                                      _buildSocialButton(
                                        SocialProvider.facebook,
                                        onPressed: () =>
                                            _handleSocialLogin(SocialProvider.facebook),
                                      ),
                                      const SizedBox(width: 12),
                                      _buildSocialButton(
                                        SocialProvider.apple,
                                        onPressed: () =>
                                            _handleSocialLogin(SocialProvider.apple),
                                      ),
                                      const SizedBox(width: 12),
                                      _buildSocialButton(
                                        SocialProvider.line,
                                        onPressed: () =>
                                            _handleSocialLogin(SocialProvider.line),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 24),
      
                                  // Register Link
                                  TextButton(
                                    onPressed: _handleSignUp,
                                    child: Text(
                                      'ลงทะเบียนสำหรับผู้ใช้ใหม่',
                                      style: AppTextStyles.bodyMedium.copyWith(
                                        color: AppColors.warning,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
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
              ],
            ),
          ),

          // Top Header - Back Button (Absolute Position)
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
                    size: 24,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Build custom input field with green border
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
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: AppColors.primary,
          width: 1.5,
        ),
      ),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        obscureText: obscureText,
        style: AppTextStyles.bodyMedium.copyWith(
          color: AppColors.textPrimary,
        ),
        decoration: InputDecoration(
          hintText: hintText,
          hintStyle: AppTextStyles.bodyMedium.copyWith(
            color: AppColors.textHint,
          ),
          prefixIcon: Icon(
            prefixIcon,
            color: AppColors.primary,
            size: 24,
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
    Color iconColor = Colors.white;

    switch (provider) {
      case SocialProvider.google:
        backgroundColor = Colors.white;
        borderColor = AppColors.border;
        iconWidget = _buildGoogleIcon();
        break;
      case SocialProvider.facebook:
        backgroundColor = const Color(0xFF1877F2);
        borderColor = null;
        iconWidget = const Icon(
          Icons.facebook,
          color: Colors.white,
          size: 28,
        );
        break;
      case SocialProvider.apple:
        backgroundColor = Colors.black;
        borderColor = null;
        iconWidget = const Icon(
          Icons.apple,
          color: Colors.white,
          size: 28,
        );
        break;
      case SocialProvider.line:
        backgroundColor = const Color(0xFF00C300);
        borderColor = null;
        iconWidget = const Text(
          'L',
          style: TextStyle(
            color: Colors.white,
            fontSize: 24,
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
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        );
        break;
    }

    final isLoadingThis = _isLoading && _loadingProvider == provider;

    return InkWell(
      onTap: _isLoading ? null : onPressed,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(12),
          border: borderColor != null
              ? Border.all(color: borderColor, width: 1)
              : null,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Center(
          child: isLoadingThis
              ? SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      provider == SocialProvider.google
                          ? AppColors.primary
                          : Colors.white,
                    ),
                  ),
                )
              : iconWidget,
        ),
      ),
    );
  }

  /// Build Google "G" icon with colors
  Widget _buildGoogleIcon() {
    return CustomPaint(
      size: const Size(28, 28),
      painter: _GoogleIconPainter(),
    );
  }

  void _handleLogin() async {
    // Check if Supabase is configured
    if (_userRepository == null) {
      _showSnackBar('ระบบยังไม่พร้อมใช้งาน (Supabase not configured)');
      return;
    }

    // Basic validation
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
        // Save user session
        AuthService.instance.login(user);
        
        // Login successful
        _showSnackBar('เข้าสู่ระบบสำเร็จ');
        
        // Wait a bit for SnackBar to show before navigating
        await Future.delayed(const Duration(milliseconds: 500));
        
        if (!mounted) return;
        
        // Set loading to false BEFORE navigation
        setState(() {
          _isLoading = false;
        });
        
        // Use addPostFrameCallback to ensure Navigator is ready
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          
          // Get the redirect argument if it exists
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
            // If no redirect but can pop, go back to previous page
            Navigator.pop(context);
          } else {
            // Default: go to home page
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
    // Check if Supabase is configured
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
        // Save user session
        AuthService.instance.login(result.user!);

        if (result.isNewUser) {
          _showSnackBar('ยินดีต้อนรับ ${result.user!.fullName}');
        } else {
          _showSnackBar('เข้าสู่ระบบสำเร็จ');
        }
        
        // Wait a bit for SnackBar to show before navigating
        await Future.delayed(const Duration(milliseconds: 500));
        
        if (!mounted) return;
        
        // Set loading to false BEFORE navigation
        setState(() {
          _isLoading = false;
          _loadingProvider = null;
        });
        
        // Use addPostFrameCallback to ensure Navigator is ready
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          
          // Get the redirect argument if it exists
          final redirectRoute = ModalRoute.of(context)?.settings.arguments as String?;
          
          if (redirectRoute != null && redirectRoute.isNotEmpty) {
            // If there's a redirect route, go there and replace the login page
            Navigator.pushReplacementNamed(context, redirectRoute);
          } else if (Navigator.canPop(context)) {
            // If no redirect but can pop, go back to previous page
            Navigator.pop(context);
          } else {
            // Default: go to home page
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

    // Colors
    const red = Color(0xFFEA4335);
    const yellow = Color(0xFFFBBC05);
    const green = Color(0xFF34A853);
    const blue = Color(0xFF4285F4);

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.15
      ..strokeCap = StrokeCap.butt;

    // Draw colored arcs
    // Red (top)
    paint.color = red;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -2.4, // Start angle
      0.8, // Sweep angle
      false,
      paint,
    );

    // Yellow (left)
    paint.color = yellow;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      2.0,
      1.0,
      false,
      paint,
    );

    // Green (bottom)
    paint.color = green;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      0.7,
      1.3,
      false,
      paint,
    );

    // Blue (right) with horizontal bar
    paint.color = blue;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -1.6,
      1.2,
      false,
      paint,
    );

    // Blue horizontal bar
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
