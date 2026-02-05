/// Sync Configuration - กำหนดค่า Synchronization
/// ร้านค้าสามารถปรับแต่งได้ตามต้องการ
/// 
/// ⚠️ คำเตือน: การเพิ่มความถี่ sync จะเพิ่มค่าใช้จ่าย Supabase
/// 
/// ค่าใช้จ่าย Supabase (ประมาณ):
/// - Free tier: 500MB database, 2GB bandwidth/เดือน
/// - Pro ($25/เดือน): 8GB database, 50GB bandwidth
/// 
/// แนะนำ:
/// - ร้านเล็ก (1-5 พนักงาน): 60 วินาที
/// - ร้านกลาง (5-20 พนักงาน): 30 วินาที
/// - ร้านใหญ่ (20+ พนักงาน): 15-30 วินาที + ใช้แผน Pro

class SyncConfig {
  // =====================================================
  // SYNC TIMING - กำหนดเวลา Sync
  // =====================================================
  
  /// ความถี่ Sync อัตโนมัติ (วินาที)
  /// ค่าเริ่มต้น: 30 วินาที
  /// แนะนำ: 30-60 วินาที สำหรับ Free tier
  static int syncIntervalSeconds = 30;
  
  /// ความถี่ Sync สำหรับข้อมูลสำคัญ (วินาที)
  /// เช่น ออเดอร์ใหม่, การชำระเงิน
  /// ค่าเริ่มต้น: 5 วินาที
  static int criticalSyncIntervalSeconds = 5;
  
  /// Timeout สำหรับ Sync (วินาที)
  /// ถ้า sync นานกว่านี้จะยกเลิก
  static int syncTimeoutSeconds = 30;

  // =====================================================
  // SYNC BEHAVIOR - พฤติกรรม Sync
  // =====================================================
  
  /// เปิด/ปิด Auto Sync
  static bool enableAutoSync = true;
  
  /// Sync เมื่อ App เปิดขึ้นมา
  static bool syncOnAppStart = true;
  
  /// Sync เมื่อกลับมาจาก Background
  static bool syncOnResume = true;
  
  /// Sync ก่อนปิด App
  static bool syncOnPause = false;
  
  /// Sync เฉพาะเมื่อต่อ WiFi (ประหยัด data มือถือ)
  static bool syncOnlyOnWifi = false;

  // =====================================================
  // BATCH SETTINGS - การจัดกลุ่ม Sync
  // =====================================================
  
  /// จำนวน records สูงสุดต่อ batch
  /// ลดค่านี้ถ้า sync ช้า
  static int maxRecordsPerBatch = 100;
  
  /// รอกี่วินาทีก่อน sync การเปลี่ยนแปลง (debounce)
  /// ป้องกัน sync บ่อยเกินไปเมื่อพิมพ์
  static int debounceSeconds = 2;

  // =====================================================
  // TABLE PRIORITIES - ลำดับความสำคัญ
  // =====================================================
  
  /// ตารางที่ต้อง sync ทันที (Critical)
  static const List<String> criticalTables = [
    'orders',
    'payments',
    'queue_tickets',
  ];
  
  /// ตารางที่ sync ตามปกติ (Normal)
  static const List<String> normalTables = [
    'users',
    'registration_applications',
    'locations',
  ];
  
  /// ตารางที่ sync ไม่บ่อย (Low Priority)
  static const List<String> lowPriorityTables = [
    'professions',
    'registration_field_configs',
    'articles',
  ];

  // =====================================================
  // OFFLINE QUEUE - คิว Offline
  // =====================================================
  
  /// จำนวน operations สูงสุดใน offline queue
  static int maxOfflineQueueSize = 1000;
  
  /// เก็บ offline queue กี่วัน
  static int offlineQueueRetentionDays = 7;

  // =====================================================
  // COST ESTIMATION - ประมาณค่าใช้จ่าย
  // =====================================================
  
  /// ประมาณ requests ต่อวัน
  static int get estimatedDailyRequests {
    if (!enableAutoSync) return 0;
    
    final syncPerMinute = 60 / syncIntervalSeconds;
    final syncPerHour = syncPerMinute * 60;
    final syncPerDay = syncPerHour * 12; // สมมติเปิดร้าน 12 ชม.
    
    // คูณด้วยจำนวน tables
    return (syncPerDay * (criticalTables.length + normalTables.length + lowPriorityTables.length)).round();
  }
  
