-- Migration: Complete cleanup when user changes profession via UI
-- Date: 2026-07-10
--
-- ปัญหา: เมื่อ user เปลี่ยนอาชีพออกจากอาชีพที่ approved แล้ว
-- ใบสมัคร approved เดิมยังค้าง ทำให้ canCreateApplication บล็อกการสมัครซ้ำ
--
-- แก้: ขยาย trigger ให้ยกเลิก pending + approved ของอาชีพเดิม
-- และ deactivate employee_roles + mark provider_profiles ไม่ verified

CREATE OR REPLACE FUNCTION public.auto_cancel_pending_applications()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.profession_id IS DISTINCT FROM OLD.profession_id THEN
    -- 1. ยกเลิกใบสมัคร pending ของอาชีพเดิม
    UPDATE public.registration_applications
    SET status = 'cancelled',
        cancelled_by = 'auto_profession_change',
        cancelled_at = now(),
        updated_at = now()
    WHERE user_id = NEW.id
      AND status = 'pending'
      AND profession_id IS DISTINCT FROM NEW.profession_id;

    -- 2. ยกเลิกใบสมัคร approved ของอาชีพเดิม (user ออกจากอาชีพแล้ว ใบอนุมัติใช้ไม่ได้)
    UPDATE public.registration_applications
    SET status = 'cancelled',
        cancelled_by = 'auto_profession_change',
        cancelled_at = now(),
        updated_at = now()
    WHERE user_id = NEW.id
      AND status = 'approved'
      AND profession_id IS DISTINCT FROM NEW.profession_id;

    -- 3. Deactivate employee_roles ของอาชีพเดิม
    UPDATE public.employee_roles
    SET is_active = false
    WHERE user_id = NEW.id
      AND profession_id IS DISTINCT FROM NEW.profession_id
      AND is_active = true;

    -- 4. Mark provider_profiles ของอาชีพเดิมว่าไม่ verified แล้ว
    UPDATE public.provider_profiles
    SET is_verified = false,
        verified_at = NULL,
        updated_at = now()
    WHERE user_id = NEW.id
      AND is_verified = true;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger ยังใช้อันเดิม (function ถูก replace)

-- Reload PostgREST schema cache
NOTIFY pgrst, 'reload schema';
