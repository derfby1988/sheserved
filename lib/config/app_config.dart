/// App Configuration
/// ใช้กำหนดค่าต่างๆ ของ Application

class AppConfig {
  // =====================================================
  // DATABASE CONFIGURATION
  // =====================================================
  
  /// โหมดการทำงาน
  /// - unified: ใช้ทั้ง Local และ Supabase ซิงค์กันอัตโนมัติ (แนะนำ)
  /// - localOnly: ใช้แค่ Local PostgreSQL
  /// - supabaseOnly: ใช้แค่ Supabase Cloud
  static const DatabaseMode databaseMode = DatabaseMode.unified;

  /// เปิดใช้งาน Auto Sync
  static const bool enableAutoSync = true;

  /// ช่วงเวลา Sync (วินาที)
  static const int syncIntervalSeconds = 30;

  // =====================================================
  // LOCAL DATABASE (WebSocket Server)
  // =====================================================
  
  /// URL ของ WebSocket Server (Local)
  static const String localApiUrl = 'http://localhost:3000';
  
  /// URL สำหรับ WebSocket connection
  static const String websocketUrl = 'http://localhost:3000';

  // =====================================================
  // SUPABASE CONFIGURATION
  // =====================================================
  
  /// Supabase Project URL
  /// เปลี่ยนเป็น URL จริงเมื่อสร้าง Supabase Project
  static const String supabaseUrl = 'https://psxcgdwcwjdbpaemkozq.supabase.co';
  
  /// Supabase Anon Key
  /// เปลี่ยนเป็น Key จริงเมื่อสร้าง Supabase Project
  static const String supabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InBzeGNnZHdjd2pkYnBhZW1rb3pxIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzAyNDQzNDQsImV4cCI6MjA4NTgyMDM0NH0.O2OP-tLPW214hQeFUWAFWMTYEn-_RA1MK6TAEJnKGfU';

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
  // LEGACY SUPPORT
  // =====================================================
  
  /// (Deprecated) ใช้ useLocalDatabase สำหรับ backward compatibility
  static bool get useLocalDatabase => 
      databaseMode == DatabaseMode.localOnly || 
      databaseMode == DatabaseMode.unified;
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
