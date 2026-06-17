-- Add icon_image_url column to body_regions for custom icon images
ALTER TABLE body_regions
ADD COLUMN IF NOT EXISTS icon_image_url TEXT;

COMMENT ON COLUMN body_regions.icon_image_url IS 'Custom icon image URL (PNG) for body map display. Falls back to Material icon via icon_name if null.';
