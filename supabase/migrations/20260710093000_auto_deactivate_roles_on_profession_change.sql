-- Migration: Deactivate employee_roles + provider_profiles when user changes profession
-- Date: 2026-07-10
-- 
-- ปัญหา: เมื่อ user เปลี่ยนอาชีพจากที่ approved ไปเป็นอาชีพอื่น/consumer
-- employee_roles และ provider_profiles ของอาชีพเดิมยังค้าง active
-- ทำให้ canCreateApplication บล็อกการสมัครซ้ำด้วย ROLE_EXISTS
--
-- แก้: ขยาย auto_cancel_pending_applications trigger ให้ deactivate ด้วย

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
    WHERE user_id = NEW.id AND status = 'pending';

    -- 2. Deactivate employee_roles ของอาชีพเดิม (กัน ROLE_EXISTS block การสมัครใหม่)
    UPDATE public.employee_roles
    SET is_active = false
    WHERE user_id = NEW.id
      AND profession_id IS DISTINCT FROM NEW.profession_id
      AND is_active = true;

    -- 3. Mark provider_profiles ของอาชีพเดิมว่าไม่ verified แล้ว
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

-- Trigger ยังใช้อันเดิม (แก้ function แล้ว trigger จะเรียก version ใหม่อัตโนมัติ)

-- Reload PostgREST schema cache
NOTIFY pgrst, 'reload schema';
