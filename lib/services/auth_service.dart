import 'dart:async';
import 'package:flutter/foundation.dart';
import '../features/auth/data/models/user_model.dart';
import 'presence_service.dart';

/// Simple Auth Service to store current user session
/// This is a temporary solution until we fully integrate Supabase Auth
class AuthService extends ChangeNotifier {
  static AuthService? _instance;
  
  UserModel? _currentUser;
  
  AuthService._();
  
  static AuthService get instance {
    _instance ??= AuthService._();
    return _instance!;
  }
  
  /// Get current logged in user
  UserModel? get currentUser => _currentUser;
  
  /// Get current user's phone number
  String? get userPhone => _currentUser?.phone;
  
  /// Check if user is logged in
  bool get isLoggedIn => _currentUser != null;
  
  /// Login user (set current user) - auto starts presence heartbeat
  Future<void> login(UserModel user) async {
    _currentUser = user;
    debugPrint('AuthService: User logged in - ${user.username} (Phone: ${user.phone})');
    // เริ่ม heartbeat เพื่อ track สถานะ online แบบ real-time
    // ไม่ await — ไม่ให้ block login flow (PresenceService.start ทำงาน fire-and-forget อยู่แล้ว)
    unawaited(PresenceService.instance.start(user.id));
    notifyListeners();
  }
  
  /// Logout user (clear current user) - auto stops presence heartbeat
  Future<void> logout() async {
    // หยุด heartbeat ก่อน logout
    await PresenceService.instance.stop();
    _currentUser = null;
    debugPrint('AuthService: User logged out');
    notifyListeners();
  }
  
  /// Get user ID
  String? get userId => _currentUser?.id;
}
