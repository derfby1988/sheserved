import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/health_info.dart';
import '../../../auth/data/models/user_model.dart';

/// Health Repository - จัดการข้อมูลสุขภาพใน Database
class HealthRepository {
  final SupabaseClient _client;

  HealthRepository(this._client);

  /// ดึงข้อมูลสุขภาพของผู้ใช้
  Future<HealthInfo?> getHealthInfo(String userId) async {
    try {
      final response = await _client
          .from('consumer_profiles')
          .select('health_info')
          .eq('user_id', userId)
          .single();

      if (response['health_info'] != null) {
        return HealthInfo.fromJson(response['health_info']);
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// อัพเดทข้อมูลสุขภาพ
  Future<HealthInfo?> updateHealthInfo(String userId, HealthInfo healthInfo) async {
    try {
      // Calculate health score
      final score = HealthInfo.calculateHealthScore(
        bmi: healthInfo.bmi,
        age: healthInfo.age,
        gender: healthInfo.gender,
      );

      final updatedInfo = healthInfo.copyWith(healthScore: score);

      await _client
          .from('consumer_profiles')
          .update({
            'health_info': updatedInfo.toJson(),
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('user_id', userId);

      return updatedInfo;
    } catch (e) {
      return null;
    }
  }

  /// ดึงรายการอุปกรณ์ที่เชื่อมต่อ (Mock data for now)
  Future<List<ConnectedDevice>> getConnectedDevices(String userId) async {
    // TODO: Implement actual device connection from database
    // For now, return mock data
    return [
      ConnectedDevice(
        id: '1',
        name: 'Smart Scale Pro',
        type: DeviceType.scale,
        isConnected: true,
        lastSyncAt: DateTime.now().subtract(const Duration(hours: 2)),
      ),
      ConnectedDevice(
        id: '2',
        name: 'Fitness Watch X',
        type: DeviceType.watch,
        isConnected: true,
        lastSyncAt: DateTime.now().subtract(const Duration(minutes: 30)),
      ),
      ConnectedDevice(
        id: '3',
        name: 'Treadmill T500',
        type: DeviceType.treadmill,
        isConnected: true,
        lastSyncAt: DateTime.now().subtract(const Duration(days: 1)),
      ),
      const ConnectedDevice(
        id: '4',
        name: 'Running Shoes',
        type: DeviceType.shoes,
        isConnected: false,
      ),
    ];
  }

  /// เชื่อมต่ออุปกรณ์ใหม่
  Future<bool> connectDevice(String userId, ConnectedDevice device) async {
    // TODO: Implement actual device connection
    await Future.delayed(const Duration(seconds: 1));
    return true;
  }

  /// ยกเลิกการเชื่อมต่ออุปกรณ์
  Future<bool> disconnectDevice(String userId, String deviceId) async {
    // TODO: Implement actual device disconnection
    await Future.delayed(const Duration(milliseconds: 500));
    return true;
  }

  /// ดึงประวัติการวัดสุขภาพ (Mock data)
  Future<List<Map<String, dynamic>>> getHealthHistory(String userId, {int limit = 30}) async {
    // TODO: Implement actual health history from database
    final now = DateTime.now();
    return List.generate(limit, (index) {
      final date = now.subtract(Duration(days: index));
      return {
        'date': date.toIso8601String(),
        'weight': 64.0 + (index % 3) * 0.5,
        'steps': 5000 + (index * 200) % 10000,
        'calories': 1800 + (index * 50) % 800,
      };
    });
  }

  /// ดึง Consumer Profile พร้อมข้อมูลสุขภาพ
  Future<ConsumerProfile?> getConsumerProfileWithHealth(String userId) async {
    try {
      final response = await _client
          .from('consumer_profiles')
          .select()
          .eq('user_id', userId)
          .single();

      return ConsumerProfile.fromJson(response);
    } catch (e) {
      return null;
    }
  }
}
