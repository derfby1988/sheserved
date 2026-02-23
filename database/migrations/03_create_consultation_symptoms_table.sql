-- Add Symptoms table as a child of consultation_requests
CREATE TABLE consultation_symptoms (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  request_id UUID NOT NULL REFERENCES consultation_requests(id) ON DELETE CASCADE,
  region_id TEXT NOT NULL,      -- e.g., 'shoulder'
  side TEXT NOT NULL,            -- 'left', 'right', 'center'
  symptom TEXT NOT NULL,         -- 'ปวด', 'เจ็บ'
  display_label TEXT,            -- 'หัวไหล่(ซ้าย): ปวด'
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Index for querying symptoms by request
CREATE INDEX idx_consultation_symptoms_request_id ON consultation_symptoms(request_id);

-- Enable RLS
ALTER TABLE consultation_symptoms ENABLE ROW LEVEL SECURITY;

-- Policy: Users can view symptoms of their own requests
CREATE POLICY "Users can view symptoms of their own requests" 
ON consultation_symptoms FOR SELECT 
USING (
  EXISTS (
    SELECT 1 FROM consultation_requests 
    WHERE consultation_requests.id = consultation_symptoms.request_id 
    AND consultation_requests.user_id = auth.uid()
  )
);

-- Policy: Users can insert symptoms for their own requests
CREATE POLICY "Users can insert symptoms for their own requests" 
ON consultation_symptoms FOR INSERT 
WITH CHECK (
  EXISTS (
    SELECT 1 FROM consultation_requests 
    WHERE consultation_requests.id = consultation_symptoms.request_id 
    AND consultation_requests.user_id = auth.uid()
  )
);
