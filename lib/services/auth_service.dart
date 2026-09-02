import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../features/auth/data/models/user_model.dart';
import '../features/auth/data/repositories/user_repository.dart';
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

  /// Check if current user is admin
  bool get isAdmin => _currentUser?.isAdmin ?? false;

  /// Check if current user is provider
  bool get isProvider => _currentUser?.isProvider ?? false;
  
  /// Login user (set current user) - auto starts presence heartbeat
  Future<void> login(UserModel user) async {
    _currentUser = user;
    debugPrint('AuthService: User logged in - ${user.username} (Phone: ${user.phone})');

    // Safety net: ถ้า status เป็น busy แต่ไม่มีงาน in_progress → reset เป็น online
    unawaited(_fixStaleBusyStatusIfNeeded(user));

    // เริ่ม heartbeat เพื่อ track สถานะ online แบบ real-time
    // ไม่ await — ไม่ให้ block login flow (PresenceService.start ทำงาน fire-and-forget อยู่แล้ว)
    unawaited(PresenceService.instance.start(user.id));
    notifyListeners();
  }

  /// Safety net: ถ้า provider เป็น busy แต่ไม่มี consultation in_progress อยู่จริง
  /// (เช่น app crash ขณะทำงาน หรือ session หมดเวลาโดยไม่ได้จบงานปกติ)
  /// → auto-reset เป็น online เพื่อป้องกันการค้างสถานะ busy
  Future<void> _fixStaleBusyStatusIfNeeded(UserModel user) async {
    if (user.availabilityStatus != 'busy') return;

    try {
      final response = await Supabase.instance.client
          .from('consultation_requests')
          .select('id')
          .eq('provider_id', user.id)
          .eq('status', 'in_progress')
          .limit(1);

      if ((response as List).isEmpty) {
        final userRepo = UserRepository(Supabase.instance.client);
        await userRepo.setAvailabilityStatus(user.id, 'online');
        _currentUser = user.copyWith(availabilityStatus: 'online');
        debugPrint('AuthService: Auto-reset stale busy → online for ${user.id}');
        notifyListeners();
      }
    } catch (e) {
      debugPrint('AuthService: _fixStaleBusyStatusIfNeeded error: $e');
    }
  }
  
  /// อัปเดต currentUser ในหน่วยความจำหลังข้อมูลผู้ใช้เปลี่ยน (เช่น เปลี่ยนรหัสผ่าน)
  /// ไม่ fetch ใหม่จาก DB — ใช้ user object ที่ caller มีอยู่แล้ว
  void applyUserUpdate(UserModel updatedUser) {
    if (_currentUser?.id != updatedUser.id) return; // ป้องกัน user ผิดคน
    _currentUser = updatedUser;
    notifyListeners();
  }
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
