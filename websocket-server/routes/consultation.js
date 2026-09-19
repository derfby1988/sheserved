'use strict';

const express = require('express');
const {
  idempotencyMiddleware,
  strictRateLimiter,
  duplicateCheckMiddleware,
} = require('../middleware');
const { submitConsultationRequest } = require('../services/consultation-queue');
const { mintPostgrestToken } = require('../lib/postgrest-token');

module.exports = () => {
  const router = express.Router();

  router.post(
    '/requests',
    idempotencyMiddleware,
    strictRateLimiter,
    duplicateCheckMiddleware('consultation-submit', 10),
    async (req, res) => {
      try {
        const trustedUserId = req.userId;
        if (!trustedUserId) {
          return res.status(401).json({ error: 'Authentication required' });
        }
        // Phase 13.3 — Decision Q7=C: when identity came from a verified
        // Backend JWT, mint a short-lived PostgREST token (role=authenticated)
        // for the downstream Supabase call instead of forwarding the Backend
        // JWT (PostgREST cannot verify our signing key).  The legacy path
        // keeps forwarding the client's own Supabase token during the
        // compatibility window.
        let authHeader;
        if (req.identitySource === 'jwt') {
          authHeader = `Bearer ${mintPostgrestToken({ userId: trustedUserId })}`;
        } else {
          authHeader = req.headers.authorization || null;
        }
        const result = await submitConsultationRequest(req.body, authHeader, trustedUserId);

        return res.status(202).json({
          queued: true,
          jobId: result.jobId,
          roomId: result.roomId,
          consultationRequest: result.consultationRequest,
        });
      } catch (error) {
        console.error('Consultation submit error:', error);
        return res.status(500).json({
          error: 'Failed to submit consultation request',
          detail: error.message,
        });
      }
    },
  );

  return router;
};
