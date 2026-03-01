ALTER TABLE public.clinical_knowledge ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Enable insert access for all users" ON public.clinical_knowledge;
CREATE POLICY "Enable insert access for all users" ON public.clinical_knowledge FOR INSERT WITH CHECK (true);
DROP POLICY IF EXISTS "Enable read access for all users" ON public.clinical_knowledge;
CREATE POLICY "Enable read access for all users" ON public.clinical_knowledge FOR SELECT USING (true);
