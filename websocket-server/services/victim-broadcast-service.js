'use strict';

const socketService = require('./socket-service');

function broadcastVictimInserted(pool, incidentId, victim) {
  const io = socketService.getIO();
  if (!io) return;
  io.to(`video-${incidentId}`).emit('victim-inserted', {
    incidentId,
    victimId: victim.id,
    maskedName: victim.masked_name,
    triageLevel: victim.triage_level,
    verifyStatus: victim.verify_status,
  });
}

function broadcastVictimTriageUpdated(pool, incidentId, victim) {
  const io = socketService.getIO();
  if (!io) return;
  io.to(`video-${incidentId}`).emit('victim-triage-updated', {
    incidentId,
    victimId: victim.id,
    triageLevel: victim.triage_level,
    triagedAt: victim.triaged_at,
    triagedBy: victim.triaged_by,
    verifyStatus: victim.verify_status,
  });
}

function broadcastVictimUpdated(pool, incidentId, victim) {
  const io = socketService.getIO();
  if (!io) return;
  io.to(`video-${incidentId}`).emit('victim-name-updated', {
    incidentId,
    victimId: victim.id,
    maskedName: victim.masked_name,
    verifyStatus: victim.verify_status,
  });
}

function broadcastVictimDisputed(pool, incidentId, victim) {
  const io = socketService.getIO();
  if (!io) return;
  io.to(`video-${incidentId}`).emit('victim-disputed', {
    incidentId,
    victimId: victim.id,
    verifyStatus: victim.verify_status,
  });
}

function broadcastVictimDeleted(pool, incidentId, victimId) {
  const io = socketService.getIO();
  if (!io) return;
  io.to(`video-${incidentId}`).emit('victim-deleted', {
    incidentId,
    victimId,
  });
}

module.exports = {
  broadcastVictimInserted,
  broadcastVictimTriageUpdated,
  broadcastVictimUpdated,
  broadcastVictimDisputed,
  broadcastVictimDeleted,
};
