-- Fix: health_data_permission_requests FK constraints point to auth.users
-- but the app uses a custom public.users table (no Supabase native auth).
-- Drop the broken constraints and re-add them referencing public.users.

ALTER TABLE public.health_data_permission_requests
  DROP CONSTRAINT IF EXISTS health_data_permission_requests_doctor_id_fkey;

ALTER TABLE public.health_data_permission_requests
  DROP CONSTRAINT IF EXISTS health_data_permission_requests_patient_id_fkey;

ALTER TABLE public.health_data_permission_requests
  ADD CONSTRAINT health_data_permission_requests_doctor_id_fkey
  FOREIGN KEY (doctor_id) REFERENCES public.users(id) ON DELETE CASCADE;

ALTER TABLE public.health_data_permission_requests
  ADD CONSTRAINT health_data_permission_requests_patient_id_fkey
  FOREIGN KEY (patient_id) REFERENCES public.users(id) ON DELETE CASCADE;
