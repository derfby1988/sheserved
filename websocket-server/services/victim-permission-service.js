'use strict';

async function getVictimPermissions(pool, userId, incidentId) {
  if (!userId) return { canViewFull: false, isResponder: false, isAdmin: false, canTriage: false, canDelete: false, canDispute: false, canViewNote: false };

  const [responderRes, adminRes] = await Promise.all([
    pool.query(
      `SELECT 1 FROM incident_responses
        WHERE video_id = $1 AND volunteer_id = $2
          AND status IN ('accepted','en_route','arrived') LIMIT 1`,
      [incidentId, userId]
    ),
    pool.query(
      `SELECT 1 FROM users
        WHERE id = $1 AND user_category_id = 'admin' AND is_active = TRUE LIMIT 1`,
      [userId]
    ),
  ]);

  const isResponder = responderRes.rowCount > 0;
  const isAdmin = adminRes.rowCount > 0;
  return {
    isResponder,
    isAdmin,
    canViewFull:  isResponder || isAdmin,
    canTriage:    isResponder || isAdmin,
    canDelete:    isResponder || isAdmin,
    canDispute:   isResponder || isAdmin,
    canViewNote:  isResponder || isAdmin,
  };
}

async function getCanTriageBlack(pool, userId, incidentId) {
  if (!userId) return false;
  const result = await pool.query(
    `SELECT p.category
       FROM users u
       LEFT JOIN professions p ON p.id = u.profession_id
      WHERE u.id = $1`,
    [userId]
  );
  if (result.rows.length === 0) return false;
  return result.rows[0].category === 'provider';
}

function canEditVictim(victim, perms, userId) {
  if (victim.is_deleted) return false;
  if (perms.isResponder || perms.isAdmin) return true;
  if (victim.reported_by !== userId) return false;
  return victim.triaged_at === null;
}

function serializeVictim(row, ctx) {
  const canSeeFull = ctx.isResponder || ctx.isAdmin || row.reported_by === ctx.userId;

  const hideBlack = row.triage_level === 'deceased' && !(ctx.isResponder || ctx.isAdmin);
  if (hideBlack) return null;

  return {
    id: row.id,
    prefix: row.prefix,
    firstName: canSeeFull ? row.first_name : null,
    lastName:  canSeeFull ? row.last_name  : null,
    displayName: canSeeFull
      ? `${row.prefix} ${row.first_name || ''} ${row.last_name || ''}`.trim()
      : row.masked_name,
    isMasked: !canSeeFull,
    triageLevel: row.triage_level,
    triagedAt: row.triaged_at,
    triagedByName: row.triaged_by_name || null,
    triageNote: (ctx.isResponder || ctx.isAdmin) ? row.triage_note : null,
    verifyStatus: row.verify_status,
    canEdit: ctx.canEdit !== undefined ? ctx.canEdit : false,
    hasHealthData: row.health_data_consent_verified || false,
    healthDataSessionId: row.health_data_session_id || null,
    disputedBy: row.disputed_by || null,
    disputedReason: (ctx.isResponder || ctx.isAdmin) ? row.disputed_reason : null,
    disputedAt: row.disputed_at || null,
    reportedByName: row.reported_by_name || null,
    createdAt: row.created_at,
  };
}

module.exports = { getVictimPermissions, getCanTriageBlack, canEditVictim, serializeVictim };
