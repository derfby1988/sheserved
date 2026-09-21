import 'health_data_source.dart';

/// Web ไม่รองรับ Health Connect / Apple Health — คืน null ให้ provider
/// แสดงสถานะ 'OS not supported' ตาม flow เดิม
HealthDataSource? createPlatformHealthSource() => null;
