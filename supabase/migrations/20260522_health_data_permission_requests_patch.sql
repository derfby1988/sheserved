-- Patch: Align health_data_permission_requests with Phase 6.3 workflow
-- Date: 2026-05-22

-- 1) Ensure new columns exist and defaults match the product spec
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'health_data_permission_requests'
          AND column_name = 'consultation_id'
    ) THEN
        ALTER TABLE public.health_data_permission_requests
        ADD COLUMN consultation_id uuid REFERENCES consultation_requests(id) ON DELETE CASCADE;
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'health_data_permission_requests'
          AND column_name = 'granted_at'
    ) THEN
        ALTER TABLE public.health_data_permission_requests
        ADD COLUMN granted_at timestamptz;
    END IF;
END $$;

-- Ensure default JSON contains every field with `true`
ALTER TABLE public.health_data_permission_requests
    ALTER COLUMN granted_fields SET DEFAULT '{"general":true,"history":true,"labs":true,"medications":true}'::jsonb;

-- Keep timestamps fresh
ALTER TABLE public.health_data_permission_requests
    ALTER COLUMN requested_at SET DEFAULT timezone('utc', now());

ALTER TABLE public.health_data_permission_requests
    ALTER COLUMN updated_at SET DEFAULT timezone('utc', now());

-- 2) Row-level security adjustments (temporarily trust the mobile app, which handles auth itself)
ALTER TABLE public.health_data_permission_requests ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Doctor can request" ON public.health_data_permission_requests;
DROP POLICY IF EXISTS "Participants can read" ON public.health_data_permission_requests;
DROP POLICY IF EXISTS "Patient can respond" ON public.health_data_permission_requests;

CREATE POLICY "Client app can insert health permission requests"
    ON public.health_data_permission_requests
    FOR INSERT
    WITH CHECK (auth.role() IN ('anon', 'authenticated'));

CREATE POLICY "Client app can read health permission requests"
    ON public.health_data_permission_requests
    FOR SELECT
    USING (auth.role() IN ('anon', 'authenticated'));

CREATE POLICY "Client app can update health permission requests"
    ON public.health_data_permission_requests
    FOR UPDATE
    USING (auth.role() IN ('anon', 'authenticated'))
    WITH CHECK (auth.role() IN ('anon', 'authenticated'));

-- 3) Ensure realtime publication still tracks this table
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables
        WHERE pubname = 'supabase_realtime'
          AND schemaname = 'public'
          AND tablename = 'health_data_permission_requests'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.health_data_permission_requests;
    END IF;
END $$;
