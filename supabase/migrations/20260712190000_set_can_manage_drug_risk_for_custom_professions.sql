-- =====================================================
-- Migration: Set can_manage_drug_risk for custom professions
-- Date: 2026-07-12
-- Purpose:
--   1. FIX: Consumer (...-000001) has can_manage_drug_risk=true — must be false
--   2. Ensure built-in expert and clinic have can_manage_drug_risk=true
--   3. Confirm apisek's custom profession (แพทย์ทั่วไป) already has flag=true
--   4. Confirm เภสัชกร custom profession already has flag=true
--
--   This migration supports "Approach 1" from profession_system_migration_guide.md:
--   using the can_manage_drug_risk flag instead of hardcoded UUID checks.
--
--   DB state verified on 2026-07-12:
--     - Consumer ...-000001: can_manage_drug_risk=true (BUG — should be false)
--     - Expert ...-000002: can_manage_drug_risk=true (correct)
--     - Clinic ...-000003: can_manage_drug_risk=true (correct)
--     - 0a8e7857-... (แพทย์ทั่วไป, custom): true (correct — apisek's profession)
--     - 191e414a-... (เภสัชกร, custom): true (correct)
--     - 5d81c5ac-... (อาจารย์แพทย์, is_built_in=true): true (correct)
--     - All other custom professions: false (correct)
-- =====================================================

-- =====================================================
-- PART 1: FIX — Consumer must NOT have can_manage_drug_risk
-- =====================================================

UPDATE public.professions
SET can_manage_drug_risk = false,
    updated_at = NOW()
WHERE id = '00000000-0000-0000-0000-000000000001'
  AND can_manage_drug_risk IS DISTINCT FROM false;

-- =====================================================
-- PART 2: Ensure built-in expert and clinic have capability
-- =====================================================

UPDATE public.professions
SET can_manage_drug_risk = true,
    updated_at = NOW()
WHERE id = '00000000-0000-0000-0000-000000000002'
  AND can_manage_drug_risk IS DISTINCT FROM true;

UPDATE public.professions
SET can_manage_drug_risk = true,
    updated_at = NOW()
WHERE id = '00000000-0000-0000-0000-000000000003'
  AND can_manage_drug_risk IS DISTINCT FROM true;

-- =====================================================
-- PART 3: Confirm custom professions with existing capability
--          (No action needed — already correct in DB)
--          apisek's profession: 0a8e7857-... (แพทย์ทั่วไป) = true
--          เภสัชกร: 191e414a-... = true
--          อาจารย์แพทย์: 5d81c5ac-... = true
-- =====================================================

-- No UPDATE needed — these are already correct.
-- If you need to grant capability to additional custom professions,
-- add UPDATE statements here with explicit UUIDs after approval.

-- =====================================================
-- PART 4: Verify final state
-- =====================================================

SELECT id,
       name,
       profession_code,
       is_built_in,
       can_manage_drug_risk
FROM public.professions
WHERE is_active = true
  AND can_manage_drug_risk = true
ORDER BY is_built_in DESC, name;
