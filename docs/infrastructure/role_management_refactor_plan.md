# Role Management Refactor Plan
# แผนการปรับปรุงระบบจัดการ Role

**Created:** 2026-06-24  
**Status:** Draft  
**Objective:** ยกเลิก hardcode string ใน Flutter code และเตรียมรองรับการ migrate ไป data-driven approach ในอนาคต

---

## สรุปแนวทาง

### แนวทาง C (Phase 1 - ทันที)
- สร้าง constants file สำหรับ role strings
- แก้ Flutter code ให้ใช้ constants แทน hardcode
- **เวลา:** 30-60 นาที
- **ความเสี่ยง:** ต่ำมาก
- **ผล:** หลีกเลี่ยง hardcode ใน application code

### แนวทาง A (Phase 3 - อนาคต)
- ใช้ `user_categories` เป็นต้นทางกำหนด role
- เพิ่ม flags ใน `user_categories` (เช่น `can_access_admin_panel`)
- **เวลา:** 1-2 วัน
- **ความเสี่ยง:** ปานกลาง-สูง
- **ผล:** Data-driven role management

### แนวทาง B (Phase 3 - อนาคต)
- ใช้ `professions` เป็นต้นทางกำหนด role
- derive role จาก `professions.category` → `user_categories`
- **เวลา:** 2-3 วัน
- **ความเสี่ยง:** สูง
- **ผล:** Data-driven role management แต่ performance impact สูง

---

## Phase 1: Implement แนวทาง C (Constants)

### 1.1 สร้าง Enum Constants File (Type Safety)

**File:** `lib/core/constants/user_roles.dart`

```dart
/// User Role Enum
/// 
/// ใช้ Enum แทน String constants เพื่อ Type Safety และป้องกัน Typo
/// 
/// Phase 1: Enum-based approach (synchronous)
/// Phase 3: Data-driven approach (asynchronous) - สำหรับอนาคต
/// 
/// การใช้งาน:
/// - ใช้ UserRole.admin แทน 'admin' string
/// - ใช้ UserRole.fromValue() แปลงจาก database value
/// - ใช้ UserRole.isAdmin() แทน role == 'admin'
enum UserRole {
  consumer('consumer', 'ผู้รับบริการ'),
  provider('provider', 'ผู้ให้บริการ'),
  admin('admin', 'ผู้ดูแลระบบ');

  final String value;
  final String displayName;

  const UserRole(this.value, this.displayName);

  /// แปลงจาก string value → Enum
  static UserRole? fromValue(String? value) {
    if (value == null) return null;
    return UserRole.values.firstWhere(
      (role) => role.value == value,
      orElse: () => consumer,
    );
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
  static bool isAdminValue(String? value) => fromValue(value)?.isAdmin ?? false;
  static bool isProviderValue(String? value) => fromValue(value)?.isProvider ?? false;
  static bool isConsumerValue(String? value) => fromValue(value)?.isConsumer ?? false;

  /// ดึง display name จาก string value
  static String getDisplayName(String? value) {
    return fromValue(value)?.displayName ?? 'ไม่ระบุ';
  }
}

/// Extension สำหรับ UserModel (ช่วยให้อ่านง่ายขึ้น)
extension UserRoleExtension on UserRole {
  String get roleValue => value;
}
```

### 1.2 แก้ UserModel

**File:** `lib/features/auth/data/models/user_model.dart`

**เปลี่ยน:**
```dart
// ปัจจุบัน
bool get isAdmin => role == 'admin';
bool get isProvider => role == 'provider' || isConsultationProvider;
bool hasRole(String requiredRole) => role == requiredRole;
```

**เป็น:**
```dart
// แนวทาง C (Enum approach)
bool get isAdmin => UserRole.isAdminValue(role);
bool get isProvider => UserRole.isProviderValue(role) || isConsultationProvider;
bool hasRole(String requiredRole) => UserRole.fromValue(role)?.value == requiredRole;

/// เพิ่ม getter แบบ Enum (สำหรับ future migration)
UserRole? get userRole => UserRole.fromValue(role);
```

### 1.3 แก้ GroupRoleRepository

**File:** `lib/features/admin/data/repositories/group_role_repository.dart`

**เปลี่ยน:**
```dart
// ปัจจุบัน
'role': isAdmin ? 'admin' : 'consumer',
```

**เป็น:**
```dart
// แนวทาง C (Enum approach)
'role': isAdmin ? UserRole.admin.value : UserRole.consumer.value,
// หรือ
'role': (isAdmin ? UserRole.admin : UserRole.consumer).value,
```

### 1.4 แก้ AuthGuardWidget

**File:** `lib/core/guards/auth_guard_widget.dart`

**เปลี่ยน:**
```dart
// ปัจจุบัน
case 'admin': hasRequiredRole = user.isAdmin; break;
case 'provider': hasRequiredRole = user.isProvider; break;
```

**เป็น:**
```dart
// แนวทาง C (Enum approach)
case 'admin': hasRequiredRole = user.isAdmin; break;
case 'provider': hasRequiredRole = user.isProvider; break;
// (ไม่ต้องเปลี่ยนมาก เพราะใช้ user.isAdmin อยู่แล้ว)
```

