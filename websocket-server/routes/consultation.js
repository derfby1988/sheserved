'use strict';

const express = require('express');
const {
  idempotencyMiddleware,
  strictRateLimiter,
  duplicateCheckMiddleware,
} = require('../middleware');
const { submitConsultationRequest } = require('../services/consultation-queue');

module.exports = () => {
  const router = express.Router();

  router.post(
    '/requests',
    idempotencyMiddleware,
    strictRateLimiter,
    duplicateCheckMiddleware('consultation-submit', 10),
    async (req, res) => {
      try {
        const authHeader = req.headers.authorization || null;
        const trustedUserId = req.userId;
        if (!trustedUserId) {
          return res.status(401).json({ error: 'Authentication required' });
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
