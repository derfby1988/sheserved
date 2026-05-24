import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sheserved/features/auth/data/repositories/user_repository.dart';

/// PresenceService - จัดการสถานะ online ของผู้ใช้
/// ส่ง heartbeat ทุก 60 วินาที เพื่ออัปเดต last_seen_at ใน Supabase
class PresenceService {
  static PresenceService? _instance;
  static PresenceService get instance {
    _instance ??= PresenceService._();
    return _instance!;
  }

  PresenceService._();

  Timer? _heartbeatTimer;
  String? _currentUserId;
  bool _isRunning = false;

  static const Duration _heartbeatInterval = Duration(seconds: 60);

  /// เริ่ม heartbeat สำหรับ userId ที่ล็อกอิน
  Future<void> start(String userId) async {
    if (_isRunning && _currentUserId == userId) return;

    await stop(); // หยุด timer เดิมถ้ามี

    _currentUserId = userId;
    _isRunning = true;

    // อัปเดตทันทีเมื่อ start (ไม่ block — fire-and-forget เพื่อไม่ให้ login ค้าง)
    final repo = UserRepository(Supabase.instance.client);
    unawaited(repo.setAvailabilityStatus(userId, 'online'));
    unawaited(_sendHeartbeat());

    // ตั้ง timer ส่งทุก 60 วินาที
    _heartbeatTimer = Timer.periodic(_heartbeatInterval, (_) {
      _sendHeartbeat();
    });

    debugPrint('PresenceService: Started heartbeat for user $userId');
  }

  /// หยุด heartbeat (เมื่อ logout หรือปิดแอป)
  Future<void> stop() async {
    if (_heartbeatTimer == null && _currentUserId == null) return;
    
    final userId = _currentUserId;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _isRunning = false;
    _currentUserId = null;

    if (userId != null) {
      try {
        final repo = UserRepository(Supabase.instance.client);
        await repo.setAvailabilityStatus(userId, 'offline');
      } catch (e) {
        debugPrint('PresenceService: Error setting offline status: $e');
      }
    }
    debugPrint('PresenceService: Stopped heartbeat');
  }

  /// ส่ง heartbeat ทันที (เช่น เมื่อแอปกลับมา foreground)
  void ping() {
    if (_currentUserId != null) {
      _sendHeartbeat();
    }
  }

  Future<void> _sendHeartbeat() async {
    if (_currentUserId == null) return;
    try {
      final repo = UserRepository(Supabase.instance.client);
      await repo.updateLastSeen(_currentUserId!);
      // debugPrint('PresenceService: Heartbeat sent at ${DateTime.now()}');
    } catch (e) {
      debugPrint('PresenceService: Heartbeat error: $e');
    }
  }

  bool get isRunning => _isRunning;
  String? get currentUserId => _currentUserId;
}
