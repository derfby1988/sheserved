import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/user_model.dart';
import '../repositories/user_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Social Auth Provider Types
enum SocialAuthProvider {
  google,
  facebook,
  apple,
  line,
  tiktok,
}

/// Social Auth Result
class SocialAuthResult {
  final bool success;
  final UserModel? user;
  final String? errorMessage;
  final bool isNewUser;

  SocialAuthResult({
    required this.success,
    this.user,
    this.errorMessage,
    this.isNewUser = false,
  });

  factory SocialAuthResult.success(UserModel user, {bool isNewUser = false}) {
    return SocialAuthResult(
      success: true,
      user: user,
      isNewUser: isNewUser,
    );
  }

  factory SocialAuthResult.error(String message) {
    return SocialAuthResult(
      success: false,
      errorMessage: message,
    );
  }
}

/// Social User Info from Provider
class SocialUserInfo {
  final String id;
  final String? email;
  final String? firstName;
  final String? lastName;
  final String? displayName;
  final String? photoUrl;
  final SocialAuthProvider provider;

  SocialUserInfo({
    required this.id,
    this.email,
    this.firstName,
    this.lastName,
    this.displayName,
    this.photoUrl,
    required this.provider,
  });

  String get fullName {
    if (firstName != null && lastName != null) {
      return '$firstName $lastName';
    }
    return displayName ?? '';
  }
}

/// Social Auth Service - จัดการ Social Login ทั้งหมด
class SocialAuthService {
  final UserRepository _userRepository;
  final SupabaseClient _supabaseClient;

