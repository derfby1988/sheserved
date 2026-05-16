-- Migration: Create platform_metrics table and increment function
-- Created at: 2026-05-16 12:05:00

CREATE TABLE IF NOT EXISTS platform_metrics (
    platform TEXT NOT NULL,
    metric_name TEXT NOT NULL,
    count BIGINT DEFAULT 0,
    last_updated TIMESTAMPTZ DEFAULT NOW(),
    PRIMARY KEY (platform, metric_name)
);

-- Enable RLS
ALTER TABLE platform_metrics ENABLE ROW LEVEL SECURITY;

-- Allow public to read/update (or restrict to authenticated/service_role as needed)
-- For this simple analytics, we allow upsert from the app
CREATE POLICY "Allow public read platform_metrics" ON platform_metrics FOR SELECT USING (true);
CREATE POLICY "Allow public insert/update platform_metrics" ON platform_metrics FOR ALL USING (true) WITH CHECK (true);

-- Function to safely increment metrics (avoiding race conditions)
CREATE OR REPLACE FUNCTION increment_platform_metric(p_platform TEXT, p_metric_name TEXT)
RETURNS VOID AS $$
BEGIN
    INSERT INTO platform_metrics (platform, metric_name, count, last_updated)
    VALUES (p_platform, p_metric_name, 1, NOW())
    ON CONFLICT (platform, metric_name)
    DO UPDATE SET count = platform_metrics.count + 1, last_updated = NOW();
END;
$$ LANGUAGE plpgsql;
