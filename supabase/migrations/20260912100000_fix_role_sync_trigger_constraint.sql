-- Fix profession/category sync so users.role always satisfies users_role_check
-- AND user_category_id stays in sync for every profession-change path
-- (ProfilePage update, approveApplication, cancel/withdraw RPC).
--
-- professions.category เป็น taxonomy ของอาชีพเอง (provider, law, volunteer,
-- local_leader, 'health center', ...) — ไม่ใช่ id ของ user_categories
-- จึงต้อง map เป็น bucket ใหญ่ตามกฎ HR_SYSTEM_PLAN ("อาชีพอื่น → role='provider'"):
--   category 'consumer'     → user_category_id 'consumer',     role 'consumer'
--   category 'local_leader' → user_category_id 'local_leader', role 'provider'
--   category อื่นๆ          → user_category_id 'provider',     role 'provider'
-- user_category_id = fine-grained bucket (source of JWT role ใน backend auth)

CREATE OR REPLACE FUNCTION public.sync_role_from_profession()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = ''
AS $$
DECLARE
  v_category TEXT;
  v_ucat TEXT;
BEGIN
  IF NEW.profession_id IS NOT NULL THEN
    SELECT p.category INTO v_category
    FROM public.professions p WHERE p.id = NEW.profession_id;

    IF v_category IS NOT NULL THEN
      v_ucat := CASE
        WHEN v_category = 'consumer' THEN 'consumer'
        WHEN v_category = 'local_leader' THEN 'local_leader'
        ELSE 'provider'
      END;

      IF EXISTS (
        SELECT 1 FROM public.user_categories uc WHERE uc.id = v_ucat
      ) THEN
        NEW.user_category_id = v_ucat;
      END IF;

      NEW.role = CASE WHEN v_ucat = 'consumer' THEN 'consumer' ELSE 'provider' END;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.sync_role_from_category()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
  IF NEW.user_category_id IS NOT NULL THEN
    NEW.role = CASE
      WHEN NEW.user_category_id IN ('consumer', 'admin')
        THEN NEW.user_category_id
      ELSE 'provider'
    END;
  END IF;
  RETURN NEW;
END;
$$;

-- Backfill: ใช้ mapped bucket ไม่ใช่ category ดิบ (JOIN user_categories = FK guard)
-- ไม่แตะแถว admin เพื่อไม่ให้สิทธิ์ผู้ดูแลหดลงโดยไม่ตั้งใจ
UPDATE public.users u
SET user_category_id = m.ucat
FROM public.professions p
CROSS JOIN LATERAL (
  SELECT CASE
    WHEN p.category = 'consumer' THEN 'consumer'
    WHEN p.category = 'local_leader' THEN 'local_leader'
    ELSE 'provider'
  END AS ucat
) m
JOIN public.user_categories uc ON uc.id = m.ucat
WHERE u.profession_id = p.id
  AND p.category IS NOT NULL
  AND u.role <> 'admin'
  AND u.user_category_id IS DISTINCT FROM m.ucat;
