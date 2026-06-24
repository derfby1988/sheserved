import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_text_styles.dart';
import '../../services/otp_service.dart';

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

  @override
  void initState() {
    super.initState();
    _otpController.addListener(_handleOtpChanged);
    _sendOtp();
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
          _remainingSeconds = _otpService.getRemainingSeconds(widget.phoneNumber);
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        padding: const EdgeInsets.all(24),
        constraints: const BoxConstraints(maxWidth: 400),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header Icon
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.sms_outlined,
                size: 40,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 20),

            // Title
            Text(
              'ยืนยันเบอร์โทรศัพท์',
              style: AppTextStyles.heading2.copyWith(
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),

            // Subtitle
            Text(
              'กรุณากรอกรหัส OTP 6 หลัก\nที่ส่งไปยัง ${_formatPhoneNumber(widget.phoneNumber)}',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.textSecondary,
              ),
            ),

            // Console Mode Notice
            if (_isConsoleMode) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.amber.shade200),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.info_outline, size: 16, color: Colors.amber.shade700),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'โหมดทดสอบ: ดู OTP ใน Console',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.amber.shade700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 24),

            // OTP Input Fields
            if (_isSending)
              const Padding(
                padding: EdgeInsets.all(20),
                child: CircularProgressIndicator(),
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
                    Icon(Icons.error_outline, color: AppColors.error, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: TextStyle(color: AppColors.error, fontSize: 13),
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
                  color: AppColors.textSecondary,
                ),
              )
            else
              TextButton(
                onPressed: _isSending ? null : _resendOtp,
                child: Text(
                  'ส่งรหัสใหม่',
                  style: TextStyle(
                    color: AppColors.primary,
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
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('ยกเลิก'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _verifyOtp,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('ยืนยัน'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOtpInputSection() {
    final otpText = _otpController.text;
    final activeIndex = otpText.length >= 6 ? 5 : otpText.length;

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: _focusOtpField,
      child: AutofillGroup(
        child: SizedBox(
          height: 64,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: List.generate(6, (index) {
                  final hasDigit = index < otpText.length;
                  final isActive = index == activeIndex && otpText.length < 6;
                  return _buildOtpBox(
                    value: hasDigit ? otpText[index] : '',
                    isActive: isActive,
                  );
                }),
              ),
              Positioned.fill(
                child: Align(
                  alignment: Alignment.center,
                  child: SizedBox(
                    width: 1,
                    height: 1,
                    child: Opacity(
                      opacity: 0.01,
                      child: TextField(
                        controller: _otpController,
                        focusNode: _otpFocusNode,
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.done,
                        autofillHints: const [AutofillHints.oneTimeCode],
                        enableSuggestions: false,
                        autocorrect: false,
                        showCursor: false,
                        cursorColor: Colors.transparent,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        style: const TextStyle(
                          color: Colors.transparent,
                          fontSize: 1,
                          height: 1,
                        ),
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          errorBorder: InputBorder.none,
                          disabledBorder: InputBorder.none,
                          counterText: '',
                          isCollapsed: true,
                          contentPadding: EdgeInsets.zero,
                          filled: false,
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(6),
                        ],
                        onSubmitted: (_) => _verifyOtp(),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOtpBox({
    required String value,
    required bool isActive,
  }) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      width: 42,
      height: 54,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isActive ? AppColors.primary : AppColors.border,
          width: isActive ? 2 : 1,
        ),
      ),
      child: Text(
        value,
        style: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.bold,
          color: AppColors.textPrimary,
        ),
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
