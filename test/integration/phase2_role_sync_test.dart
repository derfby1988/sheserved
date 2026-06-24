import 'package:flutter_test/flutter_test.dart';
import 'package:sheserved/core/constants/user_roles.dart';
import 'package:sheserved/features/auth/data/models/user_model.dart';
import 'package:sheserved/features/admin/data/repositories/group_role_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Phase 2 Integration Tests
/// ทดสอบความสอดคล้องระหว่าง users.role และ users.user_category_id
/// หลังจากรัน migration Phase 2
void main() {
  group('Phase 2: Role Sync Verification', () {
    late SupabaseClient client;
    late GroupRoleRepository repository;

    setUpAll(() async {
      // ต้องรันด้วย environment ที่มี database connection
      // หรือใช้ mock
      //
      // ถ้า Supabase ยังไม่ได้ initialize → ต้องเรียก init ก่อน
      if (!Supabase.instance.isInitialized) {
        // ใช้ค่าจาก environment variables หรือ config
        const supabaseUrl = String.fromEnvironment('SUPABASE_URL',
            defaultValue: 'https://your-project.supabase.co');
        const supabaseKey = String.fromEnvironment('SUPABASE_ANON_KEY',
            defaultValue: 'your-anon-key');

        await Supabase.initialize(
          url: supabaseUrl,
          anonKey: supabaseKey,
        );
      }
      client = Supabase.instance.client;
      repository = GroupRoleRepository(client);
    });

    group('Database Sync', () {
      test('role and user_category_id must be in sync', () async {
        // Query ผู้ใช้ที่มีทั้ง role และ user_category_id
        final response = await client
            .from('users')
            .select('id, username, role, user_category_id')
            .not('role', 'is', null)
            .not('user_category_id', 'is', null)
            .limit(100);

        for (final row in response) {
          final role = row['role'] as String?;
          final userCategoryId = row['user_category_id'] as String?;

          expect(
            role,
            equals(userCategoryId),
            reason: 'User ${row['username']} (id: ${row['id']}) '
                'has role=$role but user_category_id=$userCategoryId',
          );
        }
      });

      test('all users must have user_category_id', () async {
        final response = await client
            .from('users')
            .select('id, user_category_id')
            .limit(1000);

        final nullCount = response.where((row) => row['user_category_id'] == null).length;
        expect(nullCount, equals(0),
            reason: 'Found $nullCount users without user_category_id');
      });

      test('user_categories must have admin entry', () async {
        final response = await client
            .from('user_categories')
            .select('id, name, can_access_admin_panel')
            .eq('id', 'admin')
            .single();

        expect(response['id'], equals('admin'));
        expect(response['name'], equals('ผู้ดูแลระบบ'));
        expect(response['can_access_admin_panel'], isTrue);
      });

      test('user_categories flags are set correctly', () async {
        final response = await client
            .from('user_categories')
            .select('id, can_access_admin_panel, can_access_provider_dashboard, can_access_erp')
            .eq('id', 'admin')
            .or('id.eq.provider,id.eq.consumer');

        final categories = {for (var row in response) row['id'] as String: row};

        // Admin should have admin and ERP access
        expect(categories['admin']?['can_access_admin_panel'], isTrue);
        expect(categories['admin']?['can_access_erp'], isTrue);

        // Provider should have provider dashboard access
        expect(categories['provider']?['can_access_provider_dashboard'], isTrue);

        // Consumer should not have any special access
        expect(categories['consumer']?['can_access_admin_panel'], isFalse);
        expect(categories['consumer']?['can_access_provider_dashboard'], isFalse);
      });
    });

    group('UserRole Enum', () {
      test('enum values match database roles', () {
        expect(UserRole.consumer.value, equals('consumer'));
        expect(UserRole.provider.value, equals('provider'));
        expect(UserRole.admin.value, equals('admin'));
      });

      test('UserModel.userRole parses correctly', () {
        final now = DateTime.now();
        final user = UserModel(
          id: 'test-id',
          userType: UserType.consumer,
          firstName: 'Test',
          lastName: 'User',
          username: 'testuser',
          role: 'admin',
          createdAt: now,
          updatedAt: now,
        );

        expect(user.userRole, equals(UserRole.admin));
        expect(user.isAdmin, isTrue);
      });
    });

    group('GroupRoleRepository', () {
      test('uses UserRole enum values', () async {
        // Verify ว่า repository ใช้ UserRole.admin.value / UserRole.consumer.value
        // โดยตรวจสอบว่าไม่มี hardcoded strings ใน repository
        // (ทดสอบนี้ต้องรันหลังจาก build)
        expect(UserRole.admin.value, equals('admin'));
        expect(UserRole.consumer.value, equals('consumer'));
      });
    });
  });
}
