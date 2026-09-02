/// Central password policy used by registration and change-password flows.
///
/// This ensures the minimum length requirement is consistent across the app
/// and gives a single source of truth for password validation messages.
class PasswordPolicy {
  const PasswordPolicy._();

  /// Minimum password length in characters.
  static const int minLength = 8;

  /// Localized validation message that incorporates [minLength].
  static String get minLengthMessage =>
      'รหัสผ่านต้องมีอย่างน้อย $minLength ตัวอักษร';
}
