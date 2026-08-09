'use strict';

const INTERVAL_MS = 24 * 60 * 60 * 1000; // 24 hours
let timer = null;

function start(pool) {
  if (!pool) {
    console.warn('[VictimRetentionAnonymizer] Pool not available, skipping start');
    return;
  }

  const tick = async () => {
    try {
      await runAnonymize(pool);
    } catch (err) {
      console.error('[VictimRetentionAnonymizer] Error:', err.message);
    }
  };

  tick();
  timer = setInterval(tick, INTERVAL_MS);
  console.log('✅ Victim Retention Anonymizer started (24h interval)');
}

function stop() {
  if (timer) {
    clearInterval(timer);
    timer = null;
    console.log('🛑 Victim Retention Anonymizer stopped');
  }
}

async function runAnonymize(pool) {
  const configRes = await pool.query(
    `SELECT value->>'victimRetentionDays' AS retention_days
     FROM app_settings WHERE key = 'video_system_config'`
  );
  const retentionDays = configRes.rows[0] ? parseInt(configRes.rows[0].retention_days) : 0;
  if (retentionDays <= 0) return;

  // Null-out PII fields for records past retention period
  // Exclude deceased and disputed records (legal/audit hold)
  const result = await pool.query(
    `UPDATE incident_victims
        SET first_name      = NULL,
            last_name       = NULL,
            disputed_reason = NULL,
            deleted_reason  = NULL,
            is_synced       = FALSE,
            updated_at      = NOW()
      WHERE is_deleted = FALSE
        AND retention_countdown_started_at IS NOT NULL
        AND retention_countdown_started_at < NOW() - ($1 || ' days')::INTERVAL
        AND triage_level <> 'deceased'
        AND verify_status <> 'disputed'
        AND (first_name IS NOT NULL OR last_name IS NOT NULL
             OR disputed_reason IS NOT NULL OR deleted_reason IS NOT NULL)`,
    [String(retentionDays)]
  );

  if (result.rowCount > 0) {
    console.log(`[VictimRetentionAnonymizer] Anonymized ${result.rowCount} victim records past retention period`);
  }
}

module.exports = { start, stop, runAnonymize };
