'use strict';

/**
 * Routes: /api/sports/propose
 *
 * The database trigger creates one persisted app_notifications row per active
 * admin. This route optionally broadcasts those already-created rows over the
 * websocket-server channel; it never inserts a second notification. Legacy
 * direct-Supabase submissions still work through the DB trigger + Supabase
 * Realtime path.
 */

const express = require('express');

const NOTIFICATION_COLUMNS =
  'id, profession_id, recipient_id, category, event_type, title, body, payload, is_read, read_at, dismissed_at, created_at';

/**
 * @param {{supabaseForSync: object, socketService?: object}} deps
 */
function sportsRoutes({ supabaseForSync, socketService }) {
  const router = express.Router();

  function requireStore(res) {
    if (!supabaseForSync) {
      res.status(503).json({ error: 'Store not available' });
      return false;
    }
    return true;
  }

  async function broadcastCreatedNotifications(sportId) {
    if (!socketService?.broadcastApplicationNotification) return;

    const { data, error } = await supabaseForSync
      .from('app_notifications')
      .select(NOTIFICATION_COLUMNS)
      .eq('category', 'sport')
      .eq('event_type', 'sport.proposal_submitted')
      .contains('payload', { sportId });
    if (error) throw error;

    for (const notification of data || []) {
      socketService.broadcastApplicationNotification(
        [notification.recipient_id],
        notification,
      );
    }
  }

  router.post('/', async (req, res) => {
    if (!req.userId) return res.status(401).json({ error: 'Login required' });
    if (!requireStore(res)) return;

    const { nameTh, nameEn, fieldLayout, fieldStyle } = req.body || {};
    const trimmedNameTh = typeof nameTh === 'string' ? nameTh.trim() : '';
    if (!trimmedNameTh) {
      return res.status(400).json({ error: 'nameTh is required' });
    }

    try {
      const row = {
        name_th: trimmedNameTh,
        status: 'pending',
        proposed_by: req.userId,
        proposed_at: new Date().toISOString(),
      };
      if (typeof nameEn === 'string' && nameEn.trim().length > 0) {
        row.name_en = nameEn.trim();
      }
      if (typeof fieldLayout === 'string' && fieldLayout.length > 0) {
        row.field_layout = fieldLayout;
      }
      if (fieldStyle && typeof fieldStyle === 'object') {
        row.field_style = fieldStyle;
      }

      const { data: sport, error: insertError } = await supabaseForSync
        .from('sports')
        .insert(row)
        .select('id')
        .single();
      if (insertError) throw insertError;

      try {
        // The DB trigger owns persistence; this is only the optional live
        // websocket delivery path and therefore cannot create duplicates.
        await broadcastCreatedNotifications(sport.id);
      } catch (notificationError) {
        console.error(
          '[Sports] Websocket notification failed:',
          notificationError.message,
        );
      }

      res.status(201).json({ sportId: sport.id });
    } catch (error) {
      console.error('[Sports] Propose failed:', error.message);
      res.status(500).json({ error: 'Failed to submit sport proposal' });
    }
  });

  return router;
}

module.exports = { sportsRoutes };
