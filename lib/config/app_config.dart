/// App Configuration
/// ใช้กำหนดค่าต่างๆ ของ Application

class AppConfig {
  // =====================================================
  // DATABASE CONFIGURATION
  // =====================================================

  /// โหมดการทำงาน
  /// - unified: ใช้ทั้ง Local และ Supabase ซิงค์กันอัตโนมัติ (แนะนำสำหรับเครื่องหลัก)
  /// - localOnly: ใช้แค่ Local PostgreSQL
  /// - supabaseOnly: ใช้แค่ Supabase Cloud (แนะนำสำหรับเครื่องรอง/Client)
  static const DatabaseMode databaseMode = DatabaseMode.unified;

  /// เปิดใช้งาน Auto Sync (สำหรับ Unified mode เท่านั้น)
  static const bool enableAutoSync = true;

  /// ช่วงเวลา Sync (วินาที)
  static const int syncIntervalSeconds = 30;

  // =====================================================
  // DEVELOPMENT SERVER (VIDEO PROCESSING / WEBSOCKET)
  // =====================================================

  /// IP ของเครื่องหลัก (Primary Machine) ที่รัน Backend Server
  /// เปลี่ยนเป็น 127.0.0.1 หากรันบนเครื่องเดียวกัน
  static const String mainMachineIp = '192.168.1.142'; // LAN IP ที่ Android/iOS ทุกเครื่องในวงเดียวกันเชื่อมต่อได้

  /// URL ของ WebSocket Server
  static const String localApiUrl = 'http://$mainMachineIp:3000';

  /// URL สำหรับ WebSocket connection
  static const String websocketUrl = 'http://$mainMachineIp:3000';

  // =====================================================
  // SUPABASE CONFIGURATION
  // =====================================================

  /// Supabase Project URL
  /// เปลี่ยนเป็น URL จริงเมื่อสร้าง Supabase Project
  static const String supabaseUrl = 'https://psxcgdwcwjdbpaemkozq.supabase.co';

  /// Supabase Anon Key
  /// เปลี่ยนเป็น Key จริงเมื่อสร้าง Supabase Project
  static const String supabaseAnonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InBzeGNnZHdjd2pkYnBhZW1rb3pxIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzAyNDQzNDQsImV4cCI6MjA4NTgyMDM0NH0.O2OP-tLPW214hQeFUWAFWMTYEn-_RA1MK6TAEJnKGfU';

  /// ตรวจสอบว่า Supabase configured หรือยัง
  static bool get isSupabaseConfigured =>
      supabaseUrl != 'YOUR_SUPABASE_URL' &&
      supabaseAnonKey != 'YOUR_SUPABASE_ANON_KEY';

  // =====================================================
  // APP INFORMATION
  // =====================================================

  /// ชื่อ App
  static const String appName = 'Sheserved';

  /// เวอร์ชัน
  static const String appVersion = '1.0.0';

  /// Build Number
  static const int buildNumber = 1;

  // =====================================================
  // FEATURE FLAGS
  // =====================================================

  /// เปิดใช้งาน Location Tracking
  static const bool enableLocationTracking = true;

  /// เปิดใช้งาน Push Notifications
  static const bool enablePushNotifications = false;

  /// เปิดใช้งาน Debug Mode
  static const bool debugMode = true;

  // =====================================================
  // OTP CONFIGURATION
  // =====================================================

  /// ใช้ Console OTP (ทดสอบ - ไม่ส่ง SMS จริง)
  /// true = แสดง OTP ใน Console (ฟรี สำหรับ development)
  /// false = ส่ง SMS จริงผ่าน Supabase/Twilio (มีค่าใช้จ่าย)
  static const bool useConsoleOtp = true;

  /// เปิดใช้งาน OTP Verification
  static const bool enableOtpVerification = true;

  /// OTP หมดอายุ (นาที)
  static const int otpExpiryMinutes = 5;

  /// จำนวนครั้งที่ลองใส่ OTP ผิดได้
  static const int otpMaxRetries = 3;

  // =====================================================
  // VEGA AI (EIDY) CONFIGURATION
  // =====================================================

  /// โหมดการทำงานของ Vega AI
  /// - mock: ใช้ข้อมูลจำลอง (ฟรี 100% สำหรับ Development)
  /// - live: เชื่อมต่อ API จริงของ Vega (ใช้โควตา Free Tier/เสียเงิน)
  static const VegaAiMode vegaAiMode = VegaAiMode.mock;

  /// ขีดจำกัดจำนวนครั้งที่เรียกใช้ AI ต่อวันต่อผู้ใช้ (Free Tier Protection)
  static const int maxDailyVegaQueries = 5;

  /// ปุ่มตัดการทำงานฉุกเฉิน (Kill-Switch)
  /// หากเป็น true ระบบ AI จะหยุดทำงานทันทีเพื่อป้องกันค่าใช้จ่ายส่วนเกิน
  static const bool vegaAiKillSwitch = false;

  /// API Key สำหรับ Vega (เก็บไว้ใน Environment Variables จะดีกว่า)
  static const String vegaApiKey = 'DEVELOPMENT_MOCK_KEY';

  // =====================================================
  // GOOGLE MAPS CONFIGURATION
  // =====================================================

  /// Google Maps API Key (ใช้สำหรับ Directions API)
  static const String googleMapsApiKey =
      'AIzaSyB_cex2WRkdTKElFJ-Cjgsfhm0kk1AZkcQ';

  // =====================================================
  // LEGACY SUPPORT
  // =====================================================

  /// (Deprecated) ใช้ useLocalDatabase สำหรับ backward compatibility
  static bool get useLocalDatabase =>
      databaseMode == DatabaseMode.localOnly ||
      databaseMode == DatabaseMode.unified;

  /// Get current time in Thailand (GMT+7) forced
  static DateTime get thailandNow => DateTime.now().toUtc().add(const Duration(hours: 7));

  /// Get current UTC time
  static DateTime get currentUtc => DateTime.now().toUtc();

  /// Convert any DateTime to Thailand time (GMT+7)
  /// If [dateTime] is already in Thailand time, this might double-convert if not careful.
  /// But assuming inputs are UTC from DB.
  static DateTime toThailand(DateTime dateTime) {
    return dateTime.toUtc().add(const Duration(hours: 7));
  }
}

/// Database Mode
enum DatabaseMode {
  /// ใช้ทั้ง Local และ Supabase ซิงค์กันอัตโนมัติ
  unified,

  /// ใช้แค่ Local PostgreSQL (offline mode)
  localOnly,

  /// ใช้แค่ Supabase Cloud
  supabaseOnly,
}

/// Vega AI Mode
enum VegaAiMode {
  /// ใช้ข้อมูลจำลอง (ฟรี 100%)
  mock,

  /// เชื่อมต่อ API จริง (ใช้โควตา)
  live,
}
