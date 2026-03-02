-- Add color_hex column to professions table
ALTER TABLE professions ADD COLUMN IF NOT EXISTS color_hex TEXT;

-- Update existing built-in professions with some default colors
UPDATE professions SET color_hex = '#2196F3' WHERE id = '00000000-0000-0000-0000-000000000001'; -- Consumer
UPDATE professions SET color_hex = '#FF9800' WHERE id = '00000000-0000-0000-0000-000000000002'; -- Expert
UPDATE professions SET color_hex = '#E91E63' WHERE id = '00000000-0000-0000-0000-000000000003'; -- Clinic
