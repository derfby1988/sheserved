-- Migration: Add ERP Organization Fields
-- Adds fields required for Organization Header + Settings
-- Tables affected: professions, organization_branches, users

-- ============================================================
-- 1. PROFESSIONS — Add ERP fields
-- ============================================================
ALTER TABLE public.professions
    ADD COLUMN IF NOT EXISTS logo_url TEXT,
    ADD COLUMN IF NOT EXISTS tax_id TEXT,
    ADD COLUMN IF NOT EXISTS phone TEXT,
    ADD COLUMN IF NOT EXISTS email TEXT,
    ADD COLUMN IF NOT EXISTS address TEXT,
    ADD COLUMN IF NOT EXISTS currency TEXT DEFAULT 'THB',
    ADD COLUMN IF NOT EXISTS language TEXT DEFAULT 'th',
    ADD COLUMN IF NOT EXISTS timezone TEXT DEFAULT 'Asia/Bangkok',
    ADD COLUMN IF NOT EXISTS storage_mode TEXT DEFAULT 'cloud' CHECK (storage_mode IN ('cloud','self_host')),
    ADD COLUMN IF NOT EXISTS self_host_api_url TEXT;

COMMENT ON COLUMN public.professions.logo_url IS 'URL โลโก้องค์กร (Supabase Storage หรือ External)';
COMMENT ON COLUMN public.professions.tax_id IS 'เลขประจำตัวผู้เสียภาษีขององค์กร';
COMMENT ON COLUMN public.professions.phone IS 'เบอร์โทรศัพท์องค์กร';
COMMENT ON COLUMN public.professions.email IS 'อีเมลองค์กร';
COMMENT ON COLUMN public.professions.address IS 'ที่อยู่องค์กร';
COMMENT ON COLUMN public.professions.currency IS 'สกุลเงินเริ่มต้น (THB, USD, etc.)';
COMMENT ON COLUMN public.professions.language IS 'ภาษาเริ่มต้น (th, en)';
COMMENT ON COLUMN public.professions.timezone IS 'เขตเวลา (Asia/Bangkok)';
COMMENT ON COLUMN public.professions.storage_mode IS 'โหมดจัดเก็บข้อมูล: cloud = Supabase, self_host = On-premise';
COMMENT ON COLUMN public.professions.self_host_api_url IS 'URL API ของ Self-host server (ถ้า storage_mode = self_host)';

-- ============================================================
-- 2. ORGANIZATION_BRANCHES — Add contact fields
-- ============================================================
ALTER TABLE public.organization_branches
    ADD COLUMN IF NOT EXISTS address TEXT,
    ADD COLUMN IF NOT EXISTS phone TEXT,
    ADD COLUMN IF NOT EXISTS email TEXT,
    ADD COLUMN IF NOT EXISTS is_main_branch BOOLEAN DEFAULT false;

COMMENT ON COLUMN public.organization_branches.address IS 'ที่อยู่สาขา';
COMMENT ON COLUMN public.organization_branches.phone IS 'เบอร์โทรสาขา';
COMMENT ON COLUMN public.organization_branches.email IS 'อีเมลสาขา';
COMMENT ON COLUMN public.organization_branches.is_main_branch IS 'true = สาขาหลัก (default สำหรับ KPI/Report)';

-- Index for quick lookup of main branch
CREATE INDEX IF NOT EXISTS idx_org_branches_main
    ON public.organization_branches(profession_id, is_main_branch)
    WHERE is_main_branch = true;

-- ============================================================
-- 3. USERS — Add default branch assignment
-- ============================================================
ALTER TABLE public.users
    ADD COLUMN IF NOT EXISTS branch_id UUID REFERENCES public.organization_branches(id) ON DELETE SET NULL;

COMMENT ON COLUMN public.users.branch_id IS 'สาขาที่ user สังกัด (null = ยังไม่ได้ระบุ)';

-- Index for filtering users by branch
CREATE INDEX IF NOT EXISTS idx_users_branch ON public.users(branch_id);

-- ============================================================
-- 4. RPC: Get Organization Header (one-shot fetch)
-- ============================================================
CREATE OR REPLACE FUNCTION public.get_organization_header(
    p_profession_id UUID
) RETURNS JSONB AS $$
DECLARE
    v_profession JSONB;
    v_branches JSONB;
    v_main_branch_id UUID;
