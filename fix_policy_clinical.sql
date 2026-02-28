DROP POLICY IF EXISTS "Enable insert access for all users" ON public.clinical_knowledge;
CREATE POLICY "Enable insert access for all users" ON public.clinical_knowledge FOR INSERT WITH CHECK (true);
