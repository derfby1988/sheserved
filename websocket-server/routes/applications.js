'use strict';

/**
 * Routes: /api/applications* (registration applications)
 * Extracted from server.js (Phase 13.3 P1-3 route refactor).
 * Mounted at /api/applications.
 */

const express = require('express');
const {
  cacheAside,
  TTL,
  strictRateLimiter,
  idempotencyMiddleware,
  duplicateCheckMiddleware,
} = require('../middleware');
const {
  assertActorMatches,
  requireRole,
  whenStrictRoute,
} = require('../middleware/auth');

/**
 * @param {{pool: object|null, verifyTokenMw: Function}} deps
 */
function applicationsRoutes({ pool, verifyTokenMw }) {
  const router = express.Router();

  // Submit registration application
  router.post('/', verifyTokenMw, idempotencyMiddleware, strictRateLimiter, duplicateCheckMiddleware('application-submit', 10), async (req, res) => {
    try {
      if (!pool) {
        return res.status(503).json({ error: 'Database not available' });
      }

      const {
        professionId, firstName, lastName, username,
        phone, profileImageUrl, registrationData
      } = req.body;

      // Phase 13.3 — bound identity wins; body userId = compat field
      const userId = req.userId || req.body?.userId;
      if (!userId) {
        return res.status(401).json({ error: 'Login required' });
      }

      const result = await pool.query(
        `INSERT INTO registration_applications 
         (user_id, profession_id, first_name, last_name, username, phone, 
          profile_image_url, registration_data, status)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, 'pending')
         RETURNING *`,
        [userId, professionId, firstName, lastName, username, phone,
          profileImageUrl, JSON.stringify(registrationData || {})]
      );

      res.status(201).json(result.rows[0]);
    } catch (error) {
      console.error('Error creating application:', error);
      res.status(500).json({ error: 'Failed to create application' });
    }
  });

  // Get applications (with optional status filter)
  router.get('/', async (req, res) => {
    try {
      if (!pool) {
        return res.status(503).json({ error: 'Database not available' });
      }

      const { status } = req.query;
      const cacheKey = `applications:list:${status || 'all'}`;

      const data = await cacheAside(cacheKey, async () => {
        let query = `
          SELECT a.*, p.name as profession_name, p.category as profession_category
          FROM registration_applications a
          LEFT JOIN professions p ON a.profession_id = p.id
        `;
        const params = [];

        if (status) {
          query += ' WHERE a.status = $1';
          params.push(status);
        }

        query += ' ORDER BY a.created_at DESC';

        const result = await pool.query(query, params);
        return result.rows;
      }, TTL.DEFAULT);

      res.json(data);
    } catch (error) {
      console.error('Error fetching applications:', error);
      res.status(500).json({ error: 'Failed to fetch applications' });
    }
  });

  // Get application by ID
  router.get('/:id', async (req, res) => {
    try {
      if (!pool) {
        return res.status(503).json({ error: 'Database not available' });
      }

      const { id } = req.params;
      const data = await cacheAside(`application:${id}`, async () => {
        const result = await pool.query(
          `SELECT a.*, p.name as profession_name
           FROM registration_applications a
           LEFT JOIN professions p ON a.profession_id = p.id
           WHERE a.id = $1`,
          [id]
        );
        return result.rows[0] || null;
      }, TTL.DEFAULT);

      if (data === null) {
        return res.status(404).json({ error: 'Application not found' });
      }

      res.json(data);
    } catch (error) {
      console.error('Error fetching application:', error);
      res.status(500).json({ error: 'Failed to fetch application' });
    }
  });

  // Approve application
  router.post('/:id/approve', verifyTokenMw, whenStrictRoute(requireRole('admin')), strictRateLimiter, duplicateCheckMiddleware('application-approve', 10), async (req, res) => {
    try {
      if (!pool) {
        return res.status(503).json({ error: 'Database not available' });
      }

      const { id } = req.params;
      const { note } = req.body;
      // Phase 13.3 — reviewedBy = bound identity; body field = compat
      const reviewedBy = req.userId || req.body?.reviewedBy;

      // Update application status
      const result = await pool.query(
        `UPDATE registration_applications 
         SET status = 'approved', review_note = $1, reviewed_by = $2, reviewed_at = NOW()
         WHERE id = $3 AND status = 'pending'
         RETURNING *`,
        [note, reviewedBy, id]
      );

      if (result.rows.length === 0) {
        return res.status(404).json({ error: 'Application not found or already processed' });
      }

      // Update user profession and verification status
      await pool.query(
        `UPDATE users 
         SET profession_id = $1, 
             verification_status = 'verified',
             updated_at = NOW()
         WHERE id = $2`,
        [result.rows[0].profession_id, result.rows[0].user_id]
      );

      res.json({ message: 'Application approved', application: result.rows[0] });
    } catch (error) {
      console.error('Error approving application:', error);
      res.status(500).json({ error: 'Failed to approve application' });
    }
  });

  // Reject application
  router.post('/:id/reject', verifyTokenMw, whenStrictRoute(requireRole('admin')), strictRateLimiter, duplicateCheckMiddleware('application-reject', 10), async (req, res) => {
    try {
      if (!pool) {
        return res.status(503).json({ error: 'Database not available' });
      }

      const { id } = req.params;
      const { note } = req.body;
      const reviewedBy = req.userId || req.body?.reviewedBy;

      if (!note) {
        return res.status(400).json({ error: 'Rejection note is required' });
      }

      const result = await pool.query(
        `UPDATE registration_applications 
         SET status = 'rejected', review_note = $1, reviewed_by = $2, reviewed_at = NOW()
         WHERE id = $3 AND status = 'pending'
         RETURNING *`,
        [note, reviewedBy, id]
      );

      if (result.rows.length === 0) {
        return res.status(404).json({ error: 'Application not found or already processed' });
      }

      // Reset user profession to consumer and update verification status
      await pool.query(
        `UPDATE users 
         SET profession_id = '00000000-0000-0000-0000-000000000001',
             verification_status = 'rejected',
             updated_at = NOW()
         WHERE id = $1`,
        [result.rows[0].user_id]
      );

      res.json({ message: 'Application rejected', application: result.rows[0] });
    } catch (error) {
      console.error('Error rejecting application:', error);
      res.status(500).json({ error: 'Failed to reject application' });
    }
  });

  return router;
}

module.exports = { applicationsRoutes };
