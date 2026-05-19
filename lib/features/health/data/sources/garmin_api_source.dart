import 'health_data_source.dart';

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
    // ต้องเปิดหน้าเว็บ Webview เพื่อทำกระบวนการ OAuth2 Login กับเว็บ Garmin
    // และรับ Token กลับมาเซฟไว้
    return true; 
  }

  @override
  Future<bool> hasPermissions() async {
    // ตรวจสอบว่าในเครื่องมี Access Token ของ Garmin บันทึกไว้แล้วหรือไม่
    return false;
  }

  @override
  Future<void> revokeAccess() async {
    // ลบ Access Token ออกจากเครื่อง และยิง API ไปบอก Garmin ให้ยกเลิก Token
  }

  @override
  Future<int> fetchTodaySteps() async {
    // โค้ดยิง HTTP GET Request ไปที่ Garmin Health API 
    // endpoint: /wellness-api/rest/steps
    return 0;
  }

  @override
  Future<int?> fetchLatestHeartRate() async {
    return null;
  }

  @override
  Future<int?> fetchLastSleepDuration() async {
    return null;
  }
}
