-- Phase 1 (map_provider_rollout_plan.md §5): map provider config storage.
--
-- Single-row current config + append-only audit history.
-- Write path is ONLY the backend admin endpoint (routes/map-config.js with
-- requireRole('admin')) — this table must NOT be written from the client
-- directly, unlike public.app_settings which has an open UPDATE/INSERT policy.
--
-- The `config` JSONB holds only non-secret values (provider ids, tile source
-- ids, flags, rate limits). API keys live in server-side secrets, never here.

CREATE TABLE IF NOT EXISTS map_provider_config (
  id          SMALLINT PRIMARY KEY DEFAULT 1 CHECK (id = 1),
  revision    INTEGER NOT NULL DEFAULT 1,
  environment TEXT NOT NULL DEFAULT 'dev'
              CHECK (environment IN ('dev', 'staging', 'prod')),
  config      JSONB NOT NULL,
  reason      TEXT,
  updated_by  TEXT,
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Append-only audit: every save writes one row (old + new config snapshot).
CREATE TABLE IF NOT EXISTS map_provider_config_audit (
  id          BIGSERIAL PRIMARY KEY,
  revision    INTEGER NOT NULL,
  environment TEXT NOT NULL,
  old_config  JSONB,
  new_config  JSONB NOT NULL,
  reason      TEXT,
  actor       TEXT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_map_provider_config_audit_created
  ON map_provider_config_audit (created_at DESC);

-- Default document: everything on Google, nothing overridden.
-- Shape mirrors MapProviderConfig in lib/features/admin/models/.
INSERT INTO map_provider_config (id, revision, environment, config, reason)
VALUES (
  1,
  1,
  'dev',
  '{
    "platformDefaults": {
      "web":     {"enabled": false, "renderer": "google", "tileSourceId": null},
      "ios":     {"enabled": true,  "renderer": "google", "tileSourceId": null},
      "android": {"enabled": true,  "renderer": "google", "tileSourceId": null}
    },
    "featureOverrides": {},
    "services": {
      "routing": {"provider": "google_directions", "enabled": true},
      "search":  {"primary": "nominatim", "fallbackEnabled": true},
      "traffic": {"provider": "google"}
    },
    "fallback": {"enabled": false, "providerId": null},
    "rateConfig": {
      "googleWebMapPerThousand": 7.0,
      "googleDirectionsPerThousand": 5.0,
      "googlePlacesPerThousand": 17.0
    }
  }'::jsonb,
  'Phase 1 seed — matches previous hardcoded defaults'
)
ON CONFLICT (id) DO NOTHING;
