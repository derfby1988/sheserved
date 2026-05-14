-- Add is_consultation_provider to user_categories table
ALTER TABLE user_categories 
ADD COLUMN IF NOT EXISTS is_consultation_provider BOOLEAN DEFAULT false;

-- Add a comment explaining the column
COMMENT ON COLUMN user_categories.is_consultation_provider IS 'Whether professions in this category can act as consultation providers (e.g. redirect to Request Dashboard instead of Chat Room)';

-- Set default values for known provider categories
UPDATE user_categories 
SET is_consultation_provider = true 
WHERE id IN ('provider', 'health center', 'clinic', 'hospital');
