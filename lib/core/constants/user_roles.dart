/// User Role Enum
///
/// Phase 1: Enum-based approach (synchronous)
/// Phase 3: Data-driven approach (asynchronous) - สำหรับอนาคต
///
/// การใช้งาน:
/// - ใช้ UserRole.admin แทน 'admin' string
/// - ใช้ UserRole.fromValue() แปลงจาก database value
/// - ใช้ UserRole.isAdminValue() แทน role == 'admin'
enum UserRole {
  consumer('consumer', 'ผู้รับบริการ'),
  provider('provider', 'ผู้ให้บริการ'),
  admin('admin', 'ผู้ดูแลระบบ');

  final String value;
  final String displayName;

  const UserRole(this.value, this.displayName);

  /// แปลงจาก string value → Enum
  /// คืนค่า null ถ้าไม่พบ role ที่ตรงกัน
  static UserRole? fromValue(String? value) {
    if (value == null) return null;
    try {
      return UserRole.values.firstWhere(
        (role) => role.value == value,
      );
    } catch (_) {
      return null;
    }
  }

  /// ตรวจสอบว่าเป็น admin หรือไม่
  bool get isAdmin => this == admin;

  /// ตรวจสอบว่าเป็น provider หรือไม่
  bool get isProvider => this == provider;

  /// ตรวจสอบว่าเป็น consumer หรือไม่
  bool get isConsumer => this == consumer;

  /// ตรวจสอบว่าเป็นบทบาทที่กำหนดหรือไม่
  bool hasRole(UserRole required) => this == required;

  /// สำหรับ backward compatibility กับ string
  static bool isAdminValue(String? value) =>
      fromValue(value)?.isAdmin ?? false;
  static bool isProviderValue(String? value) =>
      fromValue(value)?.isProvider ?? false;
  static bool isConsumerValue(String? value) =>
      fromValue(value)?.isConsumer ?? false;

  /// ดึง display name จาก string value
  static String getDisplayName(String? value) {
    return fromValue(value)?.displayName ?? 'ไม่ระบุ';
  }
}