  /// ประมาณ requests ต่อเดือน
  static int get estimatedMonthlyRequests => estimatedDailyRequests * 30;
  
  /// เตือนถ้าใกล้ถึง limit ของ Free tier
  static bool get isNearingFreeLimit => estimatedMonthlyRequests > 400000;
  
  /// แนะนำแผนที่เหมาะสม
  static String get recommendedPlan {
    if (estimatedMonthlyRequests < 100000) return 'Free';
    if (estimatedMonthlyRequests < 500000) return 'Free (ระวัง limit)';
    if (estimatedMonthlyRequests < 2000000) return 'Pro (\$25/เดือน)';
    return 'Team (\$599/เดือน)';
  }

  // =====================================================
  // PRESETS - ค่าที่ตั้งไว้ล่วงหน้า
  // =====================================================
  
  /// ใช้ค่าประหยัด (สำหรับร้านเล็ก / Free tier)
  static void useEconomyMode() {
    syncIntervalSeconds = 60;
    criticalSyncIntervalSeconds = 10;
    syncOnlyOnWifi = true;
    maxRecordsPerBatch = 50;
  }
  
  /// ใช้ค่ามาตรฐาน (สำหรับร้านกลาง)
  static void useStandardMode() {
    syncIntervalSeconds = 30;
    criticalSyncIntervalSeconds = 5;
    syncOnlyOnWifi = false;
    maxRecordsPerBatch = 100;
  }
  
  /// ใช้ค่าเร็วสุด (สำหรับร้านใหญ่ / Pro tier)
  static void usePerformanceMode() {
    syncIntervalSeconds = 15;
    criticalSyncIntervalSeconds = 3;
    syncOnlyOnWifi = false;
    maxRecordsPerBatch = 200;
  }
  
  /// ปิด Auto Sync (Manual sync เท่านั้น)
  static void useManualMode() {
    enableAutoSync = false;
    syncOnAppStart = true;
    syncOnResume = true;
  }
}

/// Sync Mode Presets
enum SyncModePreset {
  /// ประหยัด - sync ทุก 60 วินาที
  economy,
  
  /// มาตรฐาน - sync ทุก 30 วินาที
  standard,
  
  /// ประสิทธิภาพสูง - sync ทุก 15 วินาที
  performance,
  
  /// Manual - sync เมื่อกดปุ่มเท่านั้น
  manual,
}

extension SyncModePresetExtension on SyncModePreset {
  void apply() {
    switch (this) {
      case SyncModePreset.economy:
        SyncConfig.useEconomyMode();
        break;
      case SyncModePreset.standard:
        SyncConfig.useStandardMode();
        break;
      case SyncModePreset.performance:
        SyncConfig.usePerformanceMode();
        break;
      case SyncModePreset.manual:
        SyncConfig.useManualMode();
        break;
    }
  }
  
  String get displayName {
    switch (this) {
      case SyncModePreset.economy:
        return 'ประหยัด (60 วินาที)';
      case SyncModePreset.standard:
        return 'มาตรฐาน (30 วินาที)';
      case SyncModePreset.performance:
        return 'เร็วสุด (15 วินาที)';
      case SyncModePreset.manual:
        return 'Manual (กดปุ่ม)';
    }
  }
  
  String get description {
    switch (this) {
      case SyncModePreset.economy:
        return 'เหมาะสำหรับร้านเล็ก หรือใช้ Supabase Free tier';
      case SyncModePreset.standard:
        return 'เหมาะสำหรับร้านทั่วไป ข้อมูล sync เร็วพอสมควร';
      case SyncModePreset.performance:
        return 'เหมาะสำหรับร้านใหญ่ ต้องการข้อมูล real-time (แนะนำ Pro tier)';
      case SyncModePreset.manual:
        return 'ประหยัดที่สุด sync เมื่อต้องการเท่านั้น';
    }
  }
  
  String get estimatedCost {
    switch (this) {
      case SyncModePreset.economy:
        return 'Free tier พอ';
      case SyncModePreset.standard:
        return 'Free tier พอ (ระวัง limit)';
      case SyncModePreset.performance:
        return 'แนะนำ Pro tier (\$25/เดือน)';
      case SyncModePreset.manual:
        return 'Free tier พอ';
    }
  }
}
