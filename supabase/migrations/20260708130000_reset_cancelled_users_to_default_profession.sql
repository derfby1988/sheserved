-- Migration: Reset cancelled/rejected users to default consumer profession
-- Date: 2026-07-08
-- When a user's provider application was cancelled (by user) or rejected (by admin),
-- revert them to the default Sheserved consumer profession (same as register wizard default).

-- Built-in consumer profession UUID defined in Profession.consumerProfessionId
UPDATE public.users u
SET profession_id = '00000000-0000-0000-0000-000000000001',
    role = 'consumer',
    verification_status = 'verified',
    updated_at = now()
WHERE u.profession_id != '00000000-0000-0000-0000-000000000001'
  AND u.verification_status IN ('pending', 'cancelled', 'rejected')
  AND EXISTS (
    SELECT 1 FROM public.registration_applications a
    WHERE a.user_id = u.id
      AND a.status IN ('cancelled', 'rejected')
  )
  AND NOT EXISTS (
    SELECT 1 FROM public.registration_applications a2
    WHERE a2.user_id = u.id
      AND a2.status IN ('pending', 'approved')
  )
  AND NOT EXISTS (
    SELECT 1 FROM public.employee_roles er
    WHERE er.user_id = u.id
      AND er.is_active = true
  );

-- Reload PostgREST schema cache
NOTIFY pgrst, 'reload schema';
