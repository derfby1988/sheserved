import '../models/device_health_metric.dart';

/// Abstract interface สำหรับ Health Data Source ทุกประเภท
abstract class HealthDataSource {
  /// ชื่อของแหล่งข้อมูล
  String get sourceName;

  Future<bool> isAvailable();
  Future<bool> requestPermissions();
  Future<bool> hasPermissions();
  Future<void> revokeAccess();

  // ---- Quick Summary Methods (แสดงใน UI) ----

  Future<int> fetchTodaySteps();
  Future<int?> fetchLatestHeartRate();
  Future<int?> fetchLastSleepDuration(); // นาที
  Future<double?> fetchTodayActiveCalories(); // kcal
  Future<double?> fetchTodayDistance(); // เมตร
  Future<double?> fetchLatestBloodOxygen(); // % (0-100)
  Future<double?> fetchLatestHRV(); // ms
  Future<int?> fetchTodayExerciseTime(); // นาที

  // ---- Full Sync Method (บันทึกลง Supabase) ----
  Future<List<DeviceHealthMetric>> fetchAllMetrics({
    required String userId,
    required DateTime from,
    required DateTime to,
  });
}
