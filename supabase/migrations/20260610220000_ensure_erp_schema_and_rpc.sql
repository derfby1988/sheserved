-- Migration: Ensure ERP Schema + RPC Functions
-- Safe to re-run: all operations use IF NOT EXISTS / CREATE OR REPLACE
-- Fixes: is_main_branch column, get_organization_header RPC, save_organization_settings RPC

-- ============================================================
-- 1. Ensure professions has ERP fields
-- ============================================================
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'professions' AND column_name = 'logo_url') THEN
        ALTER TABLE public.professions ADD COLUMN logo_url TEXT;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'professions' AND column_name = 'tax_id') THEN
        ALTER TABLE public.professions ADD COLUMN tax_id TEXT;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'professions' AND column_name = 'phone') THEN
        ALTER TABLE public.professions ADD COLUMN phone TEXT;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'professions' AND column_name = 'email') THEN
        ALTER TABLE public.professions ADD COLUMN email TEXT;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'professions' AND column_name = 'address') THEN
        ALTER TABLE public.professions ADD COLUMN address TEXT;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'professions' AND column_name = 'currency') THEN
        ALTER TABLE public.professions ADD COLUMN currency TEXT DEFAULT 'THB';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'professions' AND column_name = 'language') THEN
        ALTER TABLE public.professions ADD COLUMN language TEXT DEFAULT 'th';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'professions' AND column_name = 'timezone') THEN
        ALTER TABLE public.professions ADD COLUMN timezone TEXT DEFAULT 'Asia/Bangkok';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'professions' AND column_name = 'storage_mode') THEN
        ALTER TABLE public.professions ADD COLUMN storage_mode TEXT DEFAULT 'cloud';
        ALTER TABLE public.professions ADD CONSTRAINT chk_storage_mode CHECK (storage_mode IN ('cloud','self_host'));
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'professions' AND column_name = 'self_host_api_url') THEN
        ALTER TABLE public.professions ADD COLUMN self_host_api_url TEXT;
    END IF;
END $$;

-- ============================================================
-- 2. Ensure organization_branches has contact + main_branch fields
-- ============================================================
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'organization_branches' AND column_name = 'address') THEN
        ALTER TABLE public.organization_branches ADD COLUMN address TEXT;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'organization_branches' AND column_name = 'phone') THEN
        ALTER TABLE public.organization_branches ADD COLUMN phone TEXT;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'organization_branches' AND column_name = 'email') THEN
        ALTER TABLE public.organization_branches ADD COLUMN email TEXT;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'organization_branches' AND column_name = 'branch_tax_code') THEN
        ALTER TABLE public.organization_branches ADD COLUMN branch_tax_code TEXT;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'organization_branches' AND column_name = 'is_main_branch') THEN
        ALTER TABLE public.organization_branches ADD COLUMN is_main_branch BOOLEAN DEFAULT false;
    END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_org_branches_main
    ON public.organization_branches(profession_id, is_main_branch)
    WHERE is_main_branch = true;

-- ============================================================
-- 3. Ensure users.branch_id exists
-- ============================================================
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'users' AND column_name = 'branch_id') THEN
        ALTER TABLE public.users ADD COLUMN branch_id UUID REFERENCES public.organization_branches(id) ON DELETE SET NULL;
        CREATE INDEX idx_users_branch ON public.users(branch_id);
    END IF;
END $$;

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
        'currency', COALESCE(currency, 'THB'),
        'language', COALESCE(language, 'th'),
        'timezone', COALESCE(timezone, 'Asia/Bangkok'),
        'storage_mode', COALESCE(storage_mode, 'cloud'),
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
            'branch_tax_code', branch_tax_code,
            'address', address,
            'phone', phone,
            'email', email,
            'is_main_branch', COALESCE(is_main_branch, false),
            'is_active', is_active
        ) ORDER BY COALESCE(is_main_branch, false) DESC, branch_code
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
    p_branch_tax_code TEXT,
    p_address TEXT,
    p_phone TEXT,
    p_email TEXT,
    p_is_main_branch BOOLEAN,
    p_is_active BOOLEAN
) RETURNS JSONB AS $$
DECLARE
    v_id UUID;
    v_result RECORD;
BEGIN
    IF p_branch_id IS NOT NULL THEN
        -- Update existing
        UPDATE public.organization_branches
        SET
            branch_code = p_branch_code,
            branch_name = p_branch_name,
            tax_id = p_tax_id,
            branch_tax_code = p_branch_tax_code,
            address = p_address,
            phone = p_phone,
            email = p_email,
            is_main_branch = p_is_main_branch,
            is_active = p_is_active,
            updated_at = NOW()
        WHERE id = p_branch_id
          AND profession_id = p_profession_id
        RETURNING * INTO v_result;
    END IF;

    IF v_result IS NULL THEN
        -- Insert new
        INSERT INTO public.organization_branches (
            profession_id, branch_code, branch_name,
            tax_id, branch_tax_code, address, phone, email,
            is_main_branch, is_active
        ) VALUES (
            p_profession_id, p_branch_code, p_branch_name,
            p_tax_id, p_branch_tax_code, p_address, p_phone, p_email,
            p_is_main_branch, p_is_active
        )
        RETURNING * INTO v_result;
    END IF;

    RETURN jsonb_build_object(
        'id', v_result.id,
        'profession_id', v_result.profession_id,
        'branch_code', v_result.branch_code,
        'branch_name', v_result.branch_name,
        'tax_id', v_result.tax_id,
        'branch_tax_code', v_result.branch_tax_code,
        'address', v_result.address,
        'phone', v_result.phone,
        'email', v_result.email,
        'is_main_branch', v_result.is_main_branch,
        'is_active', v_result.is_active,
        'created_at', v_result.created_at
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================
-- 7. RPC: Delete Branch
-- ============================================================
CREATE OR REPLACE FUNCTION public.delete_branch(
    p_branch_id UUID,
    p_profession_id UUID
) RETURNS VOID AS $$
BEGIN
    DELETE FROM public.organization_branches
    WHERE id = p_branch_id AND profession_id = p_profession_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
