'use strict';

/**
 * Routes: /api/professions* (public read)
 * Extracted from server.js (Phase 13.3 P1-3 route refactor).
 * Mounted at /api/professions.
 */

const express = require('express');
const { cacheAside, TTL } = require('../middleware');

/**
 * @param {{pool: object|null}} deps
 */
function professionsRoutes({ pool }) {
  const router = express.Router();

  // Get all professions
  router.get('/', async (req, res) => {
    try {
      if (!pool) {
        return res.status(503).json({ error: 'Database not available' });
      }

      const data = await cacheAside('professions:active', async () => {
        const result = await pool.query(
          `SELECT id, name, name_en, description, icon_name, category, 
                  is_built_in, is_active, requires_verification, display_order,
                  color_hex, created_at, updated_at
           FROM professions 
           WHERE is_active = true 
           ORDER BY display_order ASC`
        );
        return result.rows;
      }, TTL.DEFAULT);
      res.json(data);
    } catch (error) {
      console.error('Error fetching professions:', error);
      res.status(500).json({ error: 'Failed to fetch professions' });
    }
  });

  // Get profession by ID
  router.get('/:id', async (req, res) => {
    try {
      if (!pool) {
        return res.status(503).json({ error: 'Database not available' });
      }

      const { id } = req.params;
      const data = await cacheAside(`profession:${id}`, async () => {
        const result = await pool.query(
          `SELECT * FROM professions WHERE id = $1`,
          [id]
        );
        return result.rows[0] || null;
      }, TTL.DEFAULT);

      if (data === null) {
        return res.status(404).json({ error: 'Profession not found' });
      }

      res.json(data);
    } catch (error) {
      console.error('Error fetching profession:', error);
      res.status(500).json({ error: 'Failed to fetch profession' });
    }
  });

  // Get registration fields for a profession
  router.get('/:id/fields', async (req, res) => {
    try {
      if (!pool) {
        return res.status(503).json({ error: 'Database not available' });
      }

      const { id } = req.params;
      const data = await cacheAside(`profession:fields:${id}`, async () => {
        const result = await pool.query(
          `SELECT id, field_id, label, hint, field_type, is_required, 
                  field_order, icon_name, dropdown_options, validation_regex,
                  validation_message, is_active
           FROM registration_field_configs 
           WHERE profession_id = $1 AND is_active = true
           ORDER BY field_order ASC`,
          [id]
        );
        return result.rows;
      }, TTL.DEFAULT);

      res.json(data);
    } catch (error) {
      console.error('Error fetching fields:', error);
      res.status(500).json({ error: 'Failed to fetch fields' });
    }
  });

  return router;
}

module.exports = { professionsRoutes };
