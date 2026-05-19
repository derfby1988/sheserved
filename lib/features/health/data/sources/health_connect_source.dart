import 'dart:io';
import 'package:health/health.dart';
import 'health_data_source.dart';

class HealthConnectSource implements HealthDataSource {
  final Health _health = Health();
  
  // ชนิดข้อมูลที่ต้องการอ่าน (ตัวอย่าง: ก้าวเดิน, หัวใจ)
  final types = [
    HealthDataType.STEPS,
    HealthDataType.HEART_RATE,
    HealthDataType.SLEEP_SESSION,
  ];

  @override
  String get sourceName => 'Health Connect';

  @override
  Future<bool> isAvailable() async {
    return Platform.isAndroid;
  }

  @override
  Future<bool> requestPermissions() async {
    try {
      // ติดตั้งและคอนฟิกเพื่อใช้ Health Connect API โดยเฉพาะ
      Health().configure();
      
      bool granted = await _health.requestAuthorization(types);
      return granted;
    } catch (e) {
      print('Health Connect request error: $e');
      return false;
    }
  }

  @override
  Future<bool> hasPermissions() async {
    try {
      bool? hasPerm = await _health.hasPermissions(types);
      return hasPerm ?? false;
    } catch (e) {
      return false;
    }
  }

  @override
  Future<void> revokeAccess() async {
    // ใน Android ผู้ใช้ต้องเข้าไปยกเลิกในแอป Health Connect
    await _health.revokePermissions();
  }

  @override
  Future<int> fetchTodaySteps() async {
    final now = DateTime.now();
    final midnight = DateTime(now.year, now.month, now.day);
    
    try {
      int? steps = await _health.getTotalStepsInInterval(midnight, now);
      return steps ?? 0;
    } catch (e) {
      print('Fetch steps error: $e');
      return 0;
    }
  }

  @override
  Future<int?> fetchLatestHeartRate() async {
    final now = DateTime.now();
    final yesterday = now.subtract(const Duration(days: 1));
    
    try {
      List<HealthDataPoint> healthData = await _health.getHealthDataFromTypes(
        types: [HealthDataType.HEART_RATE],
        startTime: yesterday,
        endTime: now,
      );

      if (healthData.isNotEmpty) {
        healthData.sort((a, b) => b.dateTo.compareTo(a.dateTo));
        return (healthData.first.value as NumericHealthValue).numericValue.toInt();
      }
      return null;
    } catch (e) {
      print('Fetch HR error: $e');
      return null;
    }
  }

  @override
  Future<int?> fetchLastSleepDuration() async {
    return null;
  }
}
