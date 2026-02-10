-- =====================================================
-- 01 Create Health Data Logs Table
-- =====================================================

CREATE TABLE IF NOT EXISTS health_data_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    field_type VARCHAR(50) NOT NULL CHECK (field_type IN ('weight', 'height', 'bmi', 'age')),
    old_value TEXT,
    new_value TEXT NOT NULL,
    created_by UUID REFERENCES users(id), -- User who made the change
    editor_name TEXT, -- Snapshot of editor's name for easier display
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Index for faster querying by user and field
CREATE INDEX IF NOT EXISTS idx_health_data_logs_user_field ON health_data_logs(user_id, field_type);
CREATE INDEX IF NOT EXISTS idx_health_data_logs_created_at ON health_data_logs(created_at DESC);

-- Enable RLS (Row Level Security) if not already enabled on other tables, but good practice
ALTER TABLE health_data_logs ENABLE ROW LEVEL SECURITY;

-- Policy: Users can view their own health logs
CREATE POLICY "Users can view own health logs" ON health_data_logs
  FOR SELECT USING (auth.uid() = user_id);

-- Policy: Users can insert their own health logs
CREATE POLICY "Users can insert own health logs" ON health_data_logs
  FOR INSERT WITH CHECK (auth.uid() = user_id);