### 1.5 แก้ UI ที่แสดง role string

**File:** ค้นหาทุกจุดที่แสดง role ใน UI

**เปลี่ยน:**
```dart
// ปัจจุบัน
Text('ผู้ดูแลระบบ')  // หรือ
Text(user.role == 'admin' ? 'ผู้ดูแลระบบ' : 'ผู้ใช้ทั่วไป')
```

**เป็น:**
```dart
// แนวทาง C (Enum approach)
Text(UserRole.getDisplayName(user.role))
// หรือถ้าใช้ UserRole enum
Text(user.userRole?.displayName ?? 'ไม่ระบุ')
```

### 1.6 แก้ Backend API

**File:** `websocket-server/middleware/auth.js`

**เปลี่ยน:**
```javascript
// ปัจจุบัน (ถ้ามี hardcode)
const ADMIN_ROLE = 'admin';
const PROVIDER_ROLE = 'provider';
const CONSUMER_ROLE = 'consumer';
```

**เป็น:**
```javascript
// แนวทาง C (Constants ใน backend)
const ROLES = {
  ADMIN: 'admin',
  PROVIDER: 'provider',
  CONSUMER: 'consumer'
};

// หรือใช้ environment variable (สำหรับ future flexibility)
const ADMIN_ROLE = process.env.ADMIN_ROLE || ROLES.ADMIN;
```

### 1.7 เพิ่ม Audit Script ค้นหา Hardcoded Strings

**File:** `scripts/audit_hardcoded_roles.sh`

```bash
#!/bin/bash
# Audit script: ตรวจหา hardcoded role strings ที่เหลืออยู่

echo "🔍 ตรวจหา hardcoded role strings ใน Flutter code..."

# ค้นหา 'admin', 'provider', 'consumer' ใน lib/ directory
# ยกเว้น user_roles.dart และ generated files
HARDcoded=$(grep -r "'admin'\|'provider'\|'consumer'" lib/ \
  --exclude-dir=generated \
  --exclude="*user_roles.dart" \
  --include="*.dart" \
  -n | grep -v "UserRole" | grep -v "// " | wc -l)

if [ "$HARDcoded" -eq 0 ]; then
  echo "✅ ไม่พบ hardcoded role strings ที่ไม่ถูกต้อง"
  exit 0
else
  echo "⚠️ พบ $HARDcoded จุดที่ยังมี hardcoded role strings"
  grep -r "'admin'\|'provider'\|'consumer'" lib/ \
    --exclude-dir=generated \
    --exclude="*user_roles.dart" \
    --include="*.dart" \
    -n | grep -v "UserRole" | grep -v "// "
  exit 1
fi
```

**การใช้งาน:**
```bash
# Run before migration
chmod +x scripts/audit_hardcoded_roles.sh
./scripts/audit_hardcoded_roles.sh

# Run after migration to verify
./scripts/audit_hardcoded_roles.sh
```

### 1.8 เพิ่ม Lint Rule ป้องกัน Hardcode Strings

**File:** `analysis_options.yaml` (ถ้ามี custom lint)

```yaml
linter:
  rules:
    - avoid_hardcoded_strings
    - prefer_single_quotes
    
# หรือเพิ่ม custom lint (ต้องสร้าง package เอง)
# แนะนำให้ใช้ code review checklist แทน
```

**Code Review Checklist:**
- [ ] ไม่มี 'admin', 'provider', 'consumer' ใน code (ยกเว้นใน user_roles.dart)
- [ ] ใช้ UserRole.fromValue() แทนการ parse string เอง
- [ ] ใช้ UserRole.getDisplayName() แทนการแสดง string เอง

### 1.9 เพิ่ม Integration Tests

**File:** `test/core/user_role_test.dart`

```dart
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
      expect(UserRole.fromValue('unknown'), UserRole.consumer);
    });

    test('should have correct display names', () {
      expect(UserRole.admin.displayName, 'ผู้ดูแลระบบ');
      expect(UserRole.provider.displayName, 'ผู้ให้บริการ');
      expect(UserRole.consumer.displayName, 'ผู้รับบริการ');
    });

    test('should validate roles correctly', () {
      expect(UserRole.admin.isAdmin, true);
      expect(UserRole.provider.isAdmin, false);
      expect(UserRole.provider.isProvider, true);
    });

    test('backward compatibility helpers work', () {
      expect(UserRole.isAdminValue('admin'), true);
      expect(UserRole.isAdminValue('provider'), false);
      expect(UserRole.isProviderValue('provider'), true);
    });

    test('getDisplayName returns correct names', () {
      expect(UserRole.getDisplayName('admin'), 'ผู้ดูแลระบบ');
      expect(UserRole.getDisplayName('unknown'), 'ไม่ระบุ');
      expect(UserRole.getDisplayName(null), 'ไม่ระบุ');
    });
  });
}
```

### 1.10 เพิ่ม Rollback Script

**File:** `scripts/rollback_phase_1.sh`

