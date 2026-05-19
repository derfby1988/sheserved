import 'health_data_source.dart';
import '../models/device_health_metric.dart';

/// Garmin API Source - ตัวอย่าง Stub สำหรับการเชื่อมต่อผ่าน Cloud OAuth2
/// ยังไม่ได้ Implement จริง - รอการเปิดใช้งาน Garmin Connect API
class GarminApiSource implements HealthDataSource {
  @override
  String get sourceName => 'Garmin Connect';

  @override
  Future<bool> isAvailable() async {
    // Garmin เป็น Cloud API ดังนั้นจึงรองรับทุก Platform
    return true;
  }

  @override
  Future<bool> requestPermissions() async {
    // TODO: เปิดหน้าเว็บ Webview เพื่อทำกระบวนการ OAuth2 Login กับ Garmin
    // และรับ Access Token กลับมาเซฟไว้ใน SecureStorage
    return true;
  }

  @override
  Future<bool> hasPermissions() async {
    // TODO: ตรวจสอบว่าในเครื่องมี Access Token ของ Garmin บันทึกไว้แล้วหรือไม่
    return false;
  }

  @override
  Future<void> revokeAccess() async {
    // TODO: ลบ Access Token ออกจากเครื่อง
    // และยิง Garmin API เพื่อยกเลิก Token
  }

  @override
  Future<int> fetchTodaySteps() async {
    // TODO: ยิง HTTP GET Request ไปที่ Garmin Health API
    // endpoint: /wellness-api/rest/steps
    return 0;
  }

  @override
  Future<int?> fetchLatestHeartRate() async {
    // TODO: ยิง Garmin API
    return null;
  }

  @override
  Future<int?> fetchLastSleepDuration() async => null;

  @override
  Future<double?> fetchTodayActiveCalories() async => null;

  @override
  Future<double?> fetchTodayDistance() async => null;

  @override
  Future<double?> fetchLatestBloodOxygen() async => null;

  @override
  Future<double?> fetchLatestHRV() async => null;

  @override
  Future<int?> fetchTodayExerciseTime() async => null;

  @override
  Future<List<DeviceHealthMetric>> fetchAllMetrics({
    required String userId,
    required DateTime from,
    required DateTime to,
  }) async {
    // TODO: ยิง Garmin API เพื่อดึงข้อมูลทั้งหมดในช่วง from-to
    // เช่น steps, heart rate, sleep, calories จาก Garmin Connect
    return [];
  }
}
