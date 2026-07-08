-- Migration: Sync user verification_status for cancelled applications
-- Date: 2026-07-08
-- Fixes existing users whose verification_status is still 'pending' after cancelling

-- 1. แก้ CHECK constraint ให้รองรับ 'cancelled'
ALTER TABLE public.users
  DROP CONSTRAINT IF EXISTS users_verification_status_check;

ALTER TABLE public.users
  ADD CONSTRAINT users_verification_status_check
  CHECK (verification_status IN ('pending', 'verified', 'rejected', 'cancelled'));

-- 2. Backfill: sync users ที่ verification_status ค้างเป็น 'pending' หลังใบสมัครถูกยกเลิก
UPDATE public.users u
SET verification_status = 'cancelled',
    updated_at = now()
WHERE u.verification_status = 'pending'
  AND EXISTS (
    SELECT 1 FROM public.registration_applications a
    WHERE a.user_id = u.id
      AND a.status = 'cancelled'
  )
  AND NOT EXISTS (
    SELECT 1 FROM public.registration_applications a2
    WHERE a2.user_id = u.id
      AND a2.status = 'pending'
  );

-- Reload PostgREST schema cache
NOTIFY pgrst, 'reload schema';