```bash
#!/bin/bash
# Rollback Phase 1: Constants → Hardcoded Strings

echo "🔄 Rollback Phase 1: Role Management Refactor"

# 1. ลบ constants file
rm -f lib/core/constants/user_roles.dart

# 2. คืนค่า hardcoded strings ใน UserModel
git checkout lib/features/auth/data/models/user_model.dart

# 3. คืนค่า hardcoded strings ใน GroupRoleRepository
git checkout lib/features/admin/data/repositories/group_role_repository.dart

# 4. คืนค่า hardcoded strings ใน AuthGuardWidget
git checkout lib/core/guards/auth_guard_widget.dart

# 5. คืนค่า hardcoded strings ใน UI
git checkout lib/features/admin/presentation/pages/

# 6. Verify
echo "✅ Rollback completed"
echo "🔍 ตรวจสอบว่าไม่มี error..."
flutter analyze
```

**เวลา Rollback:** 5-10 นาที (รวม flutter analyze)

---

## Phase 2: เตรียม Database สำหรับ Migration (อนาคต)

### 2.1 เพิ่ม 'admin' ใน user_categories

**Migration:** `supabase/migrations/YYYYMMDDHHMMSS_add_admin_to_user_categories.sql`

```sql
-- เพิ่ม 'admin' ใน user_categories
INSERT INTO user_categories (id, name, icon_name, display_order, is_active) 
VALUES ('admin', 'ผู้ดูแลระบบ', 'admin_panel_settings', 999, true)
ON CONFLICT (id) DO NOTHING;
```

### 2.2 เพิ่ม Flags ใน user_categories (สำหรับแนวทาง A)

**Migration:** `supabase/migrations/YYYYMMDDHHMMSS_add_role_flags_to_user_categories.sql`

```sql
-- เพิ่ม flags สำหรับกำหนดสิทธิ์
ALTER TABLE user_categories ADD COLUMN can_access_admin_panel BOOLEAN DEFAULT false;
ALTER TABLE user_categories ADD COLUMN can_access_provider_dashboard BOOLEAN DEFAULT false;
ALTER TABLE user_categories ADD COLUMN can_access_erp BOOLEAN DEFAULT false;

-- อัปเดต flags สำหรับ admin
UPDATE user_categories 
SET can_access_admin_panel = true, can_access_erp = true
WHERE id = 'admin';

-- อัปเดต flags สำหรับ provider
UPDATE user_categories 
SET can_access_provider_dashboard = true
WHERE id = 'provider';
```

### 2.3 เพิ่ม user_category_id ใน users (สำหรับแนวทาง A)

**Migration:** `supabase/migrations/YYYYMMDDHHMMSS_add_user_category_id_to_users.sql`

```sql
-- เพิ่ม column user_category_id
ALTER TABLE users ADD COLUMN user_category_id TEXT REFERENCES user_categories(id);

-- Migrate ข้อมูลเดิม
UPDATE users SET user_category_id = 'admin' WHERE role = 'admin';
UPDATE users SET user_category_id = 'provider' WHERE role = 'provider';
UPDATE users SET user_category_id = 'consumer' WHERE role = 'consumer';

-- สร้าง index
CREATE INDEX idx_users_user_category_id ON users(user_category_id);
```

### 2.4 เพิ่ม Profession สำหรับ Admin (สำหรับแนวทาง B)

**Migration:** `supabase/migrations/YYYYMMDDHHMMSS_add_admin_profession.sql`

```sql
-- เพิ่ม profession สำหรับ admin
INSERT INTO professions (id, name, name_en, description, icon_name, category, is_built_in, requires_verification, display_order, is_active) 
VALUES ('00000000-0000-0000-0000-000000000999', 'ผู้ดูแลระบบ', 'System Admin', 'ผู้ดูแลระบบทั้งหมด', 'admin_panel_settings', 'admin', true, false, 999, true)
ON CONFLICT (id) DO NOTHING;
```

### 2.5 เพิ่ม FK ระหว่าง professions.category → user_categories.id (สำหรับแนวทาง B)

**Migration:** `supabase/migrations/YYYYMMDDHHMMSS_add_profession_category_fk.sql`

```sql
-- เปลี่ยน professions.category เป็น FK
ALTER TABLE professions ALTER COLUMN category TYPE TEXT;
ALTER TABLE professions ADD CONSTRAINT fk_profession_category 
  FOREIGN KEY (category) REFERENCES user_categories(id);
```

### 2.6 เพิ่ม RLS Policies สำหรับ user_categories (Option B — Custom Auth)

**Migration:** `supabase/migrations/20260624090500_add_user_categories_rls.sql`

**หมายเหตุ:** โปรเจกต์นี้ไม่ได้ใช้ Supabase Auth → `auth.uid()` เป็น null เสมอ
ใช้ custom function `app.get_current_user_id()` แทน โดยอ่านจาก `current_setting('app.user_id')`
App ต้องเรียก `SELECT set_config('app.user_id', $userId, true)` ก่อน query ที่ต้องการ RLS

