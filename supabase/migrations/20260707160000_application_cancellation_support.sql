-- Migration: Application Cancellation Support
-- Date: 2026-07-07
-- Phase A: Add cancelled status, audit trail, unique index, auto-cancel trigger, fix approve trigger

-- 1. เพิ่มสถานะ 'cancelled' ใน CHECK constraint
ALTER TABLE public.registration_applications
  DROP CONSTRAINT IF EXISTS registration_applications_status_check;

ALTER TABLE public.registration_applications
  ADD CONSTRAINT registration_applications_status_check
  CHECK (status IN ('pending', 'approved', 'rejected', 'cancelled'));

-- 2. เพิ่ม audit trail สำหรับการยกเลิก
ALTER TABLE public.registration_applications
  ADD COLUMN IF NOT EXISTS cancelled_by TEXT,
  ADD COLUMN IF NOT EXISTS cancelled_at TIMESTAMPTZ;

-- 3. ป้องกันผู้ใช้สร้าง pending application ซ้ำมากกว่า 1 ใบพร้อมกัน
CREATE UNIQUE INDEX IF NOT EXISTS uq_registration_applications_one_pending_per_user
  ON public.registration_applications (user_id)
  WHERE status = 'pending';

-- 4. Trigger ยกเลิก pending applications อัตโนมัติเมื่อ user เปลี่ยนอาชีพ
CREATE OR REPLACE FUNCTION public.auto_cancel_pending_applications()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.profession_id IS DISTINCT FROM OLD.profession_id THEN
    UPDATE public.registration_applications
    SET status = 'cancelled',
        cancelled_by = 'auto_profession_change',
        cancelled_at = now(),
        updated_at = now()
    WHERE user_id = NEW.id AND status = 'pending';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_auto_cancel_pending_apps ON public.users;
CREATE TRIGGER trg_auto_cancel_pending_apps
  AFTER UPDATE OF profession_id ON public.users
  FOR EACH ROW EXECUTE FUNCTION public.auto_cancel_pending_applications();

-- 5. แก้ trigger อนุมัติใบสมัคร ให้ทำงานเฉพาะ pending → approved เท่านั้น
--    (ป้องกัน cancelled → approved ผ่าน race condition)
CREATE OR REPLACE FUNCTION public.on_registration_application_approved_trigger()
RETURNS TRIGGER AS $$
DECLARE
    v_owner_role_id UUID;
    v_main_branch_id UUID;
    v_is_owner_req BOOLEAN;
BEGIN
    -- แก้จากเดิม: OLD.status != 'approved' → OLD.status = 'pending'
    -- รับประกัน trigger ทำงานเฉพาะจาก pending → approved เท่านั้น
    IF NEW.status = 'approved' AND OLD.status = 'pending' THEN
        v_is_owner_req := COALESCE((NEW.registration_data->>'is_owner_request')::boolean, false);

        IF v_is_owner_req OR NOT EXISTS (
            SELECT 1 FROM public.employee_roles
            WHERE profession_id = NEW.profession_id AND is_active = true
        ) THEN
            SELECT id INTO v_owner_role_id
            FROM public.organization_roles
            WHERE profession_id = NEW.profession_id AND role_name = 'owner'
            LIMIT 1;

            SELECT id INTO v_main_branch_id
            FROM public.organization_branches
            WHERE profession_id = NEW.profession_id
            ORDER BY is_main_branch DESC, created_at ASC
            LIMIT 1;

            IF v_owner_role_id IS NOT NULL THEN
                INSERT INTO public.employee_roles (
                    profession_id, branch_id, user_id, role_id, is_active
                )
                VALUES (
                    NEW.profession_id, v_main_branch_id, NEW.user_id, v_owner_role_id, true
                )
                ON CONFLICT (profession_id, user_id, role_id, branch_id) DO NOTHING;
            END IF;

            INSERT INTO public.organization_feature_flags (profession_id, feature_name, status)
            SELECT NEW.profession_id, f.feature_name, 'disabled'
            FROM (VALUES
                ('pos_module'), ('inventory_module'), ('procurement_module'),
                ('accounting_module'), ('hr_module'), ('crm_loyalty'),
                ('crm_coupons'), ('crm_promotions'), ('his_module'),
                ('lis_module'), ('telemedicine_module'), ('logistics_module'),
                ('commerce_module'), ('cart_module'), ('settlement_module'),
                ('kpi_dashboard'), ('read_model_module')
            ) AS f(feature_name)
            ON CONFLICT (profession_id, feature_name) DO NOTHING;

            PERFORM public.seed_default_payment_channels(NEW.profession_id);
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger ยังใช้อันเดิม (ไม่ต้อง drop/recreate เพราะแก้ function แล้ว)

-- Reload PostgREST schema cache เพื่อป้องกัน PGRST204 (schema cache ค้าง) หลังแก้ schema
NOTIFY pgrst, 'reload schema';