  // Google Sign In Configuration
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: ['email', 'profile'],
  );

  // LINE Login Configuration
  // TODO: ใส่ LINE Channel ID จริง
  static const String _lineChannelId = 'YOUR_LINE_CHANNEL_ID';
  static const String _lineRedirectUri = 'YOUR_APP_REDIRECT_URI';

  SocialAuthService(this._userRepository, this._supabaseClient);

  // =====================================================
  // GOOGLE SIGN IN
  // =====================================================

  /// เข้าสู่ระบบด้วย Google
  Future<SocialAuthResult> signInWithGoogle() async {
    try {
      // Sign out first to ensure account picker is shown
      await _googleSignIn.signOut();

      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();

      if (googleUser == null) {
        return SocialAuthResult.error('ยกเลิกการเข้าสู่ระบบ');
      }

      final socialUserInfo = SocialUserInfo(
        id: googleUser.id,
        email: googleUser.email,
        displayName: googleUser.displayName,
        photoUrl: googleUser.photoUrl,
        provider: SocialAuthProvider.google,
      );

      return await _handleSocialLogin(socialUserInfo);
    } catch (e) {
      debugPrint('Google Sign-In Error: $e');
      return SocialAuthResult.error('เกิดข้อผิดพลาดในการเข้าสู่ระบบด้วย Google');
    }
  }

  // =====================================================
  // FACEBOOK SIGN IN
  // =====================================================

  /// เข้าสู่ระบบด้วย Facebook
  Future<SocialAuthResult> signInWithFacebook() async {
    try {
      // Log out first
      await FacebookAuth.instance.logOut();

      final LoginResult result = await FacebookAuth.instance.login(
        permissions: ['email', 'public_profile'],
      );

      if (result.status == LoginStatus.cancelled) {
        return SocialAuthResult.error('ยกเลิกการเข้าสู่ระบบ');
      }

      if (result.status == LoginStatus.failed) {
        return SocialAuthResult.error(
            result.message ?? 'เกิดข้อผิดพลาดในการเข้าสู่ระบบด้วย Facebook');
      }

      // Get user data
      final userData = await FacebookAuth.instance.getUserData(
        fields: "id,name,email,picture.width(200)",
      );

      final nameParts = (userData['name'] as String?)?.split(' ') ?? [];
      final firstName = nameParts.isNotEmpty ? nameParts.first : null;
      final lastName = nameParts.length > 1 ? nameParts.sublist(1).join(' ') : null;

      final socialUserInfo = SocialUserInfo(
        id: userData['id'],
        email: userData['email'],
        firstName: firstName,
        lastName: lastName,
        displayName: userData['name'],
        photoUrl: userData['picture']?['data']?['url'],
        provider: SocialAuthProvider.facebook,
      );

      return await _handleSocialLogin(socialUserInfo);
    } catch (e) {
      debugPrint('Facebook Sign-In Error: $e');
      return SocialAuthResult.error('เกิดข้อผิดพลาดในการเข้าสู่ระบบด้วย Facebook');
    }
  }

  // =====================================================
  // APPLE SIGN IN
  // =====================================================

  /// เข้าสู่ระบบด้วย Apple
  Future<SocialAuthResult> signInWithApple() async {
    try {
      // Generate nonce for security
      final rawNonce = _generateNonce();
      final nonce = _sha256ofString(rawNonce);

      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: nonce,
      );

      final socialUserInfo = SocialUserInfo(
        id: credential.userIdentifier ?? '',
        email: credential.email,
        firstName: credential.givenName,
        lastName: credential.familyName,
        provider: SocialAuthProvider.apple,
      );

      return await _handleSocialLogin(socialUserInfo);
    } catch (e) {
      if (e is SignInWithAppleAuthorizationException) {
        if (e.code == AuthorizationErrorCode.canceled) {
          return SocialAuthResult.error('ยกเลิกการเข้าสู่ระบบ');
        }
      }
      debugPrint('Apple Sign-In Error: $e');
      return SocialAuthResult.error('เกิดข้อผิดพลาดในการเข้าสู่ระบบด้วย Apple');
    }
  }

  // =====================================================
  // LINE SIGN IN
  // =====================================================

  /// เข้าสู่ระบบด้วย LINE (OAuth Web Flow)
  Future<SocialAuthResult> signInWithLine() async {
    try {
      // Generate state for security
      final state = _generateNonce(16);

      // Build LINE authorization URL
      final authUrl = Uri.https('access.line.me', '/oauth2/v2.1/authorize', {
        'response_type': 'code',
        'client_id': _lineChannelId,
        'redirect_uri': _lineRedirectUri,
        'state': state,
        'scope': 'profile openid email',
      });

      // Launch LINE login in browser
      if (await canLaunchUrl(authUrl)) {
        await launchUrl(authUrl, mode: LaunchMode.externalApplication);
        // Note: LINE callback will be handled by deep link
        return SocialAuthResult.error(
            'กรุณาดำเนินการต่อในหน้าต่าง LINE Login');
      } else {
        return SocialAuthResult.error('ไม่สามารถเปิด LINE Login ได้');
      }
    } catch (e) {
      debugPrint('LINE Sign-In Error: $e');
      return SocialAuthResult.error('เกิดข้อผิดพลาดในการเข้าสู่ระบบด้วย LINE');
    }
  }

  /// Handle LINE OAuth callback
  Future<SocialAuthResult> handleLineCallback(String code) async {
    try {
      // TODO: Exchange code for access token and get user profile
      // This requires server-side implementation for security

      return SocialAuthResult.error('LINE Login ยังไม่พร้อมใช้งาน');
    } catch (e) {
      debugPrint('LINE Callback Error: $e');
      return SocialAuthResult.error('เกิดข้อผิดพลาดในการเข้าสู่ระบบด้วย LINE');
    }
  }

  // =====================================================
  // TIKTOK SIGN IN
  // =====================================================

  /// เข้าสู่ระบบด้วย TikTok (ยังไม่รองรับ)
  Future<SocialAuthResult> signInWithTikTok() async {
    // TikTok Login Kit requires business account and approval
    return SocialAuthResult.error('TikTok Login จะเปิดใช้งานเร็วๆ นี้');
  }

  // =====================================================
  // COMMON HANDLERS
  // =====================================================

  /// Handle social login - ตรวจสอบและสร้าง/อัพเดทผู้ใช้
  Future<SocialAuthResult> _handleSocialLogin(SocialUserInfo info) async {
    try {
      // ค้นหาผู้ใช้จาก social provider ID
      final existingUser = await _userRepository.getUserBySocialId(
        info.provider.name,
        info.id,
      );

      if (existingUser != null) {
        // ผู้ใช้มีอยู่แล้ว - อัพเดทข้อมูลล่าสุด
        final updatedUser = await _userRepository.updateUser(existingUser.id, {
          'profile_image_url': info.photoUrl,
          'last_login_at': DateTime.now().toIso8601String(),
        });
        return SocialAuthResult.success(updatedUser);
      }

      // ผู้ใช้ใหม่ - สร้างบัญชี
      final username = _generateUsername(info);
      final newUser = await _userRepository.createUserFromSocial(
        userType: UserType.consumer, // Default to consumer
        firstName: info.firstName ?? info.displayName?.split(' ').first ?? '',
        lastName: info.lastName ?? '',
        username: username,
        socialProvider: info.provider.name,
        socialId: info.id,
        profileImageUrl: info.photoUrl,
      );

      return SocialAuthResult.success(newUser, isNewUser: true);
    } catch (e) {
      debugPrint('Handle Social Login Error: $e');
      return SocialAuthResult.error('เกิดข้อผิดพลาดในการเข้าสู่ระบบ');
    }
  }

  /// Generate unique username from social info
  String _generateUsername(SocialUserInfo info) {
    String base = '';

    if (info.displayName != null && info.displayName!.isNotEmpty) {
      base = info.displayName!
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9]'), '');
    } else if (info.firstName != null) {
      base = info.firstName!.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    } else {
      base = info.provider.name;
    }

    // Add random suffix to ensure uniqueness
    final random = Random();
    final suffix = random.nextInt(9999).toString().padLeft(4, '0');

    return '${base}_$suffix';
  }

  /// Generate random nonce
  String _generateNonce([int length = 32]) {
    const charset =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = Random.secure();
    return List.generate(length, (_) => charset[random.nextInt(charset.length)])
        .join();
  }

  /// SHA256 hash of string
  String _sha256ofString(String input) {
    final bytes = utf8.encode(input);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  // =====================================================
  // SIGN OUT
  // =====================================================

  /// Sign out from all social providers
  Future<void> signOut() async {
    try {
      // Google
      if (await _googleSignIn.isSignedIn()) {
        await _googleSignIn.signOut();
      }

      // Facebook
      await FacebookAuth.instance.logOut();

      // Apple doesn't have sign out API
    } catch (e) {
      debugPrint('Social Sign Out Error: $e');
    }
  }
}
