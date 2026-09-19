'use strict';

/**
 * Routes: Supabase→Local sync endpoints
 * Extracted from server.js (Phase 13.3 P1-3 route refactor).
 * Mounted at /api — paths carry the full prefix.
 *
 *   POST /professions/sync
 *   POST /registration_field_configs/sync
 *   GET  /sync/status
 *   (POST /users/sync lives in routes/users.js with the users router)
 */

const express = require('express');

/**
 * @param {{pool: object|null}} deps
 */
function syncRoutes({ pool }) {
  const router = express.Router();

  // Sync professions from Supabase
  router.post('/professions/sync', async (req, res) => {
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
          `INSERT INTO professions (id, name, name_en, description, icon_name, category,
                                    is_built_in, is_active, is_volunteer, requires_verification, display_order,
                                    color_hex, created_at, updated_at)
           VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14)
           ON CONFLICT (id) DO UPDATE SET
             name = EXCLUDED.name,
             name_en = EXCLUDED.name_en,
             description = EXCLUDED.description,
             icon_name = EXCLUDED.icon_name,
             category = EXCLUDED.category,
             is_built_in = EXCLUDED.is_built_in,
             is_active = EXCLUDED.is_active,
             is_volunteer = EXCLUDED.is_volunteer,
             requires_verification = EXCLUDED.requires_verification,
             display_order = EXCLUDED.display_order,
             color_hex = EXCLUDED.color_hex,
             updated_at = EXCLUDED.updated_at`,
          [
            item.id, item.name, item.name_en, item.description, item.icon_name,
            item.category, item.is_built_in, item.is_active, item.is_volunteer,
            item.requires_verification, item.display_order, item.color_hex,
            item.created_at, item.updated_at
          ]
        );
        synced++;
      }

      console.log(`✅ Synced ${synced} professions`);
      res.json({ message: `Synced ${synced} professions` });
    } catch (error) {
      console.error('Error syncing professions:', error);
      res.status(500).json({ error: 'Failed to sync professions' });
    }
  });

  // Sync registration_field_configs from Supabase
  router.post('/registration_field_configs/sync', async (req, res) => {
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
          `INSERT INTO registration_field_configs 
           (id, profession_id, field_id, label, hint, field_type, is_required, 
            field_order, icon_name, dropdown_options, validation_regex, 
            validation_message, is_active, created_at, updated_at)
           VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15)
           ON CONFLICT (id) DO UPDATE SET
             profession_id = EXCLUDED.profession_id,
             field_id = EXCLUDED.field_id,
             label = EXCLUDED.label,
             hint = EXCLUDED.hint,
             field_type = EXCLUDED.field_type,
             is_required = EXCLUDED.is_required,
             field_order = EXCLUDED.field_order,
             icon_name = EXCLUDED.icon_name,
             dropdown_options = EXCLUDED.dropdown_options,
             validation_regex = EXCLUDED.validation_regex,
             validation_message = EXCLUDED.validation_message,
             is_active = EXCLUDED.is_active,
             updated_at = EXCLUDED.updated_at`,
          [
            item.id, item.profession_id, item.field_id, item.label, item.hint,
            item.field_type, item.is_required, item.field_order, item.icon_name,
            item.dropdown_options, item.validation_regex, item.validation_message,
            item.is_active, item.created_at, item.updated_at
          ]
        );
        synced++;
      }

      console.log(`✅ Synced ${synced} field configs`);
      res.json({ message: `Synced ${synced} field configs` });
    } catch (error) {
      console.error('Error syncing field configs:', error);
      res.status(500).json({ error: 'Failed to sync field configs' });
    }
  });

  // Get sync status
  router.get('/sync/status', async (req, res) => {
    try {
      const tables = ['professions', 'users', 'registration_field_configs', 'registration_applications'];
      const counts = {};

      if (pool) {
        for (const table of tables) {
          const result = await pool.query(`SELECT COUNT(*) FROM ${table}`);
          counts[table] = parseInt(result.rows[0].count);
        }
      }

      res.json({
        status: pool ? 'connected' : 'disconnected',
        tables: counts,
        timestamp: new Date().toISOString()
      });
    } catch (error) {
      console.error('Error getting sync status:', error);
      res.status(500).json({ error: 'Failed to get sync status' });
    }
  });

  return router;
}

module.exports = { syncRoutes };
