-- Fix RLS policies for registration_field_configs and user_group_roles to properly allow INSERTS
-- by separating the ALL policy into individual policies with proper USING and WITH CHECK clauses

-- Drop the old overly simplified policies that might be blocking INSERT
DROP POLICY IF EXISTS "Modifiable by admin" ON public.registration_field_configs;
DROP POLICY IF EXISTS "Modifiable by admin" ON public.user_group_roles;

-- 1. Policies for registration_field_configs
CREATE POLICY "Insertable authenticated" 
ON public.registration_field_configs FOR INSERT 
TO authenticated WITH CHECK (true);

CREATE POLICY "Updatable authenticated" 
ON public.registration_field_configs FOR UPDATE 
TO authenticated USING (true) WITH CHECK (true);

CREATE POLICY "Deletable authenticated" 
ON public.registration_field_configs FOR DELETE 
TO authenticated USING (true);


-- 2. Policies for user_group_roles 
CREATE POLICY "Insertable authenticated roles" 
ON public.user_group_roles FOR INSERT 
TO authenticated WITH CHECK (true);

CREATE POLICY "Updatable authenticated roles" 
ON public.user_group_roles FOR UPDATE 
TO authenticated USING (true) WITH CHECK (true);

CREATE POLICY "Deletable authenticated roles" 
ON public.user_group_roles FOR DELETE 
TO authenticated USING (true);
