import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// PlatformService - จัดการ Logic เกี่ยวกับความแตกต่างของแต่ละแพลตฟอร์ม (Web/iOS/Android)
/// ช่วยให้การบำรุงรักษาโค้ดทำได้จากที่เดียว (Centralized Logic)
class PlatformService {
  
  /// ตรวจสอบว่าเป็น Web หรือไม่
  static bool get isWeb => kIsWeb;
  
  /// ตรวจสอบว่าเป็น iOS หรือไม่
  static bool get isIOS => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
  
  /// ตรวจสอบว่าเป็น Android หรือไม่
  static bool get isAndroid => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  // สวิตช์หลักสำหรับเปิด/ปิดแผนที่บน Web
  static bool _isWebMapEnabled = false; 

  // สถานะเปิด/ปิดแผนที่แยกตามหน้าจอ (สำหรับ Web)
  static Map<String, bool> _webMapSettings = {
    'home': true,
    'rescue': false,
    'emergency': true,
  };

  /// อัปเดตสถานะเปิด/ปิดแผนที่บน Web ทั้งหมด
  static void setWebMapEnabled(bool value) {
    _isWebMapEnabled = value;
  }

  /// ตรวจสอบสถานะ Master Switch ของ Web Map
  static bool get isWebMapEnabled => _isWebMapEnabled;

  /// อัปเดตการตั้งค่าแผนที่รายหน้าจอ (ใช้โดย Admin)
  static void updateWebMapSetting(String pageName, bool value) {
    _webMapSettings[pageName] = value;
  }

  /// ตรวจสอบว่าควรแสดงแผนที่จริง (Interactive Google Map) หรือไม่
  /// สามารถระบุ [pageName] เพื่อเช็คแยกรายหน้าจอได้ (เช่น 'home', 'rescue', 'emergency')
  static bool shouldShowLiveMap({String? pageName}) {
    if (kIsWeb) {
      // ถ้า Master Switch ปิดอยู่ ให้ปิดทุกหน้า
      if (!_isWebMapEnabled) return false;

      if (pageName != null && _webMapSettings.containsKey(pageName)) {
        return _webMapSettings[pageName]!;
      }
      return false; // Default for Web if unknown page
    }
    return true; // Always live on Mobile
  }
  
  /// URL รูปภาพทดแทนแผนที่ (Fallback Image)
  static String get mapFallbackImageUrl => 
    'https://images.unsplash.com/photo-1526778548025-fa2f459cd5c1?auto=format&fit=crop&q=80&w=1000';

  /// ข้อความแจ้งเตือนเมื่อแผนที่ถูกปิดใช้งาน
  static String get mapDisabledMessage => 
    'แผนที่ถูกปิดใช้งานบนเบราว์เซอร์เพื่อความรวดเร็วและประหยัดข้อมูล';

  /// บันทึกการโหลดแผนที่ (ใช้สำหรับนับโควต้า/ประมาณการค่าใช้จ่าย)
  /// [pageName] คือชื่อหน้าจอที่เรียกใช้แผนที่ เช่น 'home', 'rescue', 'emergency'
  static Future<void> logMapLoad({String pageName = 'unknown'}) async {
    final platform = kIsWeb ? 'web' : (defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android');
    final metricName = 'map_load_$pageName';
    
    try {
      // 1. บันทึกแยกตามหน้าจอ
      await Supabase.instance.client.rpc(
        'increment_platform_metric', 
        params: {'p_platform': platform, 'p_metric_name': metricName}
      );
      
      // 2. บันทึกรวม (Total) เพื่อใช้คำนวณค่าใช้จ่ายรวม
      await Supabase.instance.client.rpc(
        'increment_platform_metric', 
        params: {'p_platform': platform, 'p_metric_name': 'map_loads_total'}
      );
    } catch (e) {
      debugPrint('Error logging map load for $pageName: $e');
    }
  }

  /// ดึงข้อมูลสถิติการใช้งาน
  static Future<List<Map<String, dynamic>>> getMetrics() async {
    try {
      final data = await Supabase.instance.client
          .from('platform_metrics')
          .select()
          .order('count', ascending: false);
      return List<Map<String, dynamic>>.from(data);
    } catch (e) {
      debugPrint('Error fetching metrics: $e');
      return [];
    }
  }
}