```sql
-- Custom Auth Helper Functions
CREATE OR REPLACE FUNCTION app.get_current_user_id()
RETURNS TEXT
LANGUAGE plpgsql STABLE SECURITY DEFINER
AS $$
BEGIN
  RETURN current_setting('app.user_id', true);
EXCEPTION WHEN OTHERS THEN RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION app.is_admin()
RETURNS BOOLEAN
LANGUAGE plpgsql STABLE SECURITY DEFINER
AS $$
DECLARE v_user_id TEXT; v_role TEXT;
BEGIN
  v_user_id := app.get_current_user_id();
  IF v_user_id IS NULL THEN RETURN false; END IF;
  SELECT role INTO v_role FROM users WHERE id = v_user_id LIMIT 1;
  RETURN v_role = 'admin';
END;
$$;

-- RLS Policies
ALTER TABLE user_categories ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Anyone can read user_categories"
ON user_categories FOR SELECT TO public USING (true);

CREATE POLICY "Only admins can modify user_categories"
ON user_categories FOR ALL TO authenticated
USING (app.is_admin())
WITH CHECK (app.is_admin());
```

### 2.7 เพิ่ม Trigger สำหรับ Sync Data

**Migration:** `supabase/migrations/YYYYMMDDHHMMSS_add_role_sync_trigger.sql`

```sql
-- Trigger: เมื่อ user_category_id เปลี่ยน → sync กับ role
CREATE OR REPLACE FUNCTION sync_role_from_category()
RETURNS TRIGGER AS $$
BEGIN
  -- Sync role จาก user_category_id (ถ้ามี)
  IF NEW.user_category_id IS NOT NULL THEN
    NEW.role = NEW.user_category_id;
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_sync_role
BEFORE UPDATE OF user_category_id ON users
FOR EACH ROW
EXECUTE FUNCTION sync_role_from_category();

-- Trigger: เมื่อ profession_id เปลี่ยน → sync กับ role (สำหรับแนวทาง B)
CREATE OR REPLACE FUNCTION sync_role_from_profession()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.profession_id IS NOT NULL THEN
    SELECT category INTO NEW.role
    FROM professions
    WHERE id = NEW.profession_id;
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_sync_role_from_profession
BEFORE UPDATE OF profession_id ON users
FOR EACH ROW
EXECUTE FUNCTION sync_role_from_profession();
```

### 2.8 เพิ่ม Index สำหรับ Performance

**Migration:** `supabase/migrations/YYYYMMDDHHMMSS_add_role_indexes.sql`

```sql
-- Index สำหรับ user_category_id (Phase 3A)
CREATE INDEX idx_users_user_category_id ON users(user_category_id);

-- Index สำหรับ profession_id (Phase 3B)
CREATE INDEX idx_users_profession_id ON users(profession_id);

-- Index สำหรับ role (existing - verify)
CREATE INDEX IF NOT EXISTS idx_users_role ON users(role);

-- Index สำหรับ JOIN query (Phase 3)
CREATE INDEX idx_user_categories_id ON user_categories(id);
CREATE INDEX idx_professions_category ON professions(category);
```

---

## Phase 3: Migration ไป Data-Driven Approach (อนาคต)

### 3.1 Migration ไปแนวทาง A (user_categories)

#### 3.1.1 สร้าง UserCategoryRepository

**File:** `lib/features/admin/data/repositories/user_category_repository.dart`

```dart
class UserCategoryRepository {
  final SupabaseClient _client;
  
  UserCategoryRepository(this._client);
  
  /// ดึง user category จาก ID
  Future<UserCategory?> getById(String id) async {
    try {
      final response = await _client
          .from('user_categories')
          .select()
          .eq('id', id)
          .single();
      return UserCategory.fromJson(response);
    } catch (e) {
      return null;
    }
  }
  
  /// ดึง user category จาก user ID
  Future<UserCategory?> getByUserId(String userId) async {
    try {
      final response = await _client
          .from('users')
          .select('user_categories(*)')
          .eq('id', userId)
          .single();
      return UserCategory.fromJson(response['user_categories']);
    } catch (e) {
      return null;
    }
  }
}
```

#### 3.1.2 อัปเดต UserRoles เป็น Async (พร้อม Caching)

**File:** `lib/core/constants/user_roles.dart`

```dart
abstract class UserRoles {
  // ===== Constants (สำหรับ fallback) =====
  static const String consumer = 'consumer';
  static const String provider = 'provider';
  static const String admin = 'admin';
  
  // ===== Helper Methods (Synchronous - Fallback) =====
  static bool isAdmin(String? role) => role == admin;
  static bool isProvider(String? role) => role == provider;
  static bool isConsumer(String? role) => role == consumer;
  
  // ===== Helper Methods (Asynchronous - Phase 3) =====
  /// ตรวจสอบว่า userCategoryId เป็น admin หรือไม่
  static Future<bool> isAdminAsync(String? userCategoryId) async {
    if (userCategoryId == null) return false;
    try {
      final category = await UserCategoryRepository.getById(userCategoryId);
      return category?.canAccessAdminPanel ?? false;
    } catch (e) {
      // Fallback: ใช้ constants เดิม + log warning
      debugPrint('[UserRoles] Fallback to constants due to error: $e');
      return userCategoryId == admin;
    }
  }
  
  /// ตรวจสอบว่า userCategoryId เป็น provider หรือไม่
  static Future<bool> isProviderAsync(String? userCategoryId) async {
    if (userCategoryId == null) return false;
    try {
      final category = await UserCategoryRepository.getById(userCategoryId);
      return category?.canAccessProviderDashboard ?? false;
    } catch (e) {
      // Fallback: ใช้ constants เดิม + log warning
      debugPrint('[UserRoles] Fallback to constants due to error: $e');
      return userCategoryId == provider;
    }
  }
}
```

