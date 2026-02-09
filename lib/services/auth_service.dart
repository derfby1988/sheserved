import 'package:flutter/foundation.dart';
import '../features/auth/data/models/user_model.dart';

/// Simple Auth Service to store current user session
/// This is a temporary solution until we fully integrate Supabase Auth
class AuthService {
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
  
  /// Login user (set current user)
  void login(UserModel user) {
    _currentUser = user;
    debugPrint('AuthService: User logged in - ${user.username} (Phone: ${user.phone})');
  }
  
  /// Logout user (clear current user)
  void logout() {
    _currentUser = null;
    debugPrint('AuthService: User logged out');
  }
  
  /// Get user ID
  String? get userId => _currentUser?.id;
}
