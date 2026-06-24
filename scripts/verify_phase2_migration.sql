-- =====================================================
-- Phase 2 Post-Migration Verification Script
-- ตรวจสอบความถูกต้องหลังรัน migration Phase 2
-- วิธีใช้: รันผ่าน Supabase SQL Editor หรือ psql
-- =====================================================

-- สรุปผล: ถ้าทุก check ผ่าน → "ALL CHECKS PASSED"
-- ถ้ามี check ไม่ผ่าน → แสดงรายละเอียดปัญหา

DO $$
DECLARE
  v_fail_count INTEGER := 0;
  v_total_users INTEGER;
  v_synced_users INTEGER;
  v_null_category_count INTEGER;
  v_invalid_role_count INTEGER;
BEGIN
  RAISE NOTICE '========================================';
  RAISE NOTICE 'Phase 2 Post-Migration Verification';
  RAISE NOTICE '========================================';

  -- =====================================================
  -- Check 1: role และ user_category_id sync ถูกต้อง
  -- =====================================================
  SELECT COUNT(*) INTO v_total_users FROM users WHERE role IS NOT NULL;
  
  SELECT COUNT(*) INTO v_synced_users
  FROM users
  WHERE role IS NOT NULL
    AND role = user_category_id;

  IF v_synced_users = v_total_users THEN
    RAISE NOTICE '✅ Check 1 PASSED: All % users have role = user_category_id', v_total_users;
  ELSE
    RAISE NOTICE '❌ Check 1 FAILED: %/% users have mismatched role and user_category_id',
      (v_total_users - v_synced_users), v_total_users;
    v_fail_count := v_fail_count + 1;
  END IF;

  -- =====================================================
  -- Check 2: ไม่มี user ที่ user_category_id เป็น NULL
  -- =====================================================
  SELECT COUNT(*) INTO v_null_category_count
  FROM users WHERE user_category_id IS NULL;

  IF v_null_category_count = 0 THEN
    RAISE NOTICE '✅ Check 2 PASSED: No users with NULL user_category_id';
  ELSE
    RAISE NOTICE '❌ Check 2 FAILED: % users have NULL user_category_id', v_null_category_count;
    v_fail_count := v_fail_count + 1;
  END IF;

  -- =====================================================
  -- Check 3: user_categories มี 'admin' entry
  -- =====================================================
  IF EXISTS (SELECT 1 FROM user_categories WHERE id = 'admin') THEN
    RAISE NOTICE '✅ Check 3 PASSED: admin entry exists in user_categories';
  ELSE
    RAISE NOTICE '❌ Check 3 FAILED: admin entry missing in user_categories';
    v_fail_count := v_fail_count + 1;
  END IF;

  -- =====================================================
  -- Check 4: flags ตั้งค่าถูกต้อง
  -- =====================================================
  IF EXISTS (
    SELECT 1 FROM user_categories
    WHERE id = 'admin'
      AND can_access_admin_panel = true
      AND can_access_erp = true
  ) THEN
    RAISE NOTICE '✅ Check 4 PASSED: admin flags are correct';
  ELSE
    RAISE NOTICE '❌ Check 4 FAILED: admin flags are incorrect';
    v_fail_count := v_fail_count + 1;
  END IF;

  -- =====================================================
  -- Check 5: professions FK constraint ทำงานได้
  -- =====================================================
  IF EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'fk_profession_category'
      AND conrelid = 'professions'::regclass
  ) THEN
    RAISE NOTICE '✅ Check 5 PASSED: professions.category FK exists';
  ELSE
    RAISE NOTICE '❌ Check 5 FAILED: professions.category FK missing';
    v_fail_count := v_fail_count + 1;
  END IF;

  -- =====================================================
  -- Check 6: sync triggers มีอยู่
  -- =====================================================
  IF EXISTS (
    SELECT 1 FROM pg_trigger
    WHERE tgname = 'trigger_sync_role_from_category'
      AND tgrelid = 'users'::regclass
  ) THEN
    RAISE NOTICE '✅ Check 6 PASSED: sync trigger exists';
  ELSE
    RAISE NOTICE '❌ Check 6 FAILED: sync trigger missing';
    v_fail_count := v_fail_count + 1;
  END IF;

  -- =====================================================
  -- Check 7: RLS policies มีอยู่
  -- =====================================================
  IF EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'user_categories'
      AND policyname = 'Only admins can modify user_categories'
  ) THEN
    RAISE NOTICE '✅ Check 7 PASSED: RLS policy exists';
  ELSE
    RAISE NOTICE '❌ Check 7 FAILED: RLS policy missing';
    v_fail_count := v_fail_count + 1;
  END IF;

  -- =====================================================
  -- Check 8: performance indexes มีอยู่
  -- =====================================================
  IF EXISTS (
    SELECT 1 FROM pg_indexes
    WHERE tablename = 'users'
      AND indexname = 'idx_users_user_category_id'
  ) THEN
    RAISE NOTICE '✅ Check 8 PASSED: user_category_id index exists';
  ELSE
    RAISE NOTICE '❌ Check 8 FAILED: user_category_id index missing';
    v_fail_count := v_fail_count + 1;
  END IF;

  -- =====================================================
  -- Summary
  -- =====================================================
  RAISE NOTICE '========================================';
  IF v_fail_count = 0 THEN
    RAISE NOTICE '✅ ALL CHECKS PASSED - Phase 2 migration is healthy';
  ELSE
    RAISE NOTICE '❌ % CHECK(S) FAILED - Please review above', v_fail_count;
  END IF;
  RAISE NOTICE '========================================';

END $$;
