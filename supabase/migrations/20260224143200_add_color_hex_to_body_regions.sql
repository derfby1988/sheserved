-- Add color_hex column to body_regions table
ALTER TABLE public.body_regions ADD COLUMN IF NOT EXISTS color_hex TEXT;

-- Update the seed function if needed (optional since we use Dart seeding)