#### 3.1.3 เพิ่ม Caching Layer (Performance)

**File:** `lib/features/admin/data/repositories/user_category_repository.dart`

```dart
class UserCategoryRepository {
  final SupabaseClient _client;
  final Map<String, UserCategory> _cache = {};
  static const Duration _cacheDuration = Duration(minutes: 5);
  DateTime? _lastCacheUpdate;
  
  UserCategoryRepository(this._client);
  
  /// ดึง user category จาก ID (with caching)
  Future<UserCategory?> getById(String id) async {
    // Check cache
    if (_cache.containsKey(id)) {
      return _cache[id];
    }
    
    try {
      final response = await _client
          .from('user_categories')
          .select()
          .eq('id', id)
          .single();
      final category = UserCategory.fromJson(response);
      _cache[id] = category;
      return category;
    } catch (e) {
      return null;
    }
  }
  
  /// Clear cache (เรียกเมื่อมีการแก้ไข user_categories)
  void invalidateCache() {
    _cache.clear();
    _lastCacheUpdate = null;
  }
  
  /// Refresh cache
  Future<void> refreshCache() async {
    try {
      final response = await _client.from('user_categories').select();
      for (final row in response) {
        final category = UserCategory.fromJson(row);
        _cache[category.id] = category;
      }
      _lastCacheUpdate = DateTime.now();
    } catch (e) {
      debugPrint('Failed to refresh cache: $e');
    }
  }
}
```

#### 3.1.4 อัปเดต UserModel

**File:** `lib/features/auth/data/models/user_model.dart`

```dart
class UserModel {
  // ... existing fields ...
  
  /// Phase 3: เพิ่ม userCategoryId
  final String? userCategoryId;
  
  // ... existing getters (synchronous - สำหรับ backward compatibility) ...
  bool get isAdmin => UserRole.isAdminValue(role);
  bool get isProvider => UserRole.isProviderValue(role);
  
  /// Phase 3: Async getters (สำหรับ data-driven)
  Future<bool> get isAdminAsync => UserRoles.isAdminAsync(userCategoryId);
  Future<bool> get isProviderAsync => UserRoles.isProviderAsync(userCategoryId);
}
```

#### 3.1.5 เพิ่ม Gradual Migration Strategy (Feature Flags)

**File:** `lib/core/utils/feature_flags.dart`

```dart
class FeatureFlags {
  /// เปิดใช้งาน Data-Driven Role (Phase 3)
  static bool useDataDrivenRoles = false;
  
  /// เปิดใช้งาน Async Role Check (Phase 3)
  static bool useAsyncRoleCheck = false;
  
  /// เปิดใช้งาน user_category_id (Phase 3A)
  static bool useUserCategoryId = false;
  
  /// เปิดใช้งาน profession_id สำหรับ role (Phase 3B)
  static bool useProfessionForRole = false;
  
  /// เปิดใช้งาน Caching (Phase 3)
  static bool useRoleCache = true;
}
```

**Migration Steps:**

**Step 1:** เปิดใช้งานสำหรับ user กลุ่มเล็ก (10%)
```dart
// ใน AuthService หรือ UserRepository
if (FeatureFlags.useDataDrivenRoles && isBetaUser(user.id)) {
  // ใช้ async role check
  final isAdmin = await user.isAdminAsync;
} else {
  // ใช้ sync role check (backward compatible)
  final isAdmin = user.isAdmin;
}
```

**Step 2:** Monitor 1-2 วัน
**Step 3:** เปิดใช้งานสำหรับ user 50%
**Step 4:** Monitor 1-2 วัน
**Step 5:** เปิดใช้งานสำหรับ user 100%

#### 3.1.6 เพิ่ม Monitoring และ Alerting

**Metrics ที่ต้อง monitor:**

| Metric | Threshold | Action |
|---|---|---|
| Async role check error rate | > 1% | Alert + fallback to constants |
| Cache hit rate | < 80% | Optimize cache logic |
| Database JOIN query time | > 100ms | Add index or optimize |
| User with null user_category_id | > 5% | Alert + check migration |

**Monitoring Queries:**

```sql
-- ตรวจสอบว่ามี user ที่ยังไม่มี user_category_id หรือไม่
SELECT COUNT(*) FROM users WHERE user_category_id IS NULL;

-- ตรวจสอบว่ามี user ที่ user_category_id ไม่ match กับ role
SELECT COUNT(*) FROM users u
JOIN user_categories uc ON u.user_category_id = uc.id
WHERE u.role != uc.id;

-- ตรวจสอบ performance ของ JOIN query
EXPLAIN ANALYZE
SELECT u.*, uc.can_access_admin_panel
FROM users u
LEFT JOIN user_categories uc ON u.user_category_id = uc.id
WHERE u.id = 'specific-user-id';
```

**Alert Setup:**
- ถ้ามี error rate > 1% → Slack alert
- ถ้ามี performance degradation > 20% → PagerDuty alert
- ถ้ามี data inconsistency > 5% → หยุด migration ทันที

#### 3.1.7 เพิ่ม Communication Plan

