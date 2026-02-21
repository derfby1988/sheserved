-- Create table for storing metadata of medical 3D models
CREATE TABLE IF NOT EXISTS medical_3d_models (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name TEXT NOT NULL,                   -- e.g., 'Male Human Body', 'Female Human Body', 'Human Skeleton'
    category TEXT NOT NULL,               -- e.g., 'full_body', 'organ', 'skeleton'
    gender TEXT,                          -- e.g., 'male', 'female', 'neutral'
    file_url TEXT NOT NULL,               -- The URL or path to the .glb / .gltf file
    thumbnail_url TEXT,                   -- Optional preview image
    description TEXT,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Note: Because models might be large, it's recommended to store actual files 
-- in a Supabase Storage bucket (e.g., 'medical_assets') 
-- and store only the public URL in `file_url`.
-- For now, we will seed it with local asset paths or external URLs.

-- Insert initial sample data
INSERT INTO medical_3d_models (name, category, gender, file_url, description)
VALUES 
    ('Male Human Body', 'full_body', 'male', 'assets/models/male_anatomy.glb', 'Full body anatomical model for male patients'),
    ('Female Human Body', 'full_body', 'female', 'assets/models/female_anatomy.glb', 'Full body anatomical model for female patients'),
    ('Human Skeleton', 'skeleton', 'neutral', 'https://modelviewer.dev/shared-assets/models/Astronaut.glb', 'Detailed human skeletal structure for bone-related issues')
ON CONFLICT DO NOTHING;

-- RLS Settings
ALTER TABLE medical_3d_models ENABLE ROW LEVEL SECURITY;

-- Anyone can view the available 3D models
CREATE POLICY "Public read access for medical 3D models" 
ON medical_3d_models 
FOR SELECT 
USING (true);
