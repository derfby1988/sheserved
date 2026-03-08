-- Create incident_responses table
CREATE TABLE IF NOT EXISTS public.incident_responses (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    video_id UUID NOT NULL REFERENCES public.videos(id) ON DELETE CASCADE,
    volunteer_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    status TEXT NOT NULL DEFAULT 'accepted',
    accepted_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    arrived_at TIMESTAMP WITH TIME ZONE,
    resolved_at TIMESTAMP WITH TIME ZONE,
    notes TEXT,
    volunteer_start_lat DOUBLE PRECISION,
    volunteer_start_lng DOUBLE PRECISION,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    -- Prevent same volunteer from accepting same incident twice
    UNIQUE (video_id, volunteer_id)
);

-- Performance indexes
CREATE INDEX IF NOT EXISTS idx_incident_responses_volunteer_status 
    ON public.incident_responses(volunteer_id, status);
CREATE INDEX IF NOT EXISTS idx_incident_responses_video 
    ON public.incident_responses(video_id);

-- Add toggle for active volunteer status to consumer_profiles
ALTER TABLE public.consumer_profiles ADD COLUMN IF NOT EXISTS is_volunteer_active BOOLEAN DEFAULT true;

-- RLS: Open policies matching project conventions (auth managed by AuthService, not Supabase Auth)
ALTER TABLE public.incident_responses ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Viewable by everyone" ON public.incident_responses FOR SELECT USING (true);
CREATE POLICY "Insertable by authenticated" ON public.incident_responses FOR INSERT WITH CHECK (true);
CREATE POLICY "Updatable by authenticated" ON public.incident_responses FOR UPDATE USING (true);
