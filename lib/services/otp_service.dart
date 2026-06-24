import 'dart:math';
import 'package:flutter/foundation.dart';
import '../config/app_config.dart';

/// OTP Service for Phone Verification
/// รองรับ 2 โหมด: Console (ทดสอบ) และ Production (SMS จริงผ่าน Supabase)
class OtpService {
  static final OtpService _instance = OtpService._internal();
  factory OtpService() => _instance;
  OtpService._internal();

  // เก็บ OTP ที่สร้างขึ้น (สำหรับ Console mode)
  final Map<String, _OtpData> _otpStorage = {};

  // OTP Configuration
  static const int otpLength = 6;
  static const int otpExpiryMinutes = 5;
  static const int maxRetries = 3;

  void _log(String message) {
    debugPrint('[OTP] $message');
  }

  /// ส่ง OTP ไปยังเบอร์โทร
  /// Returns: true ถ้าส่งสำเร็จ
  Future<OtpResult> sendOtp(String phoneNumber) async {
    // Normalize phone number
    final normalizedPhone = _normalizePhoneNumber(phoneNumber);
    _log('sendOtp called phone=$normalizedPhone consoleMode=${AppConfig.useConsoleOtp}');
    
    if (!_isValidThaiPhone(normalizedPhone)) {
      _log('sendOtp rejected: invalid phone format');
      return OtpResult(
        success: false,
        message: 'รูปแบบเบอร์โทรศัพท์ไม่ถูกต้อง',
      );
    }

    // Check rate limiting
    if (_isRateLimited(normalizedPhone)) {
      _log('sendOtp rejected: rate limited');
      return OtpResult(
        success: false,
        message: 'ส่ง OTP บ่อยเกินไป กรุณารอสักครู่',
      );
    }

    // Generate OTP
    final otp = _generateOtp();
    final expiresAt = DateTime.now().add(const Duration(minutes: otpExpiryMinutes));
    _log('generated OTP for $normalizedPhone expiresAt=$expiresAt');

    // Store OTP
    _otpStorage[normalizedPhone] = _OtpData(
      otp: otp,
      expiresAt: expiresAt,
      attempts: 0,
      createdAt: DateTime.now(),
    );

    // Send OTP based on mode
    if (AppConfig.useConsoleOtp) {
      // Console Mode - แสดงใน debug console
      _printOtpToConsole(normalizedPhone, otp, expiresAt);
      return OtpResult(
        success: true,
        message: 'ส่งรหัส OTP แล้ว (ดูใน Console)',
        isConsoleMode: true,
      );
    } else {
      // Production Mode - ส่ง SMS จริงผ่าน Supabase
      _log('sending real SMS for $normalizedPhone');
      return await _sendRealSms(normalizedPhone, otp);
    }
  }

  /// ยืนยัน OTP
  Future<OtpResult> verifyOtp(String phoneNumber, String enteredOtp) async {
    final normalizedPhone = _normalizePhoneNumber(phoneNumber);
    _log('verifyOtp called phone=$normalizedPhone enteredLength=${enteredOtp.length}');
    
    final otpData = _otpStorage[normalizedPhone];
    
    if (otpData == null) {
      _log('verifyOtp failed: otp not found');
      return OtpResult(
        success: false,
        message: 'ไม่พบรหัส OTP กรุณาขอรหัสใหม่',
      );
    }

    // Check expiry
    if (DateTime.now().isAfter(otpData.expiresAt)) {
      _otpStorage.remove(normalizedPhone);
      _log('verifyOtp failed: otp expired');
      return OtpResult(
        success: false,
        message: 'รหัส OTP หมดอายุ กรุณาขอรหัสใหม่',
      );
    }

    // Check attempts
    if (otpData.attempts >= maxRetries) {
      _otpStorage.remove(normalizedPhone);
      _log('verifyOtp failed: max retries reached');
      return OtpResult(
        success: false,
        message: 'ใส่รหัสผิดเกินจำนวนครั้งที่กำหนด กรุณาขอรหัสใหม่',
      );
    }

    // Verify OTP
    if (otpData.otp == enteredOtp) {
      _otpStorage.remove(normalizedPhone);
      _log('verifyOtp success for $normalizedPhone');
      return OtpResult(
        success: true,
        message: 'ยืนยันเบอร์โทรศัพท์สำเร็จ',
      );
    } else {
      // Increment attempts
      _otpStorage[normalizedPhone] = _OtpData(
        otp: otpData.otp,
        expiresAt: otpData.expiresAt,
        attempts: otpData.attempts + 1,
        createdAt: otpData.createdAt,
      );
      
      final remainingAttempts = maxRetries - otpData.attempts - 1;
      _log('verifyOtp failed: wrong code remainingAttempts=$remainingAttempts');
      return OtpResult(
        success: false,
        message: 'รหัส OTP ไม่ถูกต้อง (เหลืออีก $remainingAttempts ครั้ง)',
      );
    }
  }

