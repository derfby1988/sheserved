import 'package:flutter_test/flutter_test.dart';
import 'package:sheserved/features/auth/data/models/password_change_result.dart';

void main() {
  group('PasswordChangeResult', () {
    test('contains all expected values', () {
      const results = PasswordChangeResult.values;

      expect(results, contains(PasswordChangeResult.success));
      expect(results, contains(PasswordChangeResult.unauthorized));
      expect(results, contains(PasswordChangeResult.currentPasswordIncorrect));
      expect(results, contains(PasswordChangeResult.invalidPassword));
      expect(results, contains(PasswordChangeResult.socialAccountNoPassword));
      expect(results, contains(PasswordChangeResult.tooManyAttempts));
      expect(results, contains(PasswordChangeResult.unsupportedOffline));
      expect(results, contains(PasswordChangeResult.failed));
    });

    test('success and failed are distinguishable', () {
      expect(PasswordChangeResult.success, isNot(equals(PasswordChangeResult.failed)));
      expect(PasswordChangeResult.success.name, 'success');
      expect(PasswordChangeResult.failed.name, 'failed');
    });
  });
}
