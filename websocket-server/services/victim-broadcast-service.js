'use strict';

const socketService = require('./socket-service');

async function _getSummary(pool, incidentId) {
  const result = await pool.query(
    `SELECT triage_level, COUNT(*) as count
       FROM incident_victims
      WHERE incident_id = $1 AND is_deleted = FALSE
      GROUP BY triage_level`,
    [incidentId]
  );
  const summary = { critical: 0, urgent: 0, non_urgent: 0, white: 0, deceased: 0, total: 0 };
  for (const row of result.rows) {
    summary[row.triage_level] = parseInt(row.count);
    summary.total += parseInt(row.count);
  }
  return summary;
}

async function broadcastVictimInserted(pool, incidentId, victim) {
  const io = socketService.getIO();
  if (!io) return;
  const summary = await _getSummary(pool, incidentId);
  io.to(`video-${incidentId}`).emit('victim-inserted', {
    incidentId,
    victimId: victim.id,
    maskedName: victim.masked_name,
    triageLevel: victim.triage_level,
    verifyStatus: victim.verify_status,
    summary,
  });
}

async function broadcastVictimTriageUpdated(pool, incidentId, victim) {
  const io = socketService.getIO();
  if (!io) return;
  const summary = await _getSummary(pool, incidentId);
  io.to(`video-${incidentId}`).emit('victim-triage-updated', {
    incidentId,
    victimId: victim.id,
    triageLevel: victim.triage_level,
    triagedAt: victim.triaged_at,
    triagedBy: victim.triaged_by,
    verifyStatus: victim.verify_status,
    summary,
  });
}

async function broadcastVictimUpdated(pool, incidentId, victim) {
  const io = socketService.getIO();
  if (!io) return;
  io.to(`video-${incidentId}`).emit('victim-name-updated', {
    incidentId,
    victimId: victim.id,
    maskedName: victim.masked_name,
    verifyStatus: victim.verify_status,
  });
}

async function broadcastVictimDisputed(pool, incidentId, victim) {
  const io = socketService.getIO();
  if (!io) return;
  io.to(`video-${incidentId}`).emit('victim-disputed', {
    incidentId,
    victimId: victim.id,
    verifyStatus: victim.verify_status,
  });
}

async function broadcastVictimDeleted(pool, incidentId, victimId) {
  const io = socketService.getIO();
  if (!io) return;
  const summary = await _getSummary(pool, incidentId);
  io.to(`video-${incidentId}`).emit('victim-deleted', {
    incidentId,
    victimId,
    summary,
  });
}

async function broadcastVictimHealthUnlocked(pool, incidentId, victimId, sessionId, responderSocketId) {
  const io = socketService.getIO();
  if (!io) return;
  io.to(responderSocketId).emit('victim-health-unlocked', {
    incidentId,
    victimId,
    sessionId,
  });
}

module.exports = {
  broadcastVictimInserted,
  broadcastVictimTriageUpdated,
  broadcastVictimUpdated,
  broadcastVictimDisputed,
  broadcastVictimDeleted,
  broadcastVictimHealthUnlocked,
};