  /// ขอส่ง OTP ใหม่
  Future<OtpResult> resendOtp(String phoneNumber) async {
    final normalizedPhone = _normalizePhoneNumber(phoneNumber);
    _log('resendOtp called phone=$normalizedPhone');
    
    // Check cooldown (60 seconds)
    final existingOtp = _otpStorage[normalizedPhone];
    if (existingOtp != null) {
      final secondsSinceCreated = DateTime.now().difference(existingOtp.createdAt).inSeconds;
      if (secondsSinceCreated < 60) {
        final waitTime = 60 - secondsSinceCreated;
        _log('resendOtp rejected: cooldown active waitTime=$waitTime');
        return OtpResult(
          success: false,
          message: 'กรุณารอ $waitTime วินาที ก่อนขอรหัสใหม่',
        );
      }
    }

    // Remove old OTP and send new one
    _otpStorage.remove(normalizedPhone);
    return sendOtp(phoneNumber);
  }

  /// ตรวจสอบว่าเบอร์นี้มี OTP ที่ยังไม่หมดอายุอยู่หรือไม่
  bool hasValidOtp(String phoneNumber) {
    final normalizedPhone = _normalizePhoneNumber(phoneNumber);
    final otpData = _otpStorage[normalizedPhone];
    if (otpData == null) return false;
    return DateTime.now().isBefore(otpData.expiresAt);
  }

  /// เวลาที่เหลือก่อน OTP หมดอายุ (วินาที)
  int getRemainingSeconds(String phoneNumber) {
    final normalizedPhone = _normalizePhoneNumber(phoneNumber);
    final otpData = _otpStorage[normalizedPhone];
    if (otpData == null) return 0;
    
    final remaining = otpData.expiresAt.difference(DateTime.now()).inSeconds;
    return remaining > 0 ? remaining : 0;
  }

  // =====================================================
  // PRIVATE METHODS
  // =====================================================

  String _normalizePhoneNumber(String phone) {
    // Remove spaces, dashes, and other characters
    String normalized = phone.replaceAll(RegExp(r'[^0-9]'), '');
    
    // Convert +66 to 0
    if (normalized.startsWith('66') && normalized.length == 11) {
      normalized = '0${normalized.substring(2)}';
    }
    
    return normalized;
  }

  bool _isValidThaiPhone(String phone) {
    // Development-friendly validation:
    // Accept any Thai-style phone number starting with 0 and having 9-10 digits.
    // This matches the existing registration form validation and avoids blocking
    // valid test numbers such as 0778430244 during development.
    final devFriendlyRegex = RegExp(r'^0[0-9]{8,9}$');
    return devFriendlyRegex.hasMatch(phone);
  }

  bool _isRateLimited(String phone) {
    final otpData = _otpStorage[phone];
    if (otpData == null) return false;
    
    // Allow resend after 30 seconds
    final secondsSinceCreated = DateTime.now().difference(otpData.createdAt).inSeconds;
    return secondsSinceCreated < 30;
  }

  String _generateOtp() {
    final random = Random.secure();
    String otp = '';
    for (int i = 0; i < otpLength; i++) {
      otp += random.nextInt(10).toString();
    }
    return otp;
  }

  void _printOtpToConsole(String phone, String otp, DateTime expiresAt) {
    final expiresIn = expiresAt.difference(DateTime.now()).inMinutes;
    
    debugPrint('');
    debugPrint('[OTP] ╔══════════════════════════════════════════╗');
    debugPrint('[OTP] ║       📱 OTP VERIFICATION (Console)      ║');
    debugPrint('[OTP] ╠══════════════════════════════════════════╣');
    debugPrint('[OTP] ║  Phone: $phone');
    debugPrint('[OTP] ║  ┌─────────────────────────────────────┐ ║');
    debugPrint('[OTP] ║  │         OTP Code: $otp            │ ║');
    debugPrint('[OTP] ║  └─────────────────────────────────────┘ ║');
    debugPrint('[OTP] ║  Expires in: $expiresIn minutes');
    debugPrint('[OTP] ║                                          ║');
    debugPrint('[OTP] ║  ⚠️  Console Mode - ไม่ส่ง SMS จริง      ║');
    debugPrint('[OTP] ╚══════════════════════════════════════════╝');
    debugPrint('');
  }

  Future<OtpResult> _sendRealSms(String phone, String otp) async {
    // TODO: Implement Supabase Phone Auth
    // This will use Supabase's built-in phone auth with Twilio
    
    try {
      // For now, return error since Supabase is not configured
      if (!AppConfig.isSupabaseConfigured) {
        _log('real SMS skipped: Supabase not configured');
        return OtpResult(
          success: false,
          message: 'Supabase ยังไม่ได้ตั้งค่า กรุณาใช้ Console Mode',
        );
      }

      // TODO: Implement actual Supabase phone auth
      // await Supabase.instance.client.auth.signInWithOtp(phone: phone);
      
      return OtpResult(
        success: true,
        message: 'ส่งรหัส OTP ไปยัง $phone แล้ว',
      );
    } catch (e) {
      _log('failed to send real SMS: $e');
      return OtpResult(
        success: false,
        message: 'ไม่สามารถส่ง SMS ได้ กรุณาลองใหม่',
      );
    }
  }
}

/// OTP Data Storage
class _OtpData {
  final String otp;
  final DateTime expiresAt;
  final int attempts;
  final DateTime createdAt;

  _OtpData({
    required this.otp,
    required this.expiresAt,
    required this.attempts,
    required this.createdAt,
  });
}

/// OTP Result
class OtpResult {
  final bool success;
  final String message;
  final bool isConsoleMode;

  OtpResult({
    required this.success,
    required this.message,
    this.isConsoleMode = false,
  });
}
