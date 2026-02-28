-- Drop existing policies if they block insert
DROP POLICY IF EXISTS "Enable insert for authenticated users only" ON public.medications;
DROP POLICY IF EXISTS "Enable insert access for all users" ON public.medications;

-- Create policy to allow insert for everyone (for testing only, in production restrict this)
CREATE POLICY "Enable insert access for all users" ON public.medications FOR INSERT WITH CHECK (true);
