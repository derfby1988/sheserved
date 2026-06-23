-- Migration: Add role column to users table for route security
-- Phase 0 of Route Security Implementation Plan
-- Date: 2026-06-22

-- 1. Add role column with check constraint for valid values
ALTER TABLE users
ADD COLUMN IF NOT EXISTS role TEXT DEFAULT 'consumer';

-- 2. Add check constraint for valid role values
-- Note: This constraint is added as NOT VALID first to avoid locking on large tables,
-- then validated. If the table is small, it can be added directly.
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'users_role_check'
        AND conrelid = 'users'::regclass
    ) THEN
        ALTER TABLE users
        ADD CONSTRAINT users_role_check
        CHECK (role IN ('consumer', 'provider', 'admin'));
    END IF;
END $$;

-- 3. Backfill existing users based on profession_id
-- consumer UUID: '00000000-0000-0000-0000-000000000001'
UPDATE users
SET role = 'provider'
WHERE profession_id IS NOT NULL
  AND profession_id != '00000000-0000-0000-0000-000000000001'
  AND (role IS NULL OR role = 'consumer');

-- 4. Ensure all NULL roles are set to 'consumer' (safety net)
UPDATE users
SET role = 'consumer'
WHERE role IS NULL;

-- 5. Create helper function for backend to check admin role
-- This function can be used by the API/websocket-server or in RPC calls
CREATE OR REPLACE FUNCTION is_admin_role(p_user_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM users
        WHERE id = p_user_id
          AND role = 'admin'
          AND is_active = true
    );
END;
$$;

-- 6. Create helper function to get user role
CREATE OR REPLACE FUNCTION get_user_role(p_user_id UUID)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_role TEXT;
BEGIN
    SELECT role INTO v_role
    FROM users
    WHERE id = p_user_id;
    RETURN COALESCE(v_role, 'consumer');
END;
$$;

-- 7. Add index on role for faster filtering (optional but recommended for admin lookups)
CREATE INDEX IF NOT EXISTS idx_users_role ON users(role);

-- 8. Comment on the column for documentation
COMMENT ON COLUMN users.role IS 'User role: consumer | provider | admin. Used for route-level access control.';
