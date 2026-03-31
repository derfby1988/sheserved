-- Migration: Make title in donation_requests nullable
-- Since we are moving to fully dynamic Global Fields, 'title' is no longer a strictly required column.
-- It will be managed actively via the admin Global Fields configurations.

ALTER TABLE public.donation_requests 
ALTER COLUMN title DROP NOT NULL;
