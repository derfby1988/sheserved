-- Create Consultation Requests table
CREATE TABLE consultation_requests (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  package_id TEXT,             -- e.g., 'doctor_consultation_299'
  package_name TEXT,           -- e.g., 'แพ็คเกจ สำหรับปรึกษาผู้เชี่ยวชาญ'
  price NUMERIC(10, 2),        -- e.g., 299.0
  body_area JSONB,             -- Stores specific locations (height/part)
  symptoms_chart JSONB,        -- Stores the hexagon chart values (e.g., {"headache": "high", "nausea": "medium"})
  status TEXT DEFAULT 'pending', -- 'pending', 'assigned', 'completed'
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Index for querying consultation requests by user
CREATE INDEX idx_consultation_requests_user_id ON consultation_requests(user_id);

-- Enable RLS
ALTER TABLE consultation_requests ENABLE ROW LEVEL SECURITY;

-- Policy for Users to insert their own requests
CREATE POLICY "Users can create their own consultation requests" 
ON consultation_requests FOR INSERT 
WITH CHECK (auth.uid() = user_id);

-- Policy for Users to view their own requests
CREATE POLICY "Users can view their own consultation requests" 
ON consultation_requests FOR SELECT 
USING (auth.uid() = user_id);

-- Policy for Experts/Clinics to view requests (can be adjusted later based on assignment logic)
CREATE POLICY "Experts can view all pending requests" 
ON consultation_requests FOR SELECT 
-- For now allow read if they are experts (optional logic: auth.uid() IN (SELECT id FROM users WHERE user_type = 'expert'))
USING (true);

-- Policy for Users to upate their own requests (e.g., status changes like cancel)
CREATE POLICY "Users can update their own consultation requests"
ON consultation_requests FOR UPDATE
USING (auth.uid() = user_id);
