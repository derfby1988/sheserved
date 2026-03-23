-- Create thai_mhung_photos table
CREATE TABLE IF NOT EXISTS public.thai_mhung_photos (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    video_id UUID NOT NULL REFERENCES public.videos(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES public.users(id),
    photo_url TEXT NOT NULL,
    latitude DOUBLE PRECISION,
    longitude DOUBLE PRECISION,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Index for performance
CREATE INDEX IF NOT EXISTS idx_thai_mhung_photos_video_id ON public.thai_mhung_photos(video_id);

-- RLS: Open for simplicity (matching project conventions)
ALTER TABLE public.thai_mhung_photos ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Viewable by everyone" ON public.thai_mhung_photos FOR SELECT USING (true);
CREATE POLICY "Insertable by anyone" ON public.thai_mhung_photos FOR INSERT WITH CHECK (true);
