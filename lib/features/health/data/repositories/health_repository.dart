import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/health_info.dart';
import '../models/health_data_change_log.dart';
import '../models/device_health_metric.dart';
import '../../../auth/data/models/user_model.dart';
import '../../../../services/auth_service.dart';

/// Health Repository - จัดการข้อมูลสุขภาพใน Database
class HealthRepository {
  final SupabaseClient _client;

  HealthRepository(this._client);

  /// BOLA: Verify that the requested userId matches the authenticated session user.
  /// Throws Exception if the caller is not the owner.
  Future<void> _verifyOwnership(String userId) async {
    final currentUserId = AuthService.instance.currentUser?.id;
    if (currentUserId == null || currentUserId != userId) {
      throw Exception('Access denied: cannot access another user\'s health data');
    }
  }

  /// ดึงข้อมูลสุขภาพของผู้ใช้ (BOLA: verified against session)
  Future<HealthInfo?> getHealthInfo(String userId) async {
    await _verifyOwnership(userId);
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

  /// อัพเดทข้อมูลสุขภาพ (BOLA: verified against session)
  Future<HealthInfo?> updateHealthInfo(
    String userId,
    HealthInfo healthInfo,
  ) async {
    await _verifyOwnership(userId);
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

  /// ดึงประวัติการเปลี่ยนแปลงข้อมูลสุขภาพ (Real Data) (BOLA: verified against session)
  Future<List<HealthDataChangeLog>> getHealthHistoryLog(
    String userId,
    String fieldType,
  ) async {
    await _verifyOwnership(userId);
    try {
      final response = await _client
          .from('health_data_logs')
          .select()
          .eq('user_id', userId)
          .eq('field_type', fieldType)
          .order('created_at', ascending: false);

      return (response as List)
          .map((e) => HealthDataChangeLog.fromJson(e))
          .toList();
    } catch (e) {
      // If table doesn't exist yet or error occurs, return empty list
      return [];
    }
  }

  /// บันทึกประวัติการเปลี่ยนแปลงข้อมูลสุขภาพ
  Future<void> logHealthChange({
    required String userId,
    required String fieldType,
    String? oldValue,
    required String newValue,
    String? editorName,
  }) async {
    try {
      await _client.from('health_data_logs').insert({
        'user_id': userId,
        'field_type': fieldType,
        'old_value': oldValue,
        'new_value': newValue,
        'editor_name': editorName ?? 'Unknown',
        'created_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      // Log error silently, don't block user flow
      print('Error logging health change: $e');
    }
  }

  /// ดึงประวัติการวัดสุขภาพ (Mock data)
  Future<List<Map<String, dynamic>>> getHealthHistory(
    String userId, {
    int limit = 30,
  }) async {
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

  /// ดึง Consumer Profile พร้อมข้อมูลสุขภาพ (BOLA: verified against session)
  Future<ConsumerProfile?> getConsumerProfileWithHealth(String userId) async {
    await _verifyOwnership(userId);
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

  /// บันทึกข้อมูลสุขภาพรายวันลงตารางใหม่
  Future<void> syncDeviceMetrics(List<DeviceHealthMetric> metrics) async {
    if (metrics.isEmpty) return;

    try {
      final data = metrics.map((m) => m.toJson()).toList();
      await _client.from('device_health_metrics').insert(data);
    } catch (e) {
      print('Error syncing device metrics: $e');
    }
  }

  /// อัปเดตน้ำหนักใน consumer_profiles เมื่อได้ค่าใหม่จากตาชั่งอัจฉริยะ
  /// พร้อมคำนวณ BMI ใหม่และบันทึก Log (BOLA: verified against session)
  Future<void> updateWeightFromDevice({
    required String userId,
    required double weight,
    required String sourceName,
  }) async {
    await _verifyOwnership(userId);
    try {
      // 1. ดึงข้อมูล health_info ปัจจุบัน
      final response = await _client
          .from('consumer_profiles')
          .select('health_info')
          .eq('user_id', userId)
          .single();

      final currentInfo = Map<String, dynamic>.from(
        response['health_info'] ?? {},
      );
      final oldWeight = (currentInfo['weight'] as num?)?.toDouble();

      // ถ้าน้ำหนักเท่าเดิม ไม่ต้องอัปเดต
      if (oldWeight != null && (oldWeight - weight).abs() < 0.1) return;

      // 2. คำนวณ BMI ใหม่จากส่วนสูงที่มีอยู่
      final height = (currentInfo['height'] as num?)?.toDouble();
      double? newBmi;
      if (height != null && height > 0) {
        final heightM = height / 100.0;
        newBmi = weight / (heightM * heightM);
      }

      // 3. อัปเดตค่าใน health_info
      final updatedInfo = {
        ...currentInfo,
        'weight': weight,
        if (newBmi != null) 'bmi': double.parse(newBmi.toStringAsFixed(1)),
      };

      await _client
          .from('consumer_profiles')
          .update({
            'health_info': updatedInfo,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('user_id', userId);

      // 4. บันทึก Log การเปลี่ยนแปลงน้ำหนัก
      await logHealthChange(
        userId: userId,
        fieldType: 'weight',
        oldValue: oldWeight?.toString(),
        newValue: weight.toString(),
        editorName: '$sourceName (Auto Sync)',
      );
    } catch (e) {
      print('updateWeightFromDevice error: $e');
    }
  }

  /// ดึงข้อมูลเมตริกล่าสุดของวันนี้จากฐานข้อมูลจริง เพื่อใช้คำนวณคะแนนสุขภาพแบบ Dynamic (BOLA: verified against session)
  Future<Map<String, dynamic>> getLatestDailyMetrics(String userId) async {
    await _verifyOwnership(userId);
    try {
      final now = DateTime.now();
      final startOfYesterday = now
          .subtract(const Duration(hours: 24))
          .toIso8601String();

      final response = await _client
          .from('device_health_metrics')
          .select()
          .eq('user_id', userId)
          .gte('measured_at', startOfYesterday)
          .order('measured_at', ascending: false);

      final List<dynamic> list = response as List<dynamic>;

      // หาค่าตามประเภทข้อมูล
      int todaySteps = 0;
      double todayCalories = 0.0;
      int? latestHeartRate;
      double? latestHRV;
      int? lastSleepDuration;

      for (var row in list) {
        final type = row['metric_type']?.toString();
        final val = (row['value'] as num?)?.toDouble() ?? 0.0;
        final measuredAtStr = row['measured_at']?.toString() ?? '';
        final measuredAt = DateTime.tryParse(measuredAtStr) ?? now;

        // สำหรับก้าวเดินและแคลอรี่ ให้นับเฉพาะของวันนี้ (ตั้งแต่ 00:00)
        final isToday =
            measuredAt.year == now.year &&
            measuredAt.month == now.month &&
            measuredAt.day == now.day;

        if (type == 'steps' && isToday) {
          todaySteps += val.toInt();
        } else if ((type == 'active_calories' || type == 'calories') &&
            isToday) {
          todayCalories += val;
        } else if (type == 'heart_rate' && latestHeartRate == null) {
          latestHeartRate = val.toInt();
        } else if ((type == 'hrv_sdnn' || type == 'hrv') && latestHRV == null) {
          latestHRV = val;
        } else if ((type == 'sleep_asleep' || type == 'sleep') &&
            lastSleepDuration == null) {
          lastSleepDuration = val.toInt();
        }
      }

      // ถ้าไม่มีข้อมูลของวันนี้ใน 24 ชม. ลองดึงค่าล่าสุดแบบไม่จำกัดเวลา (สำหรับเป็น fallback)
      if (todaySteps == 0) {
        final stepRes = await _client
            .from('device_health_metrics')
            .select('value')
            .eq('user_id', userId)
            .eq('metric_type', 'steps')
            .order('measured_at', ascending: false)
            .limit(1);
        if (stepRes.isNotEmpty) {
          todaySteps = (stepRes[0]['value'] as num).toInt();
        }
      }

      if (todayCalories == 0.0) {
        final calRes = await _client
            .from('device_health_metrics')
            .select('value')
            .eq('user_id', userId)
            .eq('metric_type', 'active_calories')
            .order('measured_at', ascending: false)
            .limit(1);
        if (calRes.isNotEmpty) {
          todayCalories = (calRes[0]['value'] as num).toDouble();
        }
      }

      if (latestHeartRate == null) {
        final hrRes = await _client
            .from('device_health_metrics')
            .select('value')
            .eq('user_id', userId)
            .eq('metric_type', 'heart_rate')
            .order('measured_at', ascending: false)
            .limit(1);
        if (hrRes.isNotEmpty) {
          latestHeartRate = (hrRes[0]['value'] as num).toInt();
        }
      }

      if (latestHRV == null) {
        final hrvRes = await _client
            .from('device_health_metrics')
            .select('value')
            .eq('user_id', userId)
            .eq('metric_type', 'hrv_sdnn')
            .order('measured_at', ascending: false)
            .limit(1);
        if (hrvRes.isNotEmpty) {
          latestHRV = (hrvRes[0]['value'] as num).toDouble();
        }
      }

      if (lastSleepDuration == null) {
        final sleepRes = await _client
            .from('device_health_metrics')
            .select('value')
            .eq('user_id', userId)
            .eq('metric_type', 'sleep_asleep')
            .order('measured_at', ascending: false)
            .limit(1);
        if (sleepRes.isNotEmpty) {
          lastSleepDuration = (sleepRes[0]['value'] as num).toInt();
        }
      }

      return {
        'todaySteps': todaySteps,
        'todayActiveCalories': todayCalories,
        'latestHeartRate': latestHeartRate,
        'latestHRV': latestHRV,
        'lastSleepDuration': lastSleepDuration,
      };
    } catch (e) {
      print('getLatestDailyMetrics error: $e');
      return {};
    }
  }
}
