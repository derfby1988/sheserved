-- Migration: Standard Chart of Accounts master table + profession seeding
-- Date: 2026-06-13
-- Goal: Keep the Thai standard chart in a read-only master table and seed
--       each profession's own chart_of_accounts from that master.

-- ============================================================
-- 1. MASTER TABLE: standard_chart_of_accounts
-- ============================================================
CREATE TABLE IF NOT EXISTS public.standard_chart_of_accounts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    account_code TEXT NOT NULL UNIQUE,
    account_name TEXT NOT NULL,
    account_type TEXT NOT NULL
        CHECK (account_type IN ('asset', 'liability', 'equity', 'revenue', 'expense')),
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

DROP TRIGGER IF EXISTS trg_standard_chart_of_accounts_updated_at ON public.standard_chart_of_accounts;
CREATE TRIGGER trg_standard_chart_of_accounts_updated_at
    BEFORE UPDATE ON public.standard_chart_of_accounts
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE INDEX IF NOT EXISTS idx_standard_chart_of_accounts_type
    ON public.standard_chart_of_accounts(account_type, account_code);

ALTER TABLE public.standard_chart_of_accounts ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS standard_chart_of_accounts_select ON public.standard_chart_of_accounts;
CREATE POLICY standard_chart_of_accounts_select
    ON public.standard_chart_of_accounts
    FOR SELECT
    USING (true);

-- ============================================================
-- 2. POPULATE MASTER TABLE FROM THE LEGACY SHESERVED STANDARD CHART
--    (source of truth moves to the master table; the app will no longer
--     hardcode the chart in Flutter/repository logic)
-- ============================================================
INSERT INTO public.standard_chart_of_accounts (account_code, account_name, account_type)
SELECT DISTINCT ON (coa.account_code)
    coa.account_code,
    coa.account_name,
    CASE COALESCE(coa.account_type::text, '')
        WHEN '1' THEN 'asset'
        WHEN '2' THEN 'liability'
        WHEN '3' THEN 'equity'
        WHEN '4' THEN 'revenue'
        WHEN '5' THEN 'expense'
        ELSE coa.account_type::text
    END AS account_type
FROM public.chart_of_accounts coa
WHERE coa.profession_id = '00000000-0000-0000-0000-000000000003'
ORDER BY coa.account_code
ON CONFLICT (account_code) DO NOTHING;

