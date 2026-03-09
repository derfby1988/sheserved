CREATE TABLE IF NOT EXISTS public.app_settings (
    key VARCHAR PRIMARY KEY,
    value JSONB NOT NULL,
    description TEXT,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- RLS
ALTER TABLE public.app_settings ENABLE ROW LEVEL SECURITY;

-- Everyone can read
CREATE POLICY "Enable read access for all users" ON public.app_settings
    FOR SELECT USING (true);

-- Allow updates (per custom auth pattern where Supabase role is anon)
CREATE POLICY "Enable update for all users" ON public.app_settings
    FOR UPDATE USING (true);
CREATE POLICY "Enable insert for all users" ON public.app_settings
    FOR INSERT WITH CHECK (true);

-- Insert default settings for Video System
INSERT INTO public.app_settings (key, value, description)
VALUES (
    'video_system_config',
    '{"videoUploadCooldownSeconds": 3, "maxVideoFileSizeMB": 20, "dailyVideoUploadQuota": 50, "maxEmergencyRecordingSeconds": 60}'::jsonb,
    'Configuration for video upload and recording system'
) ON CONFLICT (key) DO NOTHING;
