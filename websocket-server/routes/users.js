'use strict';

/**
 * Routes: /api/users* + /api/users/:userId/preferences + /api/users/sync
 * Extracted from server.js (Phase 13.3 P1-3 route refactor).
 * Mounted at /api/users.
 */

const express = require('express');
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
 * @param {{pool: object|null, verifyTokenMw: Function}} deps
 */
function usersRoutes({ pool, verifyTokenMw }) {
  const router = express.Router();

  // UI Preferences API
  router.get('/:userId/preferences/:key', verifyTokenMw, whenStrictRoute(assertActorMatches((req) => req.params.userId)), async (req, res) => {
    const { userId, key } = req.params;
    try {
      if (!pool) return res.status(503).json({ error: 'Database not available' });
      const result = await pool.query(
        'SELECT preference_value FROM user_ui_preferences WHERE user_id = $1 AND preference_key = $2',
        [userId, key]
      );
      if (result.rows.length === 0) return res.json({ value: null });
      res.json({ value: result.rows[0].preference_value });
    } catch (error) {
      res.status(500).json({ error: error.message });
    }
  });

  router.post('/:userId/preferences', verifyTokenMw, whenStrictRoute(assertActorMatches((req) => req.params.userId)), async (req, res) => {
    const { userId } = req.params;
    const { key, value } = req.body;
    try {
      if (!pool) return res.status(503).json({ error: 'Database not available' });
      await pool.query(
        `INSERT INTO user_ui_preferences (user_id, preference_key, preference_value, updated_at)
         VALUES ($1, $2, $3, NOW())
         ON CONFLICT (user_id, preference_key) DO UPDATE SET preference_value = $3, updated_at = NOW()`,
        [userId, key, value]
      );
      res.json({ success: true });
    } catch (error) {
      res.status(500).json({ error: error.message });
    }
  });

  // Sync users from Supabase (non-sensitive data only)
  router.post('/sync', async (req, res) => {
    try {
      if (!pool) {
        return res.status(503).json({ error: 'Database not available' });
      }

      const { data } = req.body;
      if (!Array.isArray(data)) {
        return res.status(400).json({ error: 'Data must be an array' });
      }

      let synced = 0;
      for (const item of data) {
        await pool.query(
          `INSERT INTO users (id, profession_id, first_name, last_name, username, 
                             verification_status, is_active, created_at, updated_at)
           VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
           ON CONFLICT (id) DO UPDATE SET
             profession_id = EXCLUDED.profession_id,
             first_name = EXCLUDED.first_name,
             last_name = EXCLUDED.last_name,
             verification_status = EXCLUDED.verification_status,
             is_active = EXCLUDED.is_active,
             updated_at = EXCLUDED.updated_at`,
          [
            item.id, item.profession_id, item.first_name, item.last_name,
            item.username, item.verification_status, item.is_active,
            item.created_at, item.updated_at
          ]
        );
        synced++;
      }

      console.log(`✅ Synced ${synced} users`);
      res.json({ message: `Synced ${synced} users` });
    } catch (error) {
      console.error('Error syncing users:', error);
      res.status(500).json({ error: 'Failed to sync users' });
    }
  });

  // Create user
  router.post('/', strictRateLimiter, duplicateCheckMiddleware('user-create', 10), async (req, res) => {
    try {
      if (!pool) {
        return res.status(503).json({ error: 'Database not available' });
      }

      const {
        professionId, firstName, lastName, username, email,
        phone, passwordHash, socialProvider, socialId
      } = req.body;

      const result = await pool.query(
        `INSERT INTO users (profession_id, first_name, last_name, username, email, 
                            phone, password_hash, social_provider, social_id)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
         RETURNING id, profession_id, first_name, last_name, username, email,
                   phone, profile_image_url, social_provider, social_id,
                   is_active, is_verified, created_at, updated_at`,
        [professionId, firstName, lastName, username, email,
          phone, passwordHash, socialProvider, socialId]
      );

      res.status(201).json(result.rows[0]);
    } catch (error) {
      console.error('Error creating user:', error);
      if (error.code === '23505') { // Unique violation
        res.status(409).json({ error: 'Username already exists' });
      } else {
        res.status(500).json({ error: 'Failed to create user' });
      }
    }
  });

  // Get user by ID
  router.get('/:id', async (req, res) => {
    try {
      if (!pool) {
        return res.status(503).json({ error: 'Database not available' });
      }

      const { id } = req.params;
      const data = await cacheAside(`user:${id}`, async () => {
        const result = await pool.query(
          `SELECT id, profession_id, first_name, last_name, username, email, 
                  phone, profile_image_url, is_active, is_verified, created_at, updated_at
           FROM users 
           WHERE id = $1`,
          [id]
        );
        return result.rows[0] || null;
      }, TTL.DEFAULT);

      if (data === null) {
        return res.status(404).json({ error: 'User not found' });
      }

      res.json(data);
    } catch (error) {
      console.error('Error fetching user:', error);
      res.status(500).json({ error: 'Failed to fetch user' });
    }
  });

  // Update user
  router.put('/:id', verifyTokenMw, whenStrictRoute(assertActorMatches((req) => req.params.id)), strictRateLimiter, duplicateCheckMiddleware('user-update', 10), async (req, res) => {
    try {
      if (!pool) {
        return res.status(503).json({ error: 'Database not available' });
      }

      const { id } = req.params;
      const updates = req.body;

      // Build dynamic update query
      const fields = [];
      const values = [];
      let paramIndex = 1;

      const allowedFields = ['first_name', 'last_name', 'email', 'phone', 'profile_image_url'];
      for (const [key, value] of Object.entries(updates)) {
        const snakeKey = key.replace(/([A-Z])/g, '_$1').toLowerCase();
        if (allowedFields.includes(snakeKey)) {
          fields.push(`${snakeKey} = $${paramIndex}`);
          values.push(value);
          paramIndex++;
        }
      }

      if (fields.length === 0) {
        return res.status(400).json({ error: 'No valid fields to update' });
      }

      values.push(id);
      const result = await pool.query(
        `UPDATE users SET ${fields.join(', ')} WHERE id = $${paramIndex}
         RETURNING id, profession_id, first_name, last_name, username, email,
                   phone, profile_image_url, social_provider, social_id,
                   is_active, is_verified, created_at, updated_at`,
        values
      );

      if (result.rows.length === 0) {
        return res.status(404).json({ error: 'User not found' });
      }

      res.json(result.rows[0]);
    } catch (error) {
      console.error('Error updating user:', error);
      res.status(500).json({ error: 'Failed to update user' });
    }
  });

  return router;
}

module.exports = { usersRoutes };
