import 'package:flutter_test/flutter_test.dart';
import 'package:sheserved/core/constants/user_roles.dart';

void main() {
  group('UserRole Enum', () {
    test('should parse string values correctly', () {
      expect(UserRole.fromValue('admin'), UserRole.admin);
      expect(UserRole.fromValue('provider'), UserRole.provider);
      expect(UserRole.fromValue('consumer'), UserRole.consumer);
    });

    test('should return null for unknown values', () {
      expect(UserRole.fromValue('unknown'), isNull);
    });

    test('should return null for null input', () {
      expect(UserRole.fromValue(null), isNull);
    });

    test('should have correct display names', () {
      expect(UserRole.admin.displayName, 'ผู้ดูแลระบบ');
      expect(UserRole.provider.displayName, 'ผู้ให้บริการ');
      expect(UserRole.consumer.displayName, 'ผู้รับบริการ');
    });

    test('should validate roles correctly', () {
      expect(UserRole.admin.isAdmin, true);
      expect(UserRole.provider.isAdmin, false);
      expect(UserRole.consumer.isAdmin, false);
      expect(UserRole.provider.isProvider, true);
      expect(UserRole.admin.isProvider, false);
      expect(UserRole.consumer.isConsumer, true);
    });

    test('backward compatibility helpers work', () {
      expect(UserRole.isAdminValue('admin'), true);
      expect(UserRole.isAdminValue('provider'), false);
      expect(UserRole.isAdminValue(null), false);
      expect(UserRole.isProviderValue('provider'), true);
      expect(UserRole.isProviderValue('admin'), false);
      expect(UserRole.isConsumerValue('consumer'), true);
    });

    test('getDisplayName returns correct names', () {
      expect(UserRole.getDisplayName('admin'), 'ผู้ดูแลระบบ');
      expect(UserRole.getDisplayName('provider'), 'ผู้ให้บริการ');
      expect(UserRole.getDisplayName('consumer'), 'ผู้รับบริการ');
      expect(UserRole.getDisplayName('unknown'), 'ไม่ระบุ');
      expect(UserRole.getDisplayName(null), 'ไม่ระบุ');
    });

    test('hasRole works correctly', () {
      expect(UserRole.admin.hasRole(UserRole.admin), true);
      expect(UserRole.admin.hasRole(UserRole.provider), false);
      expect(UserRole.provider.hasRole(UserRole.provider), true);
    });

    test('value property returns correct string', () {
      expect(UserRole.admin.value, 'admin');
      expect(UserRole.provider.value, 'provider');
      expect(UserRole.consumer.value, 'consumer');
    });
  });
}
