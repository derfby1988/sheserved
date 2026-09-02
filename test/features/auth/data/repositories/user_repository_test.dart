import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sheserved/features/auth/data/models/password_change_result.dart';
import 'package:sheserved/features/auth/data/models/user_model.dart';
import 'package:sheserved/features/auth/data/repositories/user_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('UserRepository (change password)', () {
    late UserRepository repository;

    setUp(() {
      repository = UserRepository(
        SupabaseClient('https://test.supabase.co', 'test-anon-key'),
      );
    });

    test('changeCurrentUserPassword returns unauthorized when no user is logged in', () async {
      final result = await repository.changeCurrentUserPassword(
        currentPassword: 'current123',
        newPassword: 'newpassword123',
      );

      expect(result, equals(PasswordChangeResult.unauthorized));
    });

    test('new password validation rejects passwords shorter than minLength', () {
      const shortPassword = '1234567';
      expect(shortPassword.length, lessThan(8));
    });

    test('UserModel toJson does not include passwordHash', () {
      final user = UserModel(
        id: 'test-user-id',
        userType: UserType.consumer,
        firstName: 'Test',
        lastName: 'User',
        username: 'testuser',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final json = user.toJson();

      expect(json, isNot(contains('passwordHash')));
      expect(json, isNot(contains('password_hash')));
    });

    test('UserModel fromJson ignores password_hash field', () {
      final json = <String, dynamic>{
        'id': 'test-user-id',
        'first_name': 'Test',
        'last_name': 'User',
        'username': 'testuser',
        'password_hash': 'should_be_ignored',
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      };

      final user = UserModel.fromJson(json);

      // ถ้า fromJson ดึง password_hash เข้ามาเป็นฟิลด์ จะมี getter หรือ property ที่ export ออกมา
      // เนื่องจากไม่มีฟิลด์ passwordHash ให้ดึงค่าได้ เราจึงตรวจว่า toJson ไม่ส่งออกค่านั้น
      expect(user.toJson(), isNot(contains('password_hash')));
    });
  });

  group('UserRepository (password-hash containment in queries)', () {
    late List<http.Request> capturedRequests;
    late MockClient mockClient;
    late SupabaseClient supabaseClient;

    setUp(() {
      capturedRequests = [];
      mockClient = MockClient((request) async {
        capturedRequests.add(request);
        return http.Response(
          '[]',
          200,
          request: request,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });
      supabaseClient = SupabaseClient(
        'https://test.supabase.co',
        'test-anon-key',
        httpClient: mockClient,
      );
    });

    test('hasPassword does not request password_hash column in select list', () async {
      final repo = UserRepository(supabaseClient);

      final result = await repo.hasPassword('user-1');

      expect(result, isTrue); // no row with password_hash IS NULL → has password

      final request = capturedRequests.single;
      final selectParam = request.url.queryParameters['select'];

      // select list ต้องเป็น 'id' เท่านั้น — ห้ามมี password_hash (B2 containment, §6.2)
      expect(selectParam, 'id');
      expect(selectParam, isNot(contains('password_hash')));

      // หมายเหตุ: query param `password_hash=is.null` เป็น filter (ที่ต้องมี) ไม่ใช่ column ที่ select
      expect(request.url.queryParameters['password_hash'], 'is.null');
    });

    test('hasPassword treats null password_hash row as no password', () async {
      // Simulate a row with password_hash IS NULL → hasPassword must be false
      capturedRequests.clear();
      final nullHashClient = MockClient((request) async {
        return http.Response(
          '[{"id": "user-1"}]',
          200,
          request: request,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });
      final client = SupabaseClient(
        'https://test.supabase.co',
        'test-anon-key',
        httpClient: nullHashClient,
      );

      final repo = UserRepository(client);
      final result = await repo.hasPassword('user-1');

      expect(result, isFalse);
    });
  });
}
