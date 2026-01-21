import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../../shared/widgets/tlz_logo.dart';
import '../../../../shared/widgets/tlz_text_field.dart';
import '../../../../shared/widgets/tlz_button.dart';
import '../widgets/social_login_button.dart';
import '../widgets/social_login_icon_button.dart';

/// Login Page
/// หน้าลงชื่อเข้าใช้พร้อม Social Login options
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage>
    with SingleTickerProviderStateMixin {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _obscurePassword = true;
  bool _isLoading = false;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutCubic,
    ));

    _animationController.forward();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppColors.background,
              AppColors.backgroundCream,
              AppColors.primaryLight.withOpacity(0.1),
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0), // เพิ่ม padding บนล่าง
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: SlideTransition(
                  position: _slideAnimation,
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Logo - ขนาดใหญ่ขึ้นตาม design
                        TlzLogo(
                          size: 1.8, // เพิ่มขนาดจาก 1.3 เป็น 1.8
                          showSubtitle: true,
                        ),
                        const SizedBox(height: 32), // ลด spacing จาก 48 เป็น 32

                        // Brand Name in Thai
                        Text(
                          'ทรีลอว์ซู',
                          textAlign: TextAlign.center,
                          style: AppTextStyles.heading2.copyWith(
                            color: AppColors.primary,
                            fontSize: 28, // เพิ่มขนาดตัวอักษร
                          ),
                        ),
                        const SizedBox(height: 6), // ลด spacing
                        Text(
                          'Tree Law Zoo',
                          textAlign: TextAlign.center,
                          style: AppTextStyles.bodyMedium.copyWith(
                            color: AppColors.textSecondary,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 40), // ลด spacing จาก 48 เป็น 40

                        // Email/Phone Field
                        TlzTextField(
                          label: 'อีเมล หรือ เบอร์โทรศัพท์',
                          hint: 'กรุณากรอกอีเมลหรือเบอร์โทรศัพท์',
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          prefixIcon: Icons.email_outlined,
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'กรุณากรอกอีเมลหรือเบอร์โทรศัพท์';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),

                        // Password Field
                        TlzTextField(
                          label: 'รหัสผ่าน',
                          hint: 'กรุณากรอกรหัสผ่าน',
                          controller: _passwordController,
                          obscureText: _obscurePassword,
                          prefixIcon: Icons.lock_outline,
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                              color: AppColors.textSecondary,
                            ),
                            onPressed: () {
                              setState(() {
                                _obscurePassword = !_obscurePassword;
                              });
                            },
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'กรุณากรอกรหัสผ่าน';
                            }
                            if (value.length < 6) {
                              return 'รหัสผ่านต้องมีอย่างน้อย 6 ตัวอักษร';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 24),

                        // Login Button
                        TlzButton(
                          text: 'ลงชื่อเข้าใช้',
                          type: TlzButtonType.primary,
                          size: TlzButtonSize.large,
                          isFullWidth: true,
                          isLoading: _isLoading,
                          onPressed: _handleLogin,
                        ),
                        const SizedBox(height: 28), // ลด spacing จาก 32 เป็น 28

                        // Divider with "หรือ"
                        Row(
                          children: [
                            Expanded(
                              child: Divider(
                                color: AppColors.divider,
                                thickness: 1,
                              ),
                            ),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 16),
                              child: Text(
                                'หรือ',
                                style: AppTextStyles.bodyMedium.copyWith(
                                  color: AppColors.textSecondary,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Divider(
                                color: AppColors.divider,
                                thickness: 1,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),

                        // Social Login Icons - แสดงในแถวเดียวกัน
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SocialLoginIconButton(
                              provider: SocialProvider.google,
                              isLoading: _isLoading,
                              size: 56,
                              onPressed: () => _handleSocialLogin(
                                SocialProvider.google,
                              ),
                            ),
                            const SizedBox(width: 12),
                            SocialLoginIconButton(
                              provider: SocialProvider.facebook,
                              isLoading: _isLoading,
                              size: 56,
                              onPressed: () => _handleSocialLogin(
                                SocialProvider.facebook,
                              ),
                            ),
                            const SizedBox(width: 12),
                            SocialLoginIconButton(
                              provider: SocialProvider.apple,
                              isLoading: _isLoading,
                              size: 56,
                              onPressed: () => _handleSocialLogin(
                                SocialProvider.apple,
                              ),
                            ),
                            const SizedBox(width: 12),
                            SocialLoginIconButton(
                              provider: SocialProvider.line,
                              isLoading: _isLoading,
                              size: 56,
                              onPressed: () => _handleSocialLogin(
                                SocialProvider.line,
                              ),
                            ),
                            const SizedBox(width: 12),
                            SocialLoginIconButton(
                              provider: SocialProvider.tiktok,
                              isLoading: _isLoading,
                              size: 56,
                              onPressed: () => _handleSocialLogin(
                                SocialProvider.tiktok,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),

                        // Forgot Password
                        TextButton(
                          onPressed: _handleForgotPassword,
                          child: Text(
                            'ลืมรหัสผ่าน?',
                            style: AppTextStyles.bodyMedium.copyWith(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),

                        const SizedBox(height: 16),

                        // Sign Up Link
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'ยังไม่มีบัญชี? ',
                              style: AppTextStyles.bodyMedium.copyWith(
                                color: AppColors.textSecondary,
                              ),
                            ),
                            TextButton(
                              onPressed: _handleSignUp,
                              style: TextButton.styleFrom(
                                padding: EdgeInsets.zero,
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: Text(
                                'สมัครสมาชิก',
                                style: AppTextStyles.bodyMedium.copyWith(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w600,
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
    );
  }

  void _handleLogin() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
      });

      // TODO: Implement login logic
      await Future.delayed(const Duration(seconds: 1));

      if (mounted) {
        setState(() {
          _isLoading = false;
        });

        // TODO: Navigate to home page after successful login
        // Navigator.pushReplacementNamed(context, '/home');
      }
    }
  }

  void _handleSocialLogin(SocialProvider provider) async {
    setState(() {
      _isLoading = true;
    });

    // TODO: Implement social login logic
    await Future.delayed(const Duration(seconds: 1));

    if (mounted) {
      setState(() {
        _isLoading = false;
      });

      // TODO: Navigate to home page after successful login
      // Navigator.pushReplacementNamed(context, '/home');
    }
  }

  void _handleForgotPassword() {
    // TODO: Navigate to forgot password page
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('ฟีเจอร์ลืมรหัสผ่านจะเปิดใช้งานเร็วๆ นี้'),
      ),
    );
  }

  void _handleSignUp() {
    // TODO: Navigate to sign up page
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('ฟีเจอร์สมัครสมาชิกจะเปิดใช้งานเร็วๆ นี้'),
      ),
    );
  }
}
