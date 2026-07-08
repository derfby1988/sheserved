-- Migration: RLS policies for registration_applications
-- Date: 2026-07-07
--
-- ปัญหา: registration_applications เปิด RLS ไว้แต่ไม่มี policy ใดๆ
-- ทำให้ INSERT/UPDATE ถูกปฏิเสธ (42501 new row violates row-level security policy)
-- โดยเฉพาะเมื่อ user เปลี่ยนอาชีพแล้วสร้างใบสมัครใหม่ และเมื่อยกเลิกใบสมัคร
--
-- บริบท: แอปใช้ custom phone auth ไม่ได้สร้าง Supabase Auth session
-- ดังนั้น auth.uid() เป็น null — policy ที่อิง auth.uid() จะใช้ไม่ได้
-- แอป scope user_id ที่ระดับ repository (.eq('user_id', userId)) อยู่แล้ว
-- จึงใช้ permissive policy ให้สอดคล้องกับตารางอื่นในระบบ (เช่น users SELECT USING true)

DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM pg_tables
        WHERE schemaname = 'public' AND tablename = 'registration_applications'
    ) THEN
        ALTER TABLE public.registration_applications ENABLE ROW LEVEL SECURITY;

        -- SELECT: ให้ user และ admin อ่านใบสมัครได้ (scope ที่ repository)
        IF NOT EXISTS (
            SELECT 1 FROM pg_policies
            WHERE tablename = 'registration_applications'
              AND policyname = 'Allow read registration applications'
        ) THEN
            CREATE POLICY "Allow read registration applications"
            ON public.registration_applications
            FOR SELECT USING (true);
        END IF;

        -- INSERT: ให้สร้างใบสมัครใหม่ได้ (scope user_id ที่ repository)
        IF NOT EXISTS (
            SELECT 1 FROM pg_policies
            WHERE tablename = 'registration_applications'
              AND policyname = 'Allow insert registration applications'
        ) THEN
            CREATE POLICY "Allow insert registration applications"
            ON public.registration_applications
            FOR INSERT WITH CHECK (true);
        END IF;

        -- UPDATE: ให้อัปเดตสถานะได้ (ยกเลิกโดย user / อนุมัติ-ปฏิเสธโดย admin)
        IF NOT EXISTS (
            SELECT 1 FROM pg_policies
            WHERE tablename = 'registration_applications'
              AND policyname = 'Allow update registration applications'
        ) THEN
            CREATE POLICY "Allow update registration applications"
            ON public.registration_applications
            FOR UPDATE USING (true) WITH CHECK (true);
        END IF;
    END IF;
END $$;

-- Reload PostgREST schema cache
NOTIFY pgrst, 'reload schema';
