-- Seed default video_system_config in app_settings
-- Required before deploying victim DB functions that read this config

INSERT INTO app_settings (key, value, description)
VALUES (
    'video_system_config',
    '{"victimRetentionDays": 0, "victimReportRateLimitPerIncident": 0, "incidentRetentionMaxWaitHours": 72}'::jsonb,
    'Configuration for Triage System: victimRetentionDays (0=disabled), victimReportRateLimitPerIncident (0=disabled), incidentRetentionMaxWaitHours (default 72)'
)
ON CONFLICT (key) DO UPDATE
SET value = app_settings.value || EXCLUDED.value,
    description = EXCLUDED.description;