BEGIN
    -- Fetch profession data
    SELECT jsonb_build_object(
        'profession_id', id,
        'profession_name', name,
        'profession_name_en', name_en,
        'icon_name', icon_name,
        'color_hex', color_hex,
        'logo_url', logo_url,
        'tax_id', tax_id,
        'phone', phone,
        'email', email,
        'address', address,
        'currency', currency,
        'language', language,
        'timezone', timezone,
        'storage_mode', storage_mode,
        'self_host_api_url', self_host_api_url
    )
    INTO v_profession
    FROM public.professions
    WHERE id = p_profession_id;

    -- Fetch branches
    SELECT jsonb_agg(
        jsonb_build_object(
            'branch_id', id,
            'branch_code', branch_code,
            'branch_name', branch_name,
            'tax_id', tax_id,
            'address', address,
            'phone', phone,
            'email', email,
            'is_main_branch', is_main_branch,
            'is_active', is_active
        ) ORDER BY is_main_branch DESC, branch_code
    )
    INTO v_branches
    FROM public.organization_branches
    WHERE profession_id = p_profession_id
      AND is_active = true;

    -- Find main branch id
    SELECT id INTO v_main_branch_id
    FROM public.organization_branches
    WHERE profession_id = p_profession_id AND is_main_branch = true
    LIMIT 1;

    RETURN jsonb_build_object(
        'profession', v_profession,
        'branches', COALESCE(v_branches, '[]'::jsonb),
        'main_branch_id', v_main_branch_id,
        'total_branches', jsonb_array_length(COALESCE(v_branches, '[]'::jsonb))
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================
-- 5. RPC: Save Organization Settings
-- ============================================================
CREATE OR REPLACE FUNCTION public.save_organization_settings(
    p_profession_id UUID,
    p_name TEXT,
    p_name_en TEXT,
    p_logo_url TEXT,
    p_tax_id TEXT,
    p_phone TEXT,
    p_email TEXT,
    p_address TEXT,
    p_currency TEXT,
    p_language TEXT,
    p_timezone TEXT,
    p_storage_mode TEXT,
    p_self_host_api_url TEXT
) RETURNS VOID AS $$
BEGIN
    UPDATE public.professions
    SET
        name = p_name,
        name_en = p_name_en,
        logo_url = p_logo_url,
        tax_id = p_tax_id,
        phone = p_phone,
        email = p_email,
        address = p_address,
        currency = p_currency,
        language = p_language,
        timezone = p_timezone,
        storage_mode = p_storage_mode,
        self_host_api_url = p_self_host_api_url,
        updated_at = NOW()
    WHERE id = p_profession_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================
-- 6. RPC: Upsert Branch
-- ============================================================
CREATE OR REPLACE FUNCTION public.upsert_branch(
    p_branch_id UUID,
    p_profession_id UUID,
    p_branch_code TEXT,
    p_branch_name TEXT,
    p_tax_id TEXT,
    p_address TEXT,
    p_phone TEXT,
    p_email TEXT,
    p_is_main_branch BOOLEAN,
    p_is_active BOOLEAN
) RETURNS JSONB AS $$
DECLARE
    v_id UUID;
BEGIN
    IF p_branch_id IS NOT NULL THEN
        -- Update existing
        UPDATE public.organization_branches
        SET
            branch_code = p_branch_code,
            branch_name = p_branch_name,
            tax_id = p_tax_id,
            address = p_address,
            phone = p_phone,
            email = p_email,
            is_main_branch = p_is_main_branch,
            is_active = p_is_active,
            updated_at = NOW()
        WHERE id = p_branch_id
          AND profession_id = p_profession_id
        RETURNING id INTO v_id;
    END IF;

    IF v_id IS NULL THEN
        -- Insert new
        INSERT INTO public.organization_branches (
            profession_id, branch_code, branch_name, tax_id,
            address, phone, email, is_main_branch, is_active
        )
        VALUES (
            p_profession_id, p_branch_code, p_branch_name, p_tax_id,
            p_address, p_phone, p_email, p_is_main_branch, COALESCE(p_is_active, true)
        )
        RETURNING id INTO v_id;
    END IF;

    -- If this is marked as main, clear other main branches for same profession
    IF p_is_main_branch THEN
        UPDATE public.organization_branches
        SET is_main_branch = false
        WHERE profession_id = p_profession_id
          AND id != v_id;
    END IF;

    RETURN jsonb_build_object('branch_id', v_id);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================
-- 7. Seed default branch for existing professions
-- ============================================================
INSERT INTO public.organization_branches (
    profession_id, branch_code, branch_name, is_main_branch, is_active
)
SELECT
    p.id,
    'MAIN',
    p.name || ' (สาขาหลัก)',
    true,
    true
FROM public.professions p
WHERE NOT EXISTS (
    SELECT 1 FROM public.organization_branches ob
    WHERE ob.profession_id = p.id
)
ON CONFLICT (profession_id, branch_code) DO NOTHING;
