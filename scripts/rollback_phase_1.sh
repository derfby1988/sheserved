#!/bin/bash
# Rollback Phase 1: Enum Constants → Hardcoded Strings
# Role Management Refactor

echo "🔄 Rollback Phase 1: Role Management Refactor"

# 1. ลบ constants file
rm -f lib/core/constants/user_roles.dart

# 2. คืนค่า hardcoded strings ใน UserModel
git checkout lib/features/auth/data/models/user_model.dart

# 3. คืนค่า hardcoded strings ใน GroupRoleRepository
git checkout lib/features/admin/data/repositories/group_role_repository.dart

# 4. ลบ test file
rm -f test/core/user_role_test.dart

# 5. ลบ audit script
rm -f scripts/audit_hardcoded_roles.sh

# 6. ลบ rollback script ตัวเอง
rm -f scripts/rollback_phase_1.sh

# 7. Verify
echo "✅ Rollback completed"
echo "🔍 ตรวจสอบว่าไม่มี error..."
flutter analyze
