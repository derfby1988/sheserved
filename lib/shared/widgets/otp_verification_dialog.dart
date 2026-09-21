import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_text_styles.dart';
import '../../services/otp_service.dart';
import 'neumorphic/neumorphic.dart';

/// OTP Verification Dialog
/// ใช้สำหรับยืนยันเบอร์โทรศัพท์ด้วย OTP
class OtpVerificationDialog extends StatefulWidget {
  final String phoneNumber;
  final VoidCallback? onVerified;
  final VoidCallback? onCancel;

  const OtpVerificationDialog({
    super.key,
    required this.phoneNumber,
    this.onVerified,
    this.onCancel,
  });

  /// แสดง Dialog และส่ง OTP
  static Future<bool> show(BuildContext context, String phoneNumber) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => OtpVerificationDialog(phoneNumber: phoneNumber),
    );
    return result ?? false;
  }

  @override
  State<OtpVerificationDialog> createState() => _OtpVerificationDialogState();
}

class _OtpVerificationDialogState extends State<OtpVerificationDialog> {
  final OtpService _otpService = OtpService();
  final TextEditingController _otpController = TextEditingController();
  final FocusNode _otpFocusNode = FocusNode();

  bool _isLoading = false;
  bool _isSending = false;
  String? _errorMessage;
  int _remainingSeconds = 0;
  Timer? _countdownTimer;
  bool _isConsoleMode = false;
  bool _isAutoVerifying = false;
  String? _currentOtpCode;

