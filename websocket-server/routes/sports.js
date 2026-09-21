'use strict';

/**
 * Routes: /api/sports/propose
 * Extracted following the Phase 13.3 P1-3 route pattern.
 *
 * Identity contract: mounted behind verifyToken(pool) in server.js —
 * the sport row is written with the service-role client while the proposer
 * comes only from req.userId (verified by verifyToken). Actor IDs from the
 * body are ignored.
 */

const express = require('express');

const NOTIFICATION_COLUMNS =
  'id, profession_id, recipient_id, category, event_type, title, body, payload, is_read, read_at, dismissed_at, created_at';

const SPORT_REVIEW_ROUTE = '/community/sport-club/sport/review';

/**
 * @param {{supabaseForSync: object, socketService: object}} deps
 */
function sportsRoutes({ supabaseForSync, socketService }) {
  const router = express.Router();

  function requireNotificationStore(res) {
    if (!supabaseForSync) {
      res.status(503).json({ error: 'Notification store not available' });
      return false;
    }
    return true;
  }

  /**
   * Notifies every active admin that a new sport type is waiting for review.
   * Mirrors the profession-application flow so the in-app toast and the
   * notification panel behave identically.
   */
  async function notifyAdminsOfSportProposal({ sport, proposerName }) {
    const { data: admins, error: adminError } = await supabaseForSync
      .from('users')
      .select('id')
      .eq('role', 'admin')
      .eq('is_active', true);
    if (adminError) throw adminError;

    const recipientIds = (admins || []).map((admin) => admin.id);
    if (recipientIds.length === 0) return;

    const sportName = sport.name_th || '';
    const title = 'มีคำขอเพิ่มประเภทกีฬาใหม่';
    const body = proposerName
      ? `${proposerName} เสนอประเภทกีฬา "${sportName}"`
      : `มีผู้เสนอประเภทกีฬา "${sportName}"`;
    const payload = {
      sportId: sport.id,
      sportName,
      proposedBy: sport.proposed_by || null,
      route: SPORT_REVIEW_ROUTE,
    };

    const { data: inserted, error: notifyError } = await supabaseForSync
      .from('app_notifications')
      .insert(
        recipientIds.map((recipientId) => ({
          recipient_id: recipientId,
          category: 'sport',
          event_type: 'sport.proposal_submitted',
          title,
          body,
          payload,
        })),
      )
      .select(NOTIFICATION_COLUMNS);

    if (notifyError) {
      console.error(
        '[Sports] Admin notification failed:',
        notifyError.message,
      );
      return;
    }

    for (const notification of inserted || []) {
      socketService.broadcastApplicationNotification(
        [notification.recipient_id],
        notification,
      );
    }
  }

  async function proposerDisplayName(userId) {
    try {
      const { data } = await supabaseForSync
        .from('users')
        .select('first_name, last_name')
        .eq('id', userId)
        .maybeSingle();
      return [data?.first_name, data?.last_name]
        .map((value) => (value || '').trim())
        .filter((value) => value.length > 0)
        .join(' ');
    } catch (_) {
      return '';
    }
  }

  router.post('/', async (req, res) => {
    if (!req.userId) return res.status(401).json({ error: 'Login required' });
    if (!requireNotificationStore(res)) return;

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
        .select('id, name_th, proposed_by')
        .single();
      if (insertError) throw insertError;

      try {
        const proposerName = await proposerDisplayName(req.userId);
        await notifyAdminsOfSportProposal({ sport, proposerName });
      } catch (notifyError) {
        // The request itself succeeded — a failed admin notification must not
        // roll back the proposal the user just submitted.
        console.error('[Sports] Notify admins failed:', notifyError.message);
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
