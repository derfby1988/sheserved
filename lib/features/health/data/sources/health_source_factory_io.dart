import '../../../../services/platform_service.dart';
import 'apple_health_source.dart';
import 'health_connect_source.dart';
import 'health_data_source.dart';

/// สร้าง HealthDataSource ตาม platform — iOS = Apple Health, Android = Health Connect
/// คืน null เมื่อ platform ไม่รองรับ
HealthDataSource? createPlatformHealthSource() {
  if (PlatformService.isIOS) return AppleHealthSource();
  if (PlatformService.isAndroid) return HealthConnectSource();
  return null;
}
