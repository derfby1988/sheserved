-- Create device_health_metrics table for time-series health data
CREATE TABLE IF NOT EXISTS public.device_health_metrics (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    metric_type TEXT NOT NULL, -- e.g., 'steps', 'heart_rate', 'sleep_duration', 'active_calories'
    value NUMERIC NOT NULL,
    unit TEXT, -- e.g., 'count', 'bpm', 'minutes', 'kcal'
    measured_at TIMESTAMPTZ NOT NULL,
    source_name TEXT, -- e.g., 'Apple Health', 'Health Connect', 'Garmin'
    synced_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Add comments for documentation
COMMENT ON TABLE public.device_health_metrics IS 'Stores high-frequency, time-series health data synced from connected devices (Smartwatches, HealthKit, Health Connect).';
COMMENT ON COLUMN public.device_health_metrics.metric_type IS 'Type of metric: steps, heart_rate, sleep_duration, active_calories';
COMMENT ON COLUMN public.device_health_metrics.measured_at IS 'The exact time or start time the metric was recorded by the device.';

-- Create indexes for performance on frequent queries
CREATE INDEX IF NOT EXISTS idx_device_health_metrics_user_id ON public.device_health_metrics(user_id);
CREATE INDEX IF NOT EXISTS idx_device_health_metrics_metric_type ON public.device_health_metrics(metric_type);
CREATE INDEX IF NOT EXISTS idx_device_health_metrics_measured_at ON public.device_health_metrics(measured_at DESC);

-- Composite index for quickly fetching a user's specific metric history
CREATE INDEX IF NOT EXISTS idx_device_health_metrics_user_metric ON public.device_health_metrics(user_id, metric_type, measured_at DESC);

-- Row Level Security (RLS) Policies
ALTER TABLE public.device_health_metrics ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can insert their own metrics"
ON public.device_health_metrics
FOR INSERT
WITH CHECK (true);

CREATE POLICY "Users can view their own metrics"
ON public.device_health_metrics
FOR SELECT
USING (true);

CREATE POLICY "Users can update their own metrics"
ON public.device_health_metrics
FOR UPDATE
USING (true);

CREATE POLICY "Users can delete their own metrics"
ON public.device_health_metrics
FOR DELETE
USING (true);