**Pre-migration (1 week before):**
- [ ] แจ้งทีมผ่าน Slack #dev-channel
- [ ] สร้าง Google Doc: "Role Management Refactor: What You Need to Know"
- [ ] Schedule ประชุม 30 นาที: Explain แผนและผลกระทบ

**During migration:**
- [ ] Daily status update ใน Slack
- [ ] สร้าง Slack channel #role-refactor สำหรับ real-time updates
- [ ] มี on-call engineer สำหรับ handle issues

**Post-migration (1 week after):**
- [ ] Retrospective meeting
- [ ] สรุป lessons learned
- [ ] Update documentation

#### 3.1.8 เพิ่ม Documentation สำหรับ Developers

**File:** `docs/guides/role_management.md`

```markdown
# Role Management Guide

## Overview
ระบบจัดการ Role ของ SheServed แบ่งเป็น 2 Phase:
- **Phase 1 (Current):** Enum constants (UserRole)
- **Phase 3 (Future):** Data-driven (user_categories)

## Best Practices
1. ใช้ `UserRole.isAdminValue()` แทน `role == 'admin'`
2. ใช้ `user.isAdmin` แทน `user.role == 'admin'`
3. ใช้ `UserRole.getDisplayName()` แทนการแสดง string เอง
4. ไม่ hardcode role strings ใน UI logic

## Adding New Roles
1. เพิ่มใน `UserRole` enum
2. เพิ่มใน `user_categories` table
3. อัปเดต `FeatureFlags` (ถ้าจำเป็น)
4. Run tests
5. Update documentation

## Migration History
- 2026-06-24: Phase 1 - Enum constants
- 2026-XX-XX: Phase 3 - Data-driven (planned)
```

#### 3.1.9 อัปเดต UserRepository

**File:** `lib/features/auth/data/repositories/user_repository.dart`

```dart
Future<UserModel?> getUserById(String id) async {
  try {
    final response = await _client
        .from('users')
        .select('''
          *,
          user_categories!inner(id, name, can_access_admin_panel, can_access_provider_dashboard),
          professions(is_volunteer)
        ''')
        .eq('id', id)
        .single();
    return UserModel.fromJson(response);
  } catch (e) {
    return null;
  }
}
```

#### 3.1.5 อัปเดต GroupRoleRepository

**File:** `lib/features/admin/data/repositories/group_role_repository.dart`

```dart
Future<void> setSystemAdminRole(String userId, bool isAdmin, String changedByUserId) async {
  // อัปเดต user_category_id แทน role
  await _client.from('users').update({
    'user_category_id': isAdmin ? UserRoles.admin : UserRoles.consumer,
  }).eq('id', userId);
  
  // Log audit trail
  await logRoleChange(userId, isAdmin ? UserRoles.admin : UserRoles.consumer, changedByUserId);
}
```

#### 3.1.6 อัปเดต GroupMembersAdminPage

**File:** `lib/features/admin/presentation/pages/group_members_admin_page.dart`

```dart
// แสดง userCategoryId แทน role
Text(UserRoles.getDisplayName(member.userCategoryId))

// Toggle admin
await _groupRoleRepository.setSystemAdminRole(
  member.id,
  !member.isAdmin,
  currentUser.id,
);
```

### 3.2 Migration ไปแนวทาง B (professions)

#### 3.2.1 อัปเดต UserRoles เป็น Async

**File:** `lib/core/constants/user_roles.dart`

```dart
abstract class UserRoles {
  // ===== Constants (สำหรับ fallback) =====
  static const String consumer = 'consumer';
  static const String provider = 'provider';
  static const String admin = 'admin';
  
  // ===== Helper Methods (Synchronous - Fallback) =====
  static bool isAdmin(String? role) => role == admin;
  static bool isProvider(String? role) => role == provider;
  
  // ===== Helper Methods (Asynchronous - Phase 3) =====
  /// ตรวจสอบว่า professionId เป็น admin หรือไม่
  static Future<bool> isAdminAsync(String? professionId) async {
    if (professionId == null) return false;
    try {
      final profession = await ProfessionRepository.getById(professionId);
      return profession?.category == admin;
    } catch (e) {
      // Fallback: ใช้ constants เดิม
      return false;
    }
  }
  
  /// ตรวจสอบว่า professionId เป็น provider หรือไม่
  static Future<bool> isProviderAsync(String? professionId) async {
    if (professionId == null) return false;
    try {
      final profession = await ProfessionRepository.getById(professionId);
      return profession?.category == provider;
    } catch (e) {
      // Fallback: ใช้ constants เดิม
      return false;
    }
  }
}
```

#### 3.2.2 อัปเดต UserModel

**File:** `lib/features/auth/data/models/user_model.dart`

```dart
class UserModel {
  // ... existing fields ...
  
  /// Phase 3: เพิ่ม professionCategory
  final String? professionCategory;
  
  // ... existing getters (synchronous) ...
  
  /// Phase 3: Async getters (สำหรับ data-driven)
  Future<bool> get isAdminAsync => UserRoles.isAdminAsync(professionId);
  Future<bool> get isProviderAsync => UserRoles.isProviderAsync(professionId);
}
```

