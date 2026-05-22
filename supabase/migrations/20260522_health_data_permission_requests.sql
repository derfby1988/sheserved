-- Create table for health data permission requests between doctors and patients
CREATE TABLE IF NOT EXISTS health_data_permission_requests (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  doctor_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  doctor_name TEXT NOT NULL DEFAULT 'Doctor',
  patient_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  status TEXT NOT NULL DEFAULT 'pending',   -- pending / granted / denied
  granted_fields JSONB DEFAULT '{"general":true,"device_scores":true,"labs":true,"medications":true}',
  requested_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- Enable RLS
ALTER TABLE health_data_permission_requests ENABLE ROW LEVEL SECURITY;

-- Doctor can insert permission requests
CREATE POLICY "Doctor can request" ON health_data_permission_requests
  FOR INSERT WITH CHECK (auth.uid() = doctor_id);

-- Doctor and Patient can read their own requests
CREATE POLICY "Participants can read" ON health_data_permission_requests
  FOR SELECT USING (auth.uid() = doctor_id OR auth.uid() = patient_id);

-- Patient can update (respond to) requests addressed to them
CREATE POLICY "Patient can respond" ON health_data_permission_requests
  FOR UPDATE USING (auth.uid() = patient_id);

-- Enable Realtime for this table
ALTER PUBLICATION supabase_realtime ADD TABLE health_data_permission_requests;
