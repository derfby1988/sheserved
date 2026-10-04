import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../../core/constants/password_policy.dart';
import '../../../auth/data/models/password_change_result.dart';
import '../../../auth/data/repositories/user_repository.dart';
import '../../../../shared/widgets/neumorphic/neumorphic.dart';
import '../../../../shared/widgets/tlz_button.dart';

/// Bottom Sheet สำหรับเปลี่ยนรหัสผ่านของผู้ใช้ปัจจุบัน
///
/// รองรับโหมดซ่อน/แสดงรหัสผ่าน กรอกยืนยันรหัสผ่านซ้ำ และ cooldown
/// ป้องกัน brute-force ของรหัสผ่านเดิมในระดับ client (30 วินาทีหลังผิด 3 ครั้ง)
class ChangePasswordBottomSheet extends StatefulWidget {
  final UserRepository? userRepository;

  const ChangePasswordBottomSheet({super.key, this.userRepository});

  @override
  State<ChangePasswordBottomSheet> createState() =>
      _ChangePasswordBottomSheetState();
}

class _ChangePasswordBottomSheetState extends State<ChangePasswordBottomSheet> {
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _obscureCurrentPassword = true;
  bool _obscureNewPassword = true;
  bool _obscureConfirmPassword = true;

  /// โหมดแสดงรหัสผ่าน (global) — true แล้วซ่อนช่องยืนยัน
  bool _isPasswordVisibleMode = false;

  bool _isChangingPassword = false;
  String? _errorMessage;

