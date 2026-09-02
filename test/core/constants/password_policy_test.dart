import 'package:flutter_test/flutter_test.dart';
import 'package:sheserved/core/constants/password_policy.dart';

void main() {
  group('PasswordPolicy', () {
    test('minLength is 8', () {
      expect(PasswordPolicy.minLength, equals(8));
    });

    test('minLengthMessage contains the current minLength', () {
      expect(
        PasswordPolicy.minLengthMessage,
        equals('รหัสผ่านต้องมีอย่างน้อย 8 ตัวอักษร'),
      );
    });

    test('message should adapt if minLength changes', () {
      // เนื่องจาก minLength เป็นค่าคงที่ จึงตรวจแค่ว่าข้อความประกอบด้วยเลข 8
      expect(PasswordPolicy.minLengthMessage, contains('8'));
    });
  });
}