#### 3.2.3 อัปเดต UserRepository

**File:** `lib/features/auth/data/repositories/user_repository.dart`

```dart
Future<UserModel?> getUserById(String id) async {
  try {
    final response = await _client
        .from('users')
        .select('''
          *,
          professions!inner(id, name, category, is_volunteer)
        ''')
        .eq('id', id)
        .single();
    return UserModel.fromJson(response);
  } catch (e) {
    return null;
  }
}
```

#### 3.2.4 อัปเดต GroupRoleRepository

**File:** `lib/features/admin/data/repositories/group_role_repository.dart`

```dart
Future<void> setSystemAdminRole(String userId, bool isAdmin, String changedByUserId) async {
  // อัปเดต profession_id แทน role
  final adminProfessionId = '00000000-0000-0000-0000-000000000999';
  final consumerProfessionId = '00000000-0000-0000-0000-000000000001';
  
  await _client.from('users').update({
    'profession_id': isAdmin ? adminProfessionId : consumerProfessionId,
  }).eq('id', userId);
  
  // Log audit trail
  await logRoleChange(userId, isAdmin ? UserRoles.admin : UserRoles.consumer, changedByUserId);
}
```

---

## Phase 4: Deprecate users.role Column (อนาคต)

### 4.1 ทำให้ users.role เป็น nullable

**Migration:** `supabase/migrations/YYYYMMDDHHMMSS_make_users_role_nullable.sql`

```sql
-- ทำให้ role เป็น nullable
ALTER TABLE users ALTER COLUMN role DROP NOT NULL;
```

### 4.2 สร้าง View สำหรับ backward compatibility

**Migration:** `supabase/migrations/YYYYMMDDHHMMSS_create_users_role_view.sql`

```sql
-- สร้าง view สำหรับ derive role จาก user_category_id
CREATE OR REPLACE VIEW users_with_derived_role AS
SELECT 
  u.*,
  COALESCE(
    uc.id,
    CASE 
      WHEN u.profession_id IS NOT NULL THEN p.category
      ELSE 'consumer'
    END
  ) as derived_role
FROM users u
LEFT JOIN user_categories uc ON u.user_category_id = uc.id
LEFT JOIN professions p ON u.profession_id = p.id;
```

### 4.3 สร้าง View สำหรับ backward compatibility

**Migration:** `supabase/migrations/YYYYMMDDHHMMSS_create_users_role_view.sql`

```sql
-- สร้าง view สำหรับ derive role จาก user_category_id
CREATE OR REPLACE VIEW users_with_derived_role AS
SELECT 
  u.*,
  COALESCE(
    uc.id,
    CASE 
      WHEN u.profession_id IS NOT NULL THEN p.category
      ELSE 'consumer'
    END
  ) as derived_role
FROM users u
LEFT JOIN user_categories uc ON u.user_category_id = uc.id
LEFT JOIN professions p ON u.profession_id = p.id;
```

### 4.4 Grace Period (7-30 วัน)

**ระหว่าง Grace Period:**
- ไม่ลบ `users.role` ทันที
- Monitor ว่ามี code เก่าอ่าน `users.role` อยู่หรือไม่
- Monitor ว่ามี user ที่ยังไม่มี `user_category_id`

**Monitoring Queries:**

```sql
-- ตรวจสอบว่ามี user ที่ยังไม่มี user_category_id
SELECT COUNT(*) FROM users WHERE user_category_id IS NULL;

-- ตรวจสอบว่ามี code เก่าอ่าน users.role (ผ่าน logs)
-- ต้องเพิ่ม logging ใน application
```

### 4.5 ลบ users.role column (เมื่อพร้อม)

**Migration:** `supabase/migrations/YYYYMMDDHHMMSS_drop_users_role_column.sql`

```sql
-- อันตราย: ต้องแน่ใจว่าไม่มี code เก่าอ่าน column นี้
-- ต้องผ่าน Grace Period อย่างน้อย 7 วัน
ALTER TABLE users DROP COLUMN role;
```

---

## การทดสอบ (Testing)

### Phase 1 Testing
- [ ] ทดสอบ login/logout
- [ ] ทดสอบ route guard (admin, provider, consumer)
- [ ] ทดสอบ admin toggle ใน GroupMembersAdminPage
- [ ] ทดสอบ registration flow
- [ ] ทดสอบ ERP login
- [ ] **ทดสอบ UserRole Enum** (parse, validate, display name)
- [ ] **ทดสอบ Audit Script** (verify ไม่มี hardcode strings)
- [ ] **ทดสอบ Rollback Script** (verify สามารถ rollback ได้)
- [ ] **ทดสอบ Integration Tests** (run test/core/user_role_test.dart)

### Phase 2 Testing
- [ ] ทดสอบ migration script
- [ ] ทดสอบว่า `user_categories` มี `'admin'` อยู่
- [ ] ทดสอบว่า flags ทำงานถูกต้อง
- [ ] **ทดสอบ RLS Policies** (verify security)
- [ ] **ทดสอบ Sync Triggers** (verify data consistency)
- [ ] **ทดสอบ Performance Indexes** (verify query speed)

