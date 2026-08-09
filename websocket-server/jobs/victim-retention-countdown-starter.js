'use strict';

const INTERVAL_MS = 60 * 60 * 1000; // 1 hour
let timer = null;

function start(pool) {
  if (!pool) {
    console.warn('[VictimRetentionCountdown] Pool not available, skipping start');
    return;
  }

  const tick = async () => {
    try {
      await pool.query('SELECT NOW()');
      await runRetentionCountdown(pool);
    } catch (err) {
      console.error('[VictimRetentionCountdown] Error:', err.message);
    }
  };

  tick();
  timer = setInterval(tick, INTERVAL_MS);
  console.log('✅ Victim Retention Countdown Starter started (1h interval)');
}

function stop() {
  if (timer) {
    clearInterval(timer);
    timer = null;
    console.log('🛑 Victim Retention Countdown Starter stopped');
  }
}

async function runRetentionCountdown(pool) {
  const configRes = await pool.query(
    `SELECT value->>'victimRetentionDays' AS retention_days,
            value->>'incidentRetentionMaxWaitHours' AS max_wait_hours
     FROM app_settings WHERE key = 'video_system_config'`
  );
  const retentionDays = configRes.rows[0] ? parseInt(configRes.rows[0].retention_days) : 0;
  if (retentionDays <= 0) return;

  const maxWaitHours = configRes.rows[0] ? parseInt(configRes.rows[0].max_wait_hours) : 72;

  // Tier 1: Incidents with all required profession responders present → start countdown
  await pool.query(
    `UPDATE incident_victims v
        SET retention_countdown_started_at = NOW()
      WHERE v.retention_countdown_started_at IS NULL
        AND v.is_deleted = FALSE
        AND EXISTS (
          SELECT 1 FROM videos vid
          WHERE vid.id = v.incident_id
            AND vid.created_at < NOW() - ($1 || ' hours')::INTERVAL
        )
        AND NOT EXISTS (
          SELECT 1 FROM incident_responses ir
          JOIN users u ON u.id = ir.volunteer_id
          LEFT JOIN professions p ON p.id = u.profession_id
          WHERE ir.video_id = v.incident_id
            AND ir.status IN ('accepted','en_route','arrived')
            AND p.category = 'provider'
        )
        AND NOT EXISTS (
          SELECT 1 FROM incident_responses ir
          JOIN users u ON u.id = ir.volunteer_id
          LEFT JOIN professions p ON p.id = u.profession_id
          WHERE ir.video_id = v.incident_id
            AND ir.status IN ('accepted','en_route','arrived')
            AND p.category = 'consumer'
        )`,
    [String(maxWaitHours)]
  );

  // Tier 2: Incidents older than max_wait_hours with at least some responders → start countdown
  await pool.query(
    `UPDATE incident_victims v
        SET retention_countdown_started_at = NOW()
      WHERE v.retention_countdown_started_at IS NULL
        AND v.is_deleted = FALSE
        AND EXISTS (
          SELECT 1 FROM videos vid
          WHERE vid.id = v.incident_id
            AND vid.created_at < NOW() - ($1 || ' hours')::INTERVAL
        )
        AND EXISTS (
          SELECT 1 FROM incident_responses ir
          WHERE ir.video_id = v.incident_id
            AND ir.status IN ('accepted','en_route','arrived')
        )`,
    [String(maxWaitHours)]
  );

  // Tier 3: Incidents older than max_wait_hours with no responders at all → start countdown
  await pool.query(
    `UPDATE incident_victims v
        SET retention_countdown_started_at = NOW()
      WHERE v.retention_countdown_started_at IS NULL
        AND v.is_deleted = FALSE
        AND EXISTS (
          SELECT 1 FROM videos vid
          WHERE vid.id = v.incident_id
            AND vid.created_at < NOW() - ($1 || ' hours')::INTERVAL
        )
        AND NOT EXISTS (
          SELECT 1 FROM incident_responses ir
          WHERE ir.video_id = v.incident_id
            AND ir.status IN ('accepted','en_route','arrived')
        )`,
    [String(maxWaitHours)]
  );
}

module.exports = { start, stop, runRetentionCountdown };