  // Brute-force cooldown state
  int _currentPasswordFailCount = 0;
  DateTime? _cooldownUntil;
  Timer? _cooldownTimer;
  int _cooldownRemainingSeconds = 0;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _startCooldownTicker() {
    _cooldownTimer?.cancel();
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;

      if (_cooldownRemainingSeconds <= 1) {
        _cooldownTimer?.cancel();
        setState(() {
          _cooldownUntil = null;
          _cooldownRemainingSeconds = 0;
          _currentPasswordFailCount = 0;
          _errorMessage = null;
        });
      } else {
        setState(() => _cooldownRemainingSeconds--);
      }
    });
  }

  bool get _isCooldownActive =>
      _cooldownUntil != null && _cooldownRemainingSeconds > 0;

  void _setError(String? message) {
    if (!mounted) return;
    setState(() => _errorMessage = message);
  }

  String? _validate() {
    final currentPassword = _currentPasswordController.text.trim();
    final newPassword = _newPasswordController.text;
    final confirmPassword = _confirmPasswordController.text;

    if (currentPassword.isEmpty) {
      return 'กรุณากรอกรหัสผ่านปัจจุบัน';
    }
    if (newPassword.isEmpty) {
      return 'กรุณากรอกรหัสผ่านใหม่';
    }
    if (newPassword.length < PasswordPolicy.minLength) {
      return PasswordPolicy.minLengthMessage;
    }
    if (newPassword == currentPassword) {
      return 'รหัสผ่านใหม่ต้องไม่ซ้ำกับรหัสผ่านเดิม';
    }
    if (!_isPasswordVisibleMode) {
      if (confirmPassword.isEmpty) {
        return 'กรุณายืนยันรหัสผ่านใหม่';
      }
      if (confirmPassword != newPassword) {
        return 'รหัสผ่านใหม่และการยืนยันไม่ตรงกัน';
      }
    }

    return null;
  }

  void _toggleNewPasswordVisibility() {
    setState(() {
      _isPasswordVisibleMode = !_isPasswordVisibleMode;
      _obscureNewPassword = !_obscureNewPassword;
    });
  }

  void _incrementFailCount() {
    final nextFailCount = _currentPasswordFailCount + 1;
    final shouldStartCooldown = nextFailCount >= 3;
    final cooldownUntil = shouldStartCooldown
        ? DateTime.now().add(const Duration(seconds: 30))
        : null;

    setState(() {
      _currentPasswordFailCount = nextFailCount;
      if (cooldownUntil != null) {
        _cooldownUntil = cooldownUntil;
        _cooldownRemainingSeconds = 30;
        _errorMessage = null;
      } else {
        _errorMessage = 'รหัสผ่านปัจจุบันไม่ถูกต้อง';
      }
    });

    if (shouldStartCooldown) {
      _startCooldownTicker();
    }
    if (kDebugMode) {
      debugPrint(
        'ChangePasswordBottomSheet: current-password failure '
        '#$nextFailCount, cooldown=$_isCooldownActive',
      );
    }
  }

  Future<void> _handleSubmit() async {
    if (_isCooldownActive) {
      return;
    }

    final validationError = _validate();
    if (validationError != null) {
      _setError(validationError);
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _isChangingPassword = true;
      _errorMessage = null;
    });

    final repository = widget.userRepository ?? UserRepository(Supabase.instance.client);
    PasswordChangeResult result;
    try {
      result = await repository.changeCurrentUserPassword(
        currentPassword: _currentPasswordController.text.trim(),
        newPassword: _newPasswordController.text,
      );
    } catch (_) {
      if (!mounted) return;
      if (kDebugMode) {
        debugPrint('ChangePasswordBottomSheet: password change request failed');
      }
      setState(() {
        _isChangingPassword = false;
        _errorMessage = 'ไม่สามารถเปลี่ยนรหัสผ่านได้ กรุณาลองใหม่';
      });
      return;
    }

    if (!mounted) return;

    if (kDebugMode) {
      debugPrint('ChangePasswordBottomSheet: repository result=$result');
    }
    setState(() => _isChangingPassword = false);

    switch (result) {
      case PasswordChangeResult.success:
        Navigator.of(context).pop(PasswordChangeResult.success);
        break;
      case PasswordChangeResult.currentPasswordIncorrect:
        _incrementFailCount();
        break;
      case PasswordChangeResult.invalidPassword:
        _setError('รหัสผ่านใหม่ไม่ถูกต้อง');
        break;
      case PasswordChangeResult.unauthorized:
        _setError('กรุณาเข้าสู่ระบบก่อนเปลี่ยนรหัสผ่าน');
        break;
      case PasswordChangeResult.unsupportedOffline:
        _setError('ฟีเจอร์นี้ต้องเชื่อมต่ออินเทอร์เน็ต ไม่รองรับในโหมด Offline');
        break;
      case PasswordChangeResult.socialAccountNoPassword:
        _setError('บัญชีนี้ยังไม่ได้ตั้งรหัสผ่าน');
        break;
      case PasswordChangeResult.tooManyAttempts:
      case PasswordChangeResult.failed:
        _setError('ไม่สามารถเปลี่ยนรหัสผ่านได้ กรุณาลองใหม่');
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets;

    // PopScope กันการปิด sheet (ปัด/แตะพื้นหลัง/ปุ่ม back) ระหว่าง request
    // เทียบเท่า isDismissible:false + enableDrag:false แบบ dynamic (§3 R3)
    return PopScope(
      canPop: !_isChangingPassword,
      child: Padding(
        padding: EdgeInsets.only(bottom: viewInsets.bottom),
        child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Center(child: NeumorphicSheetDragHandle()),
            const SizedBox(height: 16),

            // Header: badge ไอคอนนูน + หัวข้อ + ปุ่มปิด
            Row(
              children: [
                NeumorphicContainer(
                  width: 44,
                  height: 44,
                  shape: BoxShape.circle,
                  depth: 3,
                  blur: 6,
                  child: const Icon(
                    Icons.key_rounded,
                    size: 20,
                    color: NeumorphicTheme.primaryBlue,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'เปลี่ยนรหัสผ่าน',
                    key: const Key('change_password_title'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.heading2.copyWith(
                      color: NeumorphicTheme.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                NeumorphicSheetCloseButton(
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // รหัสผ่านปัจจุบัน
            _buildFieldLabel('รหัสผ่านปัจจุบัน'),
            const SizedBox(height: 8),
            NeumorphicInputField(
              controller: _currentPasswordController,
              hintText: 'กรอกรหัสผ่านปัจจุบัน',
              prefixIcon: Icons.lock_outline_rounded,
              obscureText: _obscureCurrentPassword,
              enabled: !_isChangingPassword,
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureCurrentPassword ? Icons.visibility_off : Icons.visibility,
                  color: NeumorphicTheme.textSecondary,
                ),
                onPressed: () {
                  setState(() {
                    _obscureCurrentPassword = !_obscureCurrentPassword;
                  });
                },
              ),
            ),
            const SizedBox(height: 16),

            // รหัสผ่านใหม่
            _buildFieldLabel('รหัสผ่านใหม่'),
            const SizedBox(height: 8),
            NeumorphicInputField(
              controller: _newPasswordController,
              hintText: 'กรอกรหัสผ่านใหม่',
              prefixIcon: Icons.lock_reset_rounded,
              obscureText: _obscureNewPassword,
              enabled: !_isChangingPassword,
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureNewPassword ? Icons.visibility_off : Icons.visibility,
                  color: NeumorphicTheme.textSecondary,
                ),
                onPressed: _toggleNewPasswordVisibility,
              ),
            ),
            const SizedBox(height: 12),

            // ช่องยืนยัน — แสดงเฉพาะเมื่อไม่ได้เปิดการมองเห็น
            if (!_isPasswordVisibleMode) ...[
              _buildFieldLabel('ยืนยันรหัสผ่านใหม่'),
              const SizedBox(height: 8),
              NeumorphicInputField(
                controller: _confirmPasswordController,
                hintText: 'กรอกรหัสผ่านใหม่อีกครั้ง',
                prefixIcon: Icons.lock_outline_rounded,
                obscureText: _obscureConfirmPassword,
                enabled: !_isChangingPassword,
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscureConfirmPassword
                        ? Icons.visibility_off
                        : Icons.visibility,
                    color: NeumorphicTheme.textSecondary,
                  ),
                  onPressed: () {
                    setState(() {
                      _obscureConfirmPassword = !_obscureConfirmPassword;
                    });
                  },
                ),
              ),
              const SizedBox(height: 12),
            ] else ...[
              Text(
                'เปิดการมองเห็นแล้ว ไม่ต้องกรอกรหัสผ่านซ้ำ',
                style: AppTextStyles.bodySmall.copyWith(
                  color: NeumorphicTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 12),
            ],

            // Password policy hint
            Text(
              PasswordPolicy.minLengthMessage,
              style: AppTextStyles.bodySmall.copyWith(
                color: NeumorphicTheme.textSecondary.withValues(alpha: 0.8),
              ),
            ),
            const SizedBox(height: 16),

            // Error message
            if (_errorMessage != null) ...[
              Text(
                _errorMessage!,
                key: const Key('change_password_error'),
                style: AppTextStyles.bodyMedium.copyWith(
                  color: AppColors.error,
                ),
              ),
              const SizedBox(height: 16),
            ],
            // Submit buttons
            Row(
              children: [
                Expanded(
                  child: TlzButton(
                    text: 'ยกเลิก',
                    type: TlzButtonType.secondary,
                    isFullWidth: true,
                    onPressed: _isChangingPassword ? null : () => Navigator.of(context).pop(),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TlzButton(
                    key: const Key('change_password_submit'),
                    text: _isCooldownActive
                        ? 'รอ $_cooldownRemainingSeconds วิ'
                        : 'เปลี่ยนรหัสผ่าน',
                    type: TlzButtonType.primary,
                    isFullWidth: true,
                    isLoading: _isChangingPassword,
                    backgroundColor: NeumorphicTheme.primaryBlue,
                    onPressed: (_isChangingPassword || _isCooldownActive)
                        ? null
                        : _handleSubmit,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
      ),
    );
  }

  /// label เหนือช่องกรอก — โทนเดียวกับหน้า login/register ในระบบ Neumorphic
  Widget _buildFieldLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: NeumorphicTheme.textSecondary,
      ),
    );
  }
}
