'use strict';

/**
 * Routes: /api/emergency-health/*
 * Extracted from server.js (Phase 13.3 P1-3 route refactor).
 * Mounted at /api/emergency-health.
 *
 * Identity contract (Phase 13.3): bound identity (req.userId from
 * verifyToken) wins over body/query identity fields; when the route is
 * in STRICT_AUTH_ROUTES, actor-mismatch is rejected (403) and legacy
 * identity is denied (401).
 */

const express = require('express');
const emergencyHealthSessionService = require('../services/emergency-health-session-service');
const {
  cacheAside,
  TTL,
  strictRateLimiter,
  duplicateCheckMiddleware,
} = require('../middleware');
const {
  assertActorMatches,
  whenStrictRoute,
} = require('../middleware/auth');

/**
 * @param {{verifyTokenMw: Function}} deps — verifyToken(pool) middleware
 */
function emergencyHealthRoutes({ verifyTokenMw }) {
  const router = express.Router();

  router.post('/sessions', strictRateLimiter, duplicateCheckMiddleware('emergency-health-session', 10), async (req, res) => {
    try {
      const { patientId, incidentId, videoId } = req.body || {};
      const result = await emergencyHealthSessionService.createReleaseSession({
        patientId,
        incidentId,
        videoId,
      });

      if (!result.created) {
        return res.status(200).json(result);
      }

      return res.status(201).json(result);
    } catch (error) {
      console.error('[EmergencyHealth] create session error:', error.message);
      return res.status(500).json({ error: error.message });
    }
  });

  router.get('/:incidentId', verifyTokenMw, whenStrictRoute(assertActorMatches((req) => req.query.responderId)), async (req, res) => {
    try {
      const { incidentId } = req.params;
      // Phase 13.3 — bound identity wins; query field = compat
      const responderId = req.userId || req.query.responderId;

      if (!responderId) {
        return res.status(400).json({ error: 'responderId is required' });
      }

      const data = await cacheAside(`emergency-health:${incidentId}:${responderId}`, async () => {
        const result = await emergencyHealthSessionService.getIncidentHealthData({
          incidentId,
          responderId,
        });
        return result;
      }, TTL.SESSION);

      if (!data.allowed) {
        return res.status(403).json(data);
      }

      return res.status(200).json(data);
    } catch (error) {
      console.error('[EmergencyHealth] get health data error:', error.message);
      return res.status(500).json({ error: error.message });
    }
  });

  router.post('/revoke', strictRateLimiter, duplicateCheckMiddleware('emergency-health-revoke', 10), async (req, res) => {
    try {
      const { patientId } = req.body || {};

      if (!patientId) {
        return res.status(400).json({ error: 'patientId is required' });
      }

      const result = await emergencyHealthSessionService.revokeActiveSessions({
        patientId,
      });

      return res.status(200).json(result);
    } catch (error) {
      console.error('[EmergencyHealth] revoke sessions error:', error.message);
      return res.status(500).json({ error: error.message });
    }
  });

  router.get('/settings/:userId', verifyTokenMw, whenStrictRoute(assertActorMatches((req) => req.params.userId)), async (req, res) => {
    try {
      const { userId } = req.params;
      const data = await cacheAside(`emergency-health:settings:${userId}`, async () => {
        const settings = await emergencyHealthSessionService.getEmergencyHealthSettings({ userId });
        return { settings };
      }, TTL.SESSION);
      return res.status(200).json(data);
    } catch (error) {
      console.error('[EmergencyHealth] get settings error:', error.message);
      return res.status(500).json({ error: error.message });
    }
  });

  router.post('/settings', verifyTokenMw, whenStrictRoute(assertActorMatches((req) => req.body && req.body.userId)), strictRateLimiter, duplicateCheckMiddleware('emergency-health-settings', 10), async (req, res) => {
    try {
      const { settings } = req.body || {};
      // Phase 13.3 — bound identity (req.userId) wins; body id = compat field
      const userId = req.userId || req.body?.userId;
      if (!userId) {
        return res.status(400).json({ error: 'userId is required' });
      }

      const saved = await emergencyHealthSessionService.upsertEmergencyHealthSettings({
        userId,
        settings,
      });

      return res.status(200).json({ settings: saved });
    } catch (error) {
      console.error('[EmergencyHealth] save settings error:', error.message);
      return res.status(500).json({ error: error.message });
    }
  });

  router.get('/dead-man/:userId', verifyTokenMw, whenStrictRoute(assertActorMatches((req) => req.params.userId)), async (req, res) => {
    try {
      const { userId } = req.params;
      const data = await cacheAside(`emergency-health:dead-man:${userId}`, async () => {
        const checkin = await emergencyHealthSessionService.getDeadManCheckin({ userId });
        return { checkin };
      }, TTL.SESSION);
      return res.status(200).json(data);
    } catch (error) {
      console.error('[EmergencyHealth] get dead-man check-in error:', error.message);
      return res.status(500).json({ error: error.message });
    }
  });

  router.post('/dead-man', verifyTokenMw, whenStrictRoute(assertActorMatches((req) => req.body && req.body.userId)), strictRateLimiter, duplicateCheckMiddleware('emergency-health-deadman', 10), async (req, res) => {
    try {
      const { checkin } = req.body || {};
      const userId = req.userId || req.body?.userId;
      if (!userId) {
        return res.status(400).json({ error: 'userId is required' });
      }

      const saved = await emergencyHealthSessionService.upsertDeadManCheckin({
        userId,
        checkin,
      });

      return res.status(200).json({ checkin: saved });
    } catch (error) {
      console.error('[EmergencyHealth] save dead-man check-in error:', error.message);
      return res.status(500).json({ error: error.message });
    }
  });

  router.post('/dead-man/check-in', verifyTokenMw, whenStrictRoute(assertActorMatches((req) => req.body && req.body.userId)), strictRateLimiter, duplicateCheckMiddleware('emergency-health-checkin', 5), async (req, res) => {
    try {
      const { checkInAt } = req.body || {};
      const userId = req.userId || req.body?.userId;
      if (!userId) {
        return res.status(400).json({ error: 'userId is required' });
      }

      const saved = await emergencyHealthSessionService.updateDeadManCheckInTimestamp({
        userId,
        checkInAt: checkInAt ? new Date(checkInAt) : undefined,
      });

      return res.status(200).json({ checkin: saved });
    } catch (error) {
      console.error('[EmergencyHealth] dead-man check-in error:', error.message);
      return res.status(500).json({ error: error.message });
    }
  });

  return router;
}

module.exports = { emergencyHealthRoutes };
