'use strict';

const express = require('express');
const {
  requireAuth,
  strictRateLimiter,
  ipLimiter,
} = require('../middleware');
const { maskVictimName } = require('../utils/victim-name-mask');
const {
  getVictimPermissions,
  getCanTriageBlack,
  canEditVictim,
  serializeVictim,
} = require('../services/victim-permission-service');
const victimBroadcastService = require('../services/victim-broadcast-service');
const { checkHealthDataUnlock } = require('../services/victim-health-link-service');

module.exports = (pool) => {
  const router = express.Router();

  // GET /api/incidents/:incidentId/victims — list victims (masked by permissions)
  router.get('/incidents/:incidentId/victims', ipLimiter, async (req, res) => {
    try {
      const { incidentId } = req.params;
      const userId = req.userId || null;

      const perms = await getVictimPermissions(pool, userId, incidentId);
      const canTriageBlack = await getCanTriageBlack(pool, userId, incidentId);

      const result = await pool.query(
        `SELECT v.*,
                COALESCE(tu.first_name || ' ' || tu.last_name, tu.username, 'ไม่ทราบชื่อ') AS reported_by_name,
                COALESCE(tri.first_name || ' ' || tri.last_name, tri.username, 'ไม่ทราบชื่อ') AS triaged_by_name
           FROM incident_victims v
           LEFT JOIN users tu ON tu.id = v.reported_by
           LEFT JOIN users tri ON tri.id = v.triaged_by
          WHERE v.incident_id = $1 AND v.is_deleted = FALSE
          ORDER BY
            CASE v.triage_level
              WHEN 'deceased' THEN 1
              WHEN 'critical' THEN 2
              WHEN 'urgent' THEN 3
              WHEN 'non_urgent' THEN 4
              WHEN 'white' THEN 5
            END,
            v.created_at ASC`,
        [incidentId]
      );

      const victims = [];
      for (const row of result.rows) {
        const ctx = {
          isResponder: perms.isResponder,
          isAdmin: perms.isAdmin,
          userId,
          canEdit: canEditVictim(row, perms, userId),
          canTriageBlack,
        };
        const serialized = serializeVictim(row, ctx);
        if (serialized) victims.push(serialized);
      }

      const summary = { critical: 0, urgent: 0, non_urgent: 0, white: 0, deceased: 0, total: 0 };
      for (const v of victims) {
        summary[v.triageLevel] = (summary[v.triageLevel] || 0) + 1;
        summary.total++;
      }

      res.json({
        success: true,
        summary,
        viewerPermissions: {
          canTriage: perms.canTriage,
          canDelete: perms.canDelete,
          canViewFull: perms.canViewFull,
          canDispute: perms.canDispute,
          canTriageBlack,
        },
        victims,
      });
    } catch (error) {
      console.error('[Victims] Error listing victims:', error.message);
      res.status(500).json({ error: 'Failed to fetch victims' });
    }
  });

  // POST /api/incidents/:incidentId/victims — add a victim
  router.post('/incidents/:incidentId/victims', requireAuth, strictRateLimiter, async (req, res) => {
    try {
      const { incidentId } = req.params;
      const userId = req.userId;
      const { prefix, firstName, lastName, consent } = req.body;

      if (!prefix) return res.status(400).json({ error: 'prefix is required' });
      if (consent === undefined || consent === null) return res.status(400).json({ error: 'consent is required' });

      const masked = maskVictimName(prefix, firstName);

      const result = await pool.query(
        `SELECT * FROM insert_victim($1, $2, $3, $4, $5, $6, $7)`,
        [incidentId, prefix, firstName || null, lastName || null, masked, userId, consent]
      );

      const victim = result.rows[0];

      victimBroadcastService.broadcastVictimInserted(pool, incidentId, victim);

      res.status(201).json({
        success: true,
        victim: serializeVictim(victim, { isResponder: false, isAdmin: false, userId, canEdit: true }),
      });
    } catch (error) {
      if (error.message === 'VICTIM_REPORT_RATE_LIMIT_EXCEEDED') {
        return res.status(429).json({ error: 'Rate limit exceeded: too many victim reports for this incident' });
      }
      if (error.message && error.message.includes('idx_victims_no_dup')) {
        return res.status(409).json({ error: 'Duplicate victim name in this incident' });
      }
      console.error('[Victims] Error inserting victim:', error.message);
      res.status(500).json({ error: 'Failed to add victim' });
    }
  });

  // PATCH /api/victims/:victimId — edit victim name
  router.patch('/victims/:victimId', requireAuth, async (req, res) => {
    try {
      const { victimId } = req.params;
      const userId = req.userId;
      const { prefix, firstName, lastName } = req.body;

      if (!prefix) return res.status(400).json({ error: 'prefix is required' });

      const victimRes = await pool.query(
        `SELECT * FROM incident_victims WHERE id = $1 AND is_deleted = FALSE`,
        [victimId]
      );
      if (victimRes.rows.length === 0) return res.status(404).json({ error: 'Victim not found' });

      const victim = victimRes.rows[0];
      const perms = await getVictimPermissions(pool, userId, victim.incident_id);

      if (!canEditVictim(victim, perms, userId)) {
        return res.status(403).json({ error: 'Not authorized to edit this victim' });
      }

      const masked = maskVictimName(prefix, firstName);

      const result = await pool.query(
        `SELECT * FROM edit_victim_name($1, $2, $3, $4, $5, $6)`,
        [victimId, userId, prefix, firstName || null, lastName || null, masked]
      );

      const updated = result.rows[0];

      victimBroadcastService.broadcastVictimUpdated(pool, victim.incident_id, updated);

      res.json({
        success: true,
        victim: serializeVictim(updated, { isResponder: perms.isResponder, isAdmin: perms.isAdmin, userId, canEdit: true }),
      });
    } catch (error) {
      console.error('[Victims] Error editing victim:', error.message);
      res.status(500).json({ error: 'Failed to edit victim' });
    }
  });

  // PATCH /api/victims/:victimId/triage — assign/change triage level
  router.patch('/victims/:victimId/triage', requireAuth, strictRateLimiter, async (req, res) => {
    try {
      const { victimId } = req.params;
      const userId = req.userId;
      const { triageLevel, note } = req.body;

      if (!triageLevel) return res.status(400).json({ error: 'triageLevel is required' });

      const victimRes = await pool.query(
        `SELECT * FROM incident_victims WHERE id = $1 AND is_deleted = FALSE`,
        [victimId]
      );
      if (victimRes.rows.length === 0) return res.status(404).json({ error: 'Victim not found' });

      const victim = victimRes.rows[0];
      const perms = await getVictimPermissions(pool, userId, victim.incident_id);

      if (!perms.canTriage) {
        return res.status(403).json({ error: 'Only responders can assign triage levels' });
      }

      if (triageLevel === 'deceased') {
        const canTriageBlack = await getCanTriageBlack(pool, userId, victim.incident_id);
        if (!canTriageBlack) {
          return res.status(403).json({ error: 'Only providers can assign deceased (black) triage level' });
        }
        if (!note || note.length < 10) {
          return res.status(400).json({ error: 'Deceased reason must be at least 10 characters' });
        }
      }

      const result = await pool.query(
        `SELECT * FROM update_victim_triage($1, $2, $3, $4)`,
        [victimId, triageLevel, userId, note || null]
      );

      const updated = result.rows[0];

      victimBroadcastService.broadcastVictimTriageUpdated(pool, victim.incident_id, updated);

      res.json({
        success: true,
        victim: serializeVictim(updated, { isResponder: perms.isResponder, isAdmin: perms.isAdmin, userId, canEdit: true, canTriageBlack: true }),
      });
    } catch (error) {
      if (error.message === 'DECEASED_REQUIRES_PROVIDER_PROFESSION') {
        return res.status(403).json({ error: 'Only providers can assign deceased triage level' });
      }
      if (error.message === 'DECEASED_REASON_TOO_SHORT') {
        return res.status(400).json({ error: 'Deceased reason must be at least 10 characters' });
      }
      if (error.message === 'VICTIM_NOT_FOUND') {
        return res.status(404).json({ error: 'Victim not found' });
      }
      console.error('[Victims] Error updating triage:', error.message);
      res.status(500).json({ error: 'Failed to update triage level' });
    }
  });

  // POST /api/victims/:victimId/dispute — dispute victim name
  router.post('/victims/:victimId/dispute', requireAuth, async (req, res) => {
    try {
      const { victimId } = req.params;
      const userId = req.userId;
      const { reason } = req.body;

      if (!reason || reason.length < 10) {
        return res.status(400).json({ error: 'Dispute reason must be at least 10 characters' });
      }

      const victimRes = await pool.query(
        `SELECT * FROM incident_victims WHERE id = $1 AND is_deleted = FALSE`,
        [victimId]
      );
      if (victimRes.rows.length === 0) return res.status(404).json({ error: 'Victim not found' });

      const victim = victimRes.rows[0];
      const perms = await getVictimPermissions(pool, userId, victim.incident_id);

      if (!perms.canDispute) {
        return res.status(403).json({ error: 'Only responders can dispute victim names' });
      }

      const result = await pool.query(
        `SELECT * FROM dispute_victim($1, $2, $3)`,
        [victimId, userId, reason]
      );

      const updated = result.rows[0];

      victimBroadcastService.broadcastVictimDisputed(pool, victim.incident_id, updated);

      res.json({
        success: true,
        victim: serializeVictim(updated, { isResponder: perms.isResponder, isAdmin: perms.isAdmin, userId, canEdit: true }),
      });
    } catch (error) {
      if (error.message === 'ALREADY_DISPUTED') {
        return res.status(409).json({ error: 'Victim is already disputed' });
      }
      if (error.message === 'DISPUTE_REASON_TOO_SHORT') {
        return res.status(400).json({ error: 'Dispute reason must be at least 10 characters' });
      }
      if (error.message === 'VICTIM_NOT_FOUND') {
        return res.status(404).json({ error: 'Victim not found' });
      }
      console.error('[Victims] Error disputing victim:', error.message);
      res.status(500).json({ error: 'Failed to dispute victim' });
    }
  });

  // DELETE /api/victims/:victimId — soft delete
  router.delete('/victims/:victimId', requireAuth, async (req, res) => {
    try {
      const { victimId } = req.params;
      const userId = req.userId;
      const { reason } = req.body;

      if (!reason || reason.length < 10) {
        return res.status(400).json({ error: 'Delete reason must be at least 10 characters' });
      }

      const victimRes = await pool.query(
        `SELECT * FROM incident_victims WHERE id = $1 AND is_deleted = FALSE`,
        [victimId]
      );
      if (victimRes.rows.length === 0) return res.status(404).json({ error: 'Victim not found' });

      const victim = victimRes.rows[0];
      const perms = await getVictimPermissions(pool, userId, victim.incident_id);

      if (!perms.canDelete) {
        return res.status(403).json({ error: 'Only responders can delete victims' });
      }

      await pool.query(
        `SELECT * FROM soft_delete_victim($1, $2, $3)`,
        [victimId, userId, reason]
      );

      victimBroadcastService.broadcastVictimDeleted(pool, victim.incident_id, victimId);

      res.json({ success: true, message: 'Victim deleted' });
    } catch (error) {
      if (error.message === 'DELETE_REASON_TOO_SHORT') {
        return res.status(400).json({ error: 'Delete reason must be at least 10 characters' });
      }
      if (error.message === 'VICTIM_NOT_FOUND') {
        return res.status(404).json({ error: 'Victim not found' });
      }
      console.error('[Victims] Error deleting victim:', error.message);
      res.status(500).json({ error: 'Failed to delete victim' });
    }
  });

  // GET /api/victims/:victimId/history — triage change history
  router.get('/victims/:victimId/history', requireAuth, async (req, res) => {
    try {
      const { victimId } = req.params;
      const userId = req.userId;

      const victimRes = await pool.query(
        `SELECT incident_id FROM incident_victims WHERE id = $1`,
        [victimId]
      );
      if (victimRes.rows.length === 0) return res.status(404).json({ error: 'Victim not found' });

      const perms = await getVictimPermissions(pool, userId, victimRes.rows[0].incident_id);
      if (!perms.isResponder && !perms.isAdmin) {
        return res.status(403).json({ error: 'Only responders/admins can view history' });
      }

      const result = await pool.query(
        `SELECT l.*, COALESCE(u.first_name || ' ' || u.last_name, u.username, 'ไม่ทราบชื่อ') AS changed_by_name
           FROM incident_victim_triage_logs l
           LEFT JOIN users u ON u.id = l.changed_by
          WHERE l.victim_id = $1
          ORDER BY l.created_at DESC`,
        [victimId]
      );

      res.json({ success: true, history: result.rows });
    } catch (error) {
      console.error('[Victims] Error fetching history:', error.message);
      res.status(500).json({ error: 'Failed to fetch history' });
    }
  });

  // GET /api/incidents/:incidentId/triage-summary — lightweight summary for Map Badge
  router.get('/incidents/:incidentId/triage-summary', ipLimiter, async (req, res) => {
    try {
      const { incidentId } = req.params;
      const userId = req.userId || null;

      const perms = await getVictimPermissions(pool, userId, incidentId);

      const result = await pool.query(
        `SELECT triage_level, COUNT(*) as count
           FROM incident_victims
          WHERE incident_id = $1 AND is_deleted = FALSE
            ${!(perms.isResponder || perms.isAdmin) ? "AND triage_level <> 'deceased'" : ''}
          GROUP BY triage_level`,
        [incidentId]
      );

      const summary = { critical: 0, urgent: 0, non_urgent: 0, white: 0, deceased: 0, total: 0 };
      for (const row of result.rows) {
        summary[row.triage_level] = parseInt(row.count);
        summary.total += parseInt(row.count);
      }

      res.json({ success: true, summary });
    } catch (error) {
      console.error('[Victims] Error fetching triage summary:', error.message);
      res.status(500).json({ error: 'Failed to fetch triage summary' });
    }
  });

  // POST /api/victims/:victimId/health-data/unlock — check and unlock health data
  router.post('/victims/:victimId/health-data/unlock', requireAuth, async (req, res) => {
    try {
      const { victimId } = req.params;
      const userId = req.userId;

      const result = await checkHealthDataUnlock(pool, victimId, userId);

      if (result.unlocked) {
        res.json({ success: true, unlocked: true, sessionId: result.sessionId });
      } else {
        res.status(403).json({ success: false, unlocked: false, reason: result.reason });
      }
    } catch (error) {
      console.error('[Victims] Error unlocking health data:', error.message);
      res.status(500).json({ error: 'Failed to check health data access' });
    }
  });

  return router;
};