  @override
  void initState() {
    super.initState();
    _otpController.addListener(_handleOtpChanged);
    // ส่ง OTP ทันทีที่เปิด Dialog
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _sendOtp();
    });
  }

  @override
  void dispose() {
    _otpController.removeListener(_handleOtpChanged);
    _otpController.dispose();
    _otpFocusNode.dispose();
    _countdownTimer?.cancel();
    super.dispose();
  }

  void _focusOtpField() {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _otpFocusNode.requestFocus();
      }
    });
  }

  void _clearOtpInput({bool clearError = true}) {
    _otpController.clear();
    _isAutoVerifying = false;
    if (clearError && mounted) {
      setState(() {
        _errorMessage = null;
      });
    }
  }

  void _handleOtpChanged() {
    if (!mounted) return;

    setState(() {
      if (_errorMessage != null) {
        _errorMessage = null;
      }
    });

    final otp = _otpController.text;

    if (otp.length < 6) {
      _isAutoVerifying = false;
      return;
    }

    if (otp.length == 6 && !_isLoading && !_isSending && !_isAutoVerifying) {
      _isAutoVerifying = true;
      _verifyOtp().whenComplete(() {
        _isAutoVerifying = false;
      });
    }
  }

  Future<void> _sendOtp() async {
    setState(() {
      _isSending = true;
      _errorMessage = null;
    });

    final result = await _otpService.sendOtp(widget.phoneNumber);

    if (mounted) {
      setState(() {
        _isSending = false;
        _isConsoleMode = result.isConsoleMode;
        if (result.otpCode != null) {
          _currentOtpCode = result.otpCode;
        }
        if (!result.success) {
          _errorMessage = result.message;
        } else {
          _startCountdown();
          _clearOtpInput(clearError: false);
        }
      });

      if (result.success) {
        _showSnackBar(result.message, isSuccess: true);
        _focusOtpField();
      }
    }
  }

  void _startCountdown() {
    _remainingSeconds = _otpService.getRemainingSeconds(widget.phoneNumber);
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _remainingSeconds = _otpService.getRemainingSeconds(
            widget.phoneNumber,
          );
          if (_remainingSeconds <= 0) {
            timer.cancel();
          }
        });
      } else {
        timer.cancel();
      }
    });
  }

  Future<void> _verifyOtp() async {
    final otp = _otpController.text.trim();

    if (otp.length != 6) {
      setState(() {
        _errorMessage = 'กรุณากรอกรหัส OTP ให้ครบ 6 หลัก';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final result = await _otpService.verifyOtp(widget.phoneNumber, otp);

    if (mounted) {
      setState(() {
        _isLoading = false;
      });

      if (result.success) {
        _showSnackBar(result.message, isSuccess: true);
        Navigator.of(context).pop(true);
        widget.onVerified?.call();
      } else {
        setState(() {
          _errorMessage = result.message;
        });
        // Clear OTP field on error and refocus for retry
        _clearOtpInput(clearError: false);
        _focusOtpField();
      }
    }
  }

  Future<void> _resendOtp() async {
    setState(() {
      _isSending = true;
      _errorMessage = null;
    });

    final result = await _otpService.resendOtp(widget.phoneNumber);

    if (mounted) {
      setState(() {
        _isSending = false;
        if (result.otpCode != null) {
          _currentOtpCode = result.otpCode;
        }
        if (!result.success) {
          _errorMessage = result.message;
        } else {
          _startCountdown();
          // Clear OTP field
          _clearOtpInput(clearError: false);
          _focusOtpField();
        }
      });

      _showSnackBar(result.message, isSuccess: result.success);
    }
  }

  void _showSnackBar(String message, {bool isSuccess = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isSuccess ? AppColors.success : AppColors.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: NeumorphicTheme.baseColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: GestureDetector(
        // แตะพื้นที่ว่างบน Dialog เพื่อซ่อนแป้นพิมพ์
        // (ปุ่ม/ช่อง OTP ยังรับ tap ได้ปกติ เพราะ child ได้ priority ใน gesture arena)
        onTap: () => FocusScope.of(context).unfocus(),
        behavior: HitTestBehavior.opaque,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 400),
          // Scroll ได้เมื่อแป้นพิมพ์ขึ้นมาบังจนพื้นที่เหลือไม่พอ (กัน overflow)
          // padding อยู่ "ใน" ScrollView เพื่อให้เงาของปุ่ม/กล่องไม่ถูก clip ที่ขอบ
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 30),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header Icon - วงกลมนูน Neumorphic พร้อมไอคอนสีฟ้า
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: NeumorphicTheme.baseColor,
                    shape: BoxShape.circle,
                    boxShadow: NeumorphicTheme.smallShadows(
                      distance: 6,
                      blur: 14,
                    ),
                  ),
                  child: const Icon(
                    Icons.sms_outlined,
                    size: 36,
                    color: NeumorphicTheme.primaryBlue,
                  ),
                ),
                const SizedBox(height: 20),

                // Title - ย่อขนาดตัวอักษรอัตโนมัติให้อยู่บรรทัดเดียวเสมอ
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    'ยืนยันเบอร์โทรศัพท์',
                    style: AppTextStyles.heading2.copyWith(
                      color: NeumorphicTheme.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(height: 8),

                // Subtitle
                Text(
                  'กรุณากรอกรหัส OTP 6 หลัก\nที่ส่งไปยัง ${_formatPhoneNumber(widget.phoneNumber)}',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: NeumorphicTheme.textSecondary,
                  ),
                ),

                // Console Mode Notice & Quick Auto-fill
                if (_isConsoleMode) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.amber.shade300,
                        width: 1.5,
                      ),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.developer_mode,
                              size: 18,
                              color: Colors.amber.shade800,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'โหมดทดสอบ (Console Mode)',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Colors.amber.shade900,
                              ),
                            ),
                          ],
                        ),
                        if (_currentOtpCode != null) ...[
                          const SizedBox(height: 6),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                'OTP: ',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.amber.shade900,
                                ),
                              ),
                              Text(
                                _currentOtpCode!,
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 3,
                                  color: Colors.amber.shade900,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          InkWell(
                            onTap: () {
                              _otpController.text = _currentOtpCode!;
                            },
                            borderRadius: BorderRadius.circular(6),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.amber.shade200,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.touch_app,
                                    size: 14,
                                    color: Colors.brown.shade800,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    'แตะเพื่อกรอกรหัสนี้อัตโนมัติ',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.brown.shade900,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ] else ...[
                          const SizedBox(height: 4),
                          Text(
                            'กำลังดึงรหัส OTP...',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.amber.shade700,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 24),

                // OTP Input Fields
                if (_isSending)
                  const Padding(
                    padding: EdgeInsets.all(20),
                    child: CircularProgressIndicator(
                      color: NeumorphicTheme.accentCyan,
                    ),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: _buildOtpInputSection(),
                  ),

                const SizedBox(height: 16),

                // Error Message
                if (_errorMessage != null)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.error_outline,
                          color: AppColors.error,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: TextStyle(
                              color: AppColors.error,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                const SizedBox(height: 20),

                // Countdown / Resend Button
                if (_remainingSeconds > 0)
                  Text(
                    'ขอรหัสใหม่ได้ใน ${_formatTime(_remainingSeconds)}',
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: NeumorphicTheme.textSecondary,
                    ),
                  )
                else
                  TextButton(
                    onPressed: _isSending ? null : _resendOtp,
                    child: const Text(
                      'ส่งรหัสใหม่',
                      style: TextStyle(
                        color: NeumorphicTheme.primaryBlue,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),

                const SizedBox(height: 24),

                // Action Buttons
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _isLoading
                            ? null
                            : () {
                                Navigator.of(context).pop(false);
                                widget.onCancel?.call();
                              },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: NeumorphicTheme.textSecondary,
                          side: const BorderSide(
                            color: Color(0xFF94A3B8),
                            width: 1.5,
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: const Text('ยกเลิก'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // ปุ่มยืนยัน - Gradient ฟ้า + Glow สไตล์ Neumorphic
                    Expanded(
                      child: NeumorphicVerifyButton(
                        text: 'ยืนยัน',
                        height: 52,
                        isLoading: _isLoading,
                        isEnabled: !_isLoading,
                        onPressed: _verifyOtp,
                        icon: const Icon(
                          Icons.check_rounded,
                          color: Colors.white,
                          size: 20,
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
    );
  }

  Widget _buildOtpInputSection() {
    // ใช้ NeumorphicOtpField ส่วนกลาง (กล่องร่องลึก Inset + Cyan Glow ตอน Active)
    // controller/focusNode เดิมถูกส่งต่อให้ listener _handleOtpChanged ทำงานเหมือนเดิม
    return AutofillGroup(
      child: NeumorphicOtpField(
        controller: _otpController,
        focusNode: _otpFocusNode,
      ),
    );
  }

  String _formatPhoneNumber(String phone) {
    if (phone.length == 10) {
      return '${phone.substring(0, 3)}-${phone.substring(3, 6)}-${phone.substring(6)}';
    }
    return phone;
  }

  String _formatTime(int seconds) {
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }
}
