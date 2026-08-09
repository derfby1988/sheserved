'use strict';

async function checkHealthDataUnlock(pool, victimId, requesterId) {
  if (!pool || !victimId || !requesterId) return { unlocked: false, reason: 'MISSING_PARAMS' };

  const victimRes = await pool.query(
    `SELECT v.id, v.incident_id, v.triage_level, v.health_data_consent_verified,
            v.linked_user_id, v.is_deleted
       FROM incident_victims v
      WHERE v.id = $1 AND v.is_deleted = FALSE`,
    [victimId]
  );

  if (victimRes.rows.length === 0) return { unlocked: false, reason: 'VICTIM_NOT_FOUND' };
  const victim = victimRes.rows[0];

  if (victim.triage_level === 'deceased') {
    return { unlocked: false, reason: 'DECEASED_NO_HEALTH_ACCESS' };
  }

  if (victim.health_data_consent_verified) {
    await pool.query(
      `INSERT INTO victim_health_access_logs (victim_id, accessed_by, session_id)
       VALUES ($1, $2, NULL)`,
      [victimId, requesterId]
    );
    return { unlocked: true, reason: 'ALREADY_UNLOCKED' };
  }

  const responderRes = await pool.query(
    `SELECT 1 FROM incident_responses
      WHERE video_id = $1 AND volunteer_id = $2
        AND status IN ('accepted','en_route','arrived')`,
    [victim.incident_id, requesterId]
  );
  if (responderRes.rowCount === 0) {
    return { unlocked: false, reason: 'NOT_RESPONDER' };
  }

  if (!victim.linked_user_id) {
    return { unlocked: false, reason: 'NO_LINKED_USER' };
  }

  const sessionRes = await pool.query(
    `SELECT s.id, s.status, s.released_at
       FROM emergency_health_release_sessions s
      WHERE s.patient_id = $1 AND s.incident_id = $2
        AND s.status = 'released'
      ORDER BY s.released_at DESC LIMIT 1`,
    [victim.linked_user_id, victim.incident_id]
  );

  if (sessionRes.rows.length === 0) {
    return { unlocked: false, reason: 'NO_RELEASED_SESSION' };
  }

  await pool.query(
    `UPDATE incident_victims
        SET health_data_consent_verified = TRUE,
            health_data_unlocked_at = NOW(),
            is_synced = FALSE,
            updated_at = NOW()
      WHERE id = $1`,
    [victimId]
  );

  await pool.query(
    `INSERT INTO victim_health_access_logs (victim_id, accessed_by, session_id)
     VALUES ($1, $2, $3)`,
    [victimId, requesterId, sessionRes.rows[0].id]
  );

  return { unlocked: true, reason: 'UNLOCKED', sessionId: sessionRes.rows[0].id };
}

module.exports = { checkHealthDataUnlock };
