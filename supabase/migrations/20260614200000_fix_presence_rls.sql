-- Migration: Fix RLS for PresenceService heartbeat and availability_status updates
-- Problem: Custom AuthService doesn't use Supabase Auth, so auth.uid() is null.
--          The existing RLS policy "Allow users to update own record" uses auth.uid() = id,
--          which blocks PresenceService from updating last_seen_at and availability_status.
-- Solution: Create SECURITY DEFINER RPC functions that bypass RLS for presence updates.

-- =====================================================
-- 1. Create RPC function for heartbeat (update last_seen_at)
-- =====================================================
CREATE OR REPLACE FUNCTION public.update_last_seen(user_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    UPDATE public.users
    SET last_seen_at = NOW()
    WHERE id = user_id;
END;
$$;

-- =====================================================
-- 2. Create RPC function for availability status update
-- =====================================================
CREATE OR REPLACE FUNCTION public.update_availability_status(
    user_id UUID,
    new_status TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    UPDATE public.users
    SET availability_status = new_status,
        last_seen_at = NOW()
    WHERE id = user_id;
END;
$$;

-- =====================================================
-- 3. Grant execute permissions to authenticated and anon roles
-- =====================================================
GRANT EXECUTE ON FUNCTION public.update_last_seen(UUID) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.update_availability_status(UUID, TEXT) TO anon, authenticated;

-- =====================================================
-- 4. Add comment for documentation
-- =====================================================
COMMENT ON FUNCTION public.update_last_seen(UUID) IS
    'Updates last_seen_at for a user. Used by Flutter PresenceService heartbeat. Bypasses RLS via SECURITY DEFINER because the app uses custom auth (not Supabase Auth).';

COMMENT ON FUNCTION public.update_availability_status(UUID, TEXT) IS
    'Updates availability_status and last_seen_at for a user. Used by Flutter PresenceService. Bypasses RLS via SECURITY DEFINER because the app uses custom auth (not Supabase Auth).';