### Phase 3 Testing (แนวทาง A)
- [ ] ทดสอบ UserCategoryRepository
- [ ] ทดสอบ async getters ใน UserModel
- [ ] ทดสอบการอัปเดต user_category_id
- [ ] ทดสอบ audit trail กับ user_category_id
- [ ] ทดสอบ performance (JOIN 1 table)
- [ ] **ทดสอบ Caching Layer** (verify cache hit rate > 80%)
- [ ] **ทดสอบ Feature Flags** (verify gradual migration)
- [ ] **ทดสอบ Monitoring** (verify alerts)
- [ ] **ทดสอบ Fallback Logic** (verify constants fallback)

### Phase 3 Testing (แนวทาง B)
- [ ] ทดสอบ ProfessionRepository
- [ ] ทดสอบ async getters ใน UserModel
- [ ] ทดสอบการอัปเดต profession_id
- [ ] ทดสอบ audit trail กับ profession_id
- [ ] ทดสอบ performance (JOIN 2 tables)
- [ ] **ทดสอบ Caching Layer** (verify cache hit rate > 80%)
- [ ] **ทดสอบ Feature Flags** (verify gradual migration)
- [ ] **ทดสอบ Monitoring** (verify alerts)
- [ ] **ทดสอบ Fallback Logic** (verify constants fallback)

---

## Rollback Plan

### Phase 1 Rollback
- ลบ `lib/core/constants/user_roles.dart`
- คืนค่า hardcoded strings ทั้งหมด
- **เวลา:** 10-15 นาที

### Phase 2 Rollback
- ลบ migration files ที่เพิ่ม
- ลบ columns ที่เพิ่ม
- **เวลา:** 30-45 นาที

### Phase 3 Rollback (แนวทาง A)
- คืนค่า UserRoles เป็น synchronous
- คืนค่า UserModel getters
- คืนค่า UserRepository queries
- **เวลา:** 1-2 ชั่วโมง

### Phase 3 Rollback (แนวทาง B)
- คืนค่า UserRoles เป็น synchronous
- คืนค่า UserModel getters
- คืนค่า UserRepository queries
- **เวลา:** 1-2 ชั่วโมง

---

## สรุปเวลาและความเสี่ยง

| Phase | เวลา | ความเสี่ยง | ไฟล์ที่แก้ | ข้อเสนอแนะที่เพิ่ม |
|---|---|---|---|---|
| **Phase 1 (Enum Constants)** | 30-60 นาที | ต่ำมาก | 3-5 ไฟล์ | ✅ Enum (Type Safety), ✅ Audit Script, ✅ Integration Tests, ✅ Rollback Script |
| **Phase 2 (Prepare DB)** | 1-2 ชั่วโมง | ปานกลาง | 5-8 migrations | ✅ RLS Policies, ✅ Sync Triggers, ✅ Performance Indexes |
| **Phase 3A (user_categories)** | 1-2 วัน | ปานกลาง-สูง | 10-15 ไฟล์ | ✅ Caching Layer, ✅ Gradual Migration, ✅ Monitoring, ✅ Communication Plan |
| **Phase 3B (professions)** | 2-3 วัน | สูง | 15-20 ไฟล์ | ✅ Caching Layer, ✅ Gradual Migration, ✅ Monitoring |
| **Phase 4 (Deprecate role)** | 1-2 วัน | สูงมาก | 2-3 migrations | ✅ Grace Period (7-30 วัน), ✅ Monitoring Queries |

## รายการข้อเสนอแนะที่เพิ่มในแผน

| # | ข้อเสนอแนะ | Phase | ความสำคัญ |
|---|---|---|---|
| 1 | **Enum แทน String Constants** | Phase 1 | 🔴 สูง |
| 2 | **Audit Script** | Phase 1 | 🔴 สูง |
| 3 | **Integration Tests** | Phase 1 | 🔴 สูง |
| 4 | **Rollback Script** | Phase 1 | 🔴 สูง |
| 5 | **RLS Policies** | Phase 2 | 🔴 สูง |
| 6 | **Sync Triggers** | Phase 2 | 🟠 ปานกลาง |
| 7 | **Performance Indexes** | Phase 2 | 🔴 สูง |
| 8 | **Caching Layer** | Phase 3 | 🔴 สูง |
| 9 | **Gradual Migration (Feature Flags)** | Phase 3 | 🔴 สูงมาก |
| 10 | **Monitoring & Alerting** | Phase 3 | 🔴 สูงมาก |
| 11 | **Communication Plan** | Phase 3 | 🟠 ปานกลาง |
| 12 | **Developer Documentation** | Phase 3 | 🟠 ปานกลาง |
| 13 | **Grace Period (7-30 วัน)** | Phase 4 | 🔴 สูงมาก |

---

## คำแนะนำ

1. **ทำ Phase 1 ทันที** — 30 นาทีเสร็จ ไม่เสี่ยง
2. **ทำ Phase 2 เมื่อพร้อม** — เตรียม database สำหรับอนาคต
3. **เลือก Phase 3A หรือ 3B ตามความต้องการ** — ถ้าต้องการ dynamic role → เลือก A, ถ้าต้องการ profession-based → เลือก B
4. **ทำ Phase 4 เมื่อพร้อม** — ลงมือเมื่อทุกอย่างทำงานได้ดี