-- ============================================================
-- 3. NORMALIZE COMPANY CHART TABLE TO MATCH THE APP MODEL
-- ============================================================
-- Optional link to master row for traceability (does not change runtime behavior)
ALTER TABLE public.chart_of_accounts
    ADD COLUMN IF NOT EXISTS standard_account_id UUID REFERENCES public.standard_chart_of_accounts(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_chart_of_accounts_standard_account
    ON public.chart_of_accounts(standard_account_id);

UPDATE public.chart_of_accounts coa
SET standard_account_id = s.id
FROM public.standard_chart_of_accounts s
WHERE coa.account_code = s.account_code
  AND coa.standard_account_id IS NULL;

CREATE OR REPLACE FUNCTION public.get_chart_of_accounts_account_type_mode()
RETURNS TEXT AS $$
DECLARE
    v_type TEXT;
BEGIN
    SELECT data_type
    INTO v_type
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'chart_of_accounts'
      AND column_name = 'account_type';

    IF v_type IN ('smallint', 'integer', 'bigint', 'numeric', 'real', 'double precision') THEN
        RETURN 'numeric';
    END IF;

    RETURN 'text';
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

-- ============================================================
-- 4. SEED FUNCTION: COPY MASTER CHART INTO A PROFESSION'S OWN CHART
-- ============================================================
CREATE OR REPLACE FUNCTION public.seed_profession_chart_of_accounts(
    p_profession_id UUID
)
RETURNS INTEGER AS $$
DECLARE
    v_rows INTEGER := 0;
    v_mode TEXT := public.get_chart_of_accounts_account_type_mode();
    v_sql TEXT;
BEGIN
    IF v_mode = 'numeric' THEN
        v_sql := $sql$
            INSERT INTO public.chart_of_accounts (
                profession_id,
                account_code,
                account_name,
                account_type,
                parent_id,
                is_active,
                created_at,
                updated_at,
                standard_account_id,
                is_custom
            )
            SELECT
                $1,
                s.account_code,
                s.account_name,
                CASE s.account_type
                    WHEN 'asset' THEN 1
                    WHEN 'liability' THEN 2
                    WHEN 'equity' THEN 3
                    WHEN 'revenue' THEN 4
                    WHEN 'expense' THEN 5
                END,
                NULL,
                true,
                NOW(),
                NOW(),
                s.id,
                false
            FROM public.standard_chart_of_accounts s
            WHERE s.is_active = true
            ON CONFLICT (profession_id, account_code) DO NOTHING
        $sql$;
    ELSE
        v_sql := $sql$
            INSERT INTO public.chart_of_accounts (
                profession_id,
                account_code,
                account_name,
                account_type,
                parent_id,
                is_active,
                created_at,
                updated_at,
                standard_account_id,
                is_custom
            )
            SELECT
                $1,
                s.account_code,
                s.account_name,
                s.account_type,
                NULL,
                true,
                NOW(),
                NOW(),
                s.id,
                false
            FROM public.standard_chart_of_accounts s
            WHERE s.is_active = true
            ON CONFLICT (profession_id, account_code) DO NOTHING
        $sql$;
    END IF;

    EXECUTE v_sql USING p_profession_id;

    GET DIAGNOSTICS v_rows = ROW_COUNT;
    RETURN v_rows;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================
-- 5. AUTO-SEED NEW PROFESSIONS
-- ============================================================
CREATE OR REPLACE FUNCTION public.handle_new_profession_chart_of_accounts()
RETURNS TRIGGER AS $$
BEGIN
    PERFORM public.seed_profession_chart_of_accounts(NEW.id);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_seed_chart_of_accounts_on_profession_insert ON public.professions;
CREATE TRIGGER trg_seed_chart_of_accounts_on_profession_insert
    AFTER INSERT ON public.professions
    FOR EACH ROW
    EXECUTE FUNCTION public.handle_new_profession_chart_of_accounts();

-- ============================================================
-- 6. ADD is_custom FLAG TO DISTINGUISH USER-CREATED ACCOUNTS
-- ============================================================
ALTER TABLE public.chart_of_accounts
    ADD COLUMN IF NOT EXISTS is_custom BOOLEAN NOT NULL DEFAULT false;

-- Existing seeded rows came from the master → mark as not custom
UPDATE public.chart_of_accounts
SET is_custom = false
WHERE standard_account_id IS NOT NULL
  AND is_custom = true;

-- ============================================================
-- 7. BACKFILL ALL EXISTING PROFESSIONS
-- ============================================================
DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN SELECT id FROM public.professions LOOP
        PERFORM public.seed_profession_chart_of_accounts(r.id);
    END LOOP;
END $$;

-- ============================================================
-- 8. RESET FUNCTION: REVERT A MODIFIED ACCOUNT BACK TO MASTER
-- ============================================================
CREATE OR REPLACE FUNCTION public.reset_chart_of_account_to_standard(
    p_account_id UUID
)
RETURNS BOOLEAN AS $$
DECLARE
    v_standard_id UUID;
    v_mode TEXT;
    v_rows INTEGER;
BEGIN
    SELECT standard_account_id
    INTO v_standard_id
    FROM public.chart_of_accounts
    WHERE id = p_account_id;

    IF v_standard_id IS NULL THEN
        RETURN false;
    END IF;

    v_mode := public.get_chart_of_accounts_account_type_mode();

    IF v_mode = 'numeric' THEN
        UPDATE public.chart_of_accounts ca
        SET
            account_code = s.account_code,
            account_name = s.account_name,
            account_type = CASE s.account_type
                WHEN 'asset'    THEN 1
                WHEN 'liability' THEN 2
                WHEN 'equity'   THEN 3
                WHEN 'revenue'  THEN 4
                WHEN 'expense'  THEN 5
            END,
            is_custom = false
        FROM public.standard_chart_of_accounts s
        WHERE ca.id = p_account_id
          AND s.id = v_standard_id;
    ELSE
        UPDATE public.chart_of_accounts ca
        SET
            account_code = s.account_code,
            account_name = s.account_name,
            account_type = s.account_type,
            is_custom = false
        FROM public.standard_chart_of_accounts s
        WHERE ca.id = p_account_id
          AND s.id = v_standard_id;
    END IF;

    GET DIAGNOSTICS v_rows = ROW_COUNT;
    RETURN v_rows > 0;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================
-- 9. DEPENDENCY CHECK & DELETE FOR CHART OF ACCOUNTS
-- ============================================================

CREATE OR REPLACE FUNCTION public.get_chart_of_account_dependencies(
    p_account_id UUID
)
RETURNS JSONB AS $$
DECLARE
    v_gl_count INTEGER := 0;
    v_journal_count INTEGER := 0;
    v_parent_count INTEGER := 0;
    v_linked_products JSONB := '[]'::JSONB;
BEGIN
    SELECT COUNT(*) INTO v_gl_count
    FROM public.gl_entries
    WHERE account_id = p_account_id;

    SELECT COUNT(*) INTO v_journal_count
    FROM public.journal_entry_lines
    WHERE account_id = p_account_id;

    SELECT COUNT(*) INTO v_parent_count
    FROM public.chart_of_accounts
    WHERE parent_id = p_account_id;

    SELECT COALESCE(jsonb_agg(
        jsonb_build_object(
            'product_id', product_id,
            'product_type', product_type,
            'mapping_type', CASE
                WHEN revenue_account_id = p_account_id THEN 'revenue'
                WHEN cogs_account_id = p_account_id THEN 'cogs'
                WHEN inventory_account_id = p_account_id THEN 'inventory'
                WHEN adjustment_account_id = p_account_id THEN 'adjustment'
            END
        )
    ), '[]'::JSONB)
    INTO v_linked_products
    FROM public.product_account_mappings
    WHERE revenue_account_id = p_account_id
       OR cogs_account_id = p_account_id
       OR inventory_account_id = p_account_id
       OR adjustment_account_id = p_account_id;

    RETURN jsonb_build_object(
        'can_delete', (v_gl_count = 0 AND v_journal_count = 0 AND v_parent_count = 0),
        'gl_entries_count', v_gl_count,
        'journal_lines_count', v_journal_count,
        'parent_accounts_count', v_parent_count,
        'linked_products', v_linked_products
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION public.delete_chart_of_account(
    p_account_id UUID
)
RETURNS JSONB AS $$
DECLARE
    v_deps JSONB;
BEGIN
    v_deps := public.get_chart_of_account_dependencies(p_account_id);

    IF NOT (v_deps->>'can_delete')::BOOLEAN THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'บัญชีนี้มีรายการเคลื่อนไหวหรือถูกอ้างอิงโดยสินค้า/บริการอื่น',
            'dependencies', v_deps
        );
    END IF;

    DELETE FROM public.chart_of_accounts WHERE id = p_account_id;

    RETURN jsonb_build_object('success', true);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
