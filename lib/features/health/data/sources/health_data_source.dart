abstract class HealthDataSource {
  /// ชื่อของแหล่งข้อมูล เช่น 'Apple Health', 'Health Connect', 'Garmin'
  String get sourceName;

  /// ตรวจสอบว่าอุปกรณ์รองรับ API นี้หรือไม่
  Future<bool> isAvailable();

  /// ร้องขอสิทธิ์การเข้าถึงข้อมูลจาก OS หรือเชื่อมต่อ OAuth
  Future<bool> requestPermissions();

  /// ตรวจสอบว่าแอปได้รับสิทธิ์หรือยัง
  Future<bool> hasPermissions();

  /// ยกเลิกการเข้าถึงข้อมูล (ถ้าทำได้)
  Future<void> revokeAccess();

  /// --- Data Fetching Methods ---
  
  /// ดึงข้อมูลก้าวเดินของวันนี้
  Future<int> fetchTodaySteps();

  /// ดึงข้อมูลอัตราการเต้นของหัวใจล่าสุด
  Future<int?> fetchLatestHeartRate();

  /// ดึงข้อมูลระยะเวลาการนอนหลับล่าสุด (นาที)
  Future<int?> fetchLastSleepDuration();
}
