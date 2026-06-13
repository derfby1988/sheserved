-- Migration: Organization First Owner (Owner Onboarding) Trigger
-- Date: 2026-06-13

CREATE OR REPLACE FUNCTION public.on_registration_application_approved_trigger()
RETURNS TRIGGER AS $$
DECLARE
    v_owner_role_id UUID;
    v_main_branch_id UUID;
    v_is_owner_req BOOLEAN;
BEGIN
    -- Only run when status changes to 'approved'
    IF NEW.status = 'approved' AND (OLD.status IS NULL OR OLD.status != 'approved') THEN
        -- Check if it is requested as owner or if it is the first member of this profession
        v_is_owner_req := COALESCE((NEW.registration_data->>'is_owner_request')::boolean, false);
        
        -- If it's requested as owner OR there are no employees in this organization yet
        IF v_is_owner_req OR NOT EXISTS (
            SELECT 1 FROM public.employee_roles 
            WHERE profession_id = NEW.profession_id AND is_active = true
        ) THEN
            -- Find owner role for this profession
            SELECT id INTO v_owner_role_id
            FROM public.organization_roles
            WHERE profession_id = NEW.profession_id AND role_name = 'owner'
            LIMIT 1;

            -- Find main branch (or any branch if not found)
            SELECT id INTO v_main_branch_id
            FROM public.organization_branches
            WHERE profession_id = NEW.profession_id
            ORDER BY is_main_branch DESC, created_at ASC
            LIMIT 1;

            -- Insert employee role as Owner if we have the role
            IF v_owner_role_id IS NOT NULL THEN
                INSERT INTO public.employee_roles (
                    profession_id, branch_id, user_id, role_id, is_active
                )
                VALUES (
                    NEW.profession_id, v_main_branch_id, NEW.user_id, v_owner_role_id, true
                )
                ON CONFLICT (profession_id, user_id, role_id, branch_id) DO NOTHING;
            END IF;
            
            -- Seed default feature flags if none exist
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
            
            -- Seed default payment channels if none exist
            PERFORM public.seed_default_payment_channels(NEW.profession_id);
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Drop trigger if exists
DROP TRIGGER IF EXISTS trg_registration_application_approved ON public.registration_applications;

CREATE TRIGGER trg_registration_application_approved
    AFTER UPDATE ON public.registration_applications
    FOR EACH ROW
    EXECUTE FUNCTION public.on_registration_application_approved_trigger();
