-- Migration: Add video_id to donation_requests
ALTER TABLE public.donation_requests 
ADD COLUMN video_id UUID REFERENCES public.videos(id);
