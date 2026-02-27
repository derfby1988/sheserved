-- Migration: Fix RLS for users table to support real-time online counts
-- Created at: 2026-02-27 13:40:00

DO $$
BEGIN
    -- 1. Ensure RLS is enabled on public.users
    -- Note: We use public.users because the app repositories interact with this table
    IF EXISTS (SELECT 1 FROM pg_tables WHERE schemaname = 'public' AND tablename = 'users') THEN
        ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;

        -- 2. Policy: Allow everyone (including guests) to see basic user info 
        -- This is required for real-time online counts to work across different devices
        IF NOT EXISTS (
            SELECT 1 FROM pg_policies WHERE tablename = 'users' AND policyname = 'Allow public read access for users'
        ) THEN
            CREATE POLICY "Allow public read access for users" ON public.users
            FOR SELECT USING (true);
        END IF;

        -- 3. Policy: Allow users to update their own record
        -- Required for PresenceService heartbeat and updating availability_status
        IF NOT EXISTS (
            SELECT 1 FROM pg_policies WHERE tablename = 'users' AND policyname = 'Allow users to update own record'
        ) THEN
            CREATE POLICY "Allow users to update own record" ON public.users
            FOR UPDATE USING (auth.uid() = id) WITH CHECK (auth.uid() = id);
        END IF;
        
        -- 4. Policy: Allow users to insert their own record (for registration)
        IF NOT EXISTS (
            SELECT 1 FROM pg_policies WHERE tablename = 'users' AND policyname = 'Allow users to insert own record'
        ) THEN
            CREATE POLICY "Allow users to insert own record" ON public.users
            FOR INSERT WITH CHECK (auth.uid() = id);
        END IF;
    END IF;
END $$;

-- 5. Ensure the users table is included in real-time replication
-- We do this again to be absolutely sure
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
        IF NOT EXISTS (
            SELECT 1 FROM pg_publication_tables 
            WHERE pubname = 'supabase_realtime' 
            AND schemaname = 'public' 
            AND tablename = 'users'
        ) THEN
            ALTER PUBLICATION supabase_realtime ADD TABLE public.users;
        END IF;
    END IF;
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'Could not add users table to publication: %', SQLERRM;
END $$;
