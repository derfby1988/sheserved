'use strict';

/**
 * Routes: /api/notifications + /api/profession-change
 * Extracted from server.js (Phase 13.3 P1-3 route refactor).
 *
 * Identity contract: mounted behind verifyToken(pool) in server.js —
 * these routes use the service-role client while identity comes only
 * from req.userId (verified by verifyToken). Actor IDs from the body
 * are ignored.
 */

const express = require('express');

const NOTIFICATION_COLUMNS =
  'id, profession_id, recipient_id, category, event_type, title, body, payload, is_read, read_at, dismissed_at, created_at';

/**
 * @param {{supabaseForSync: object, socketService: object}} deps
 */
function notificationsRoutes({ supabaseForSync, socketService }) {
  const router = express.Router();

  function requireNotificationStore(res) {
    if (!supabaseForSync) {
      res.status(503).json({ error: 'Notification store not available' });
      return false;
    }
    return true;
  }

  router.get('/', async (req, res) => {
    if (!req.userId) return res.status(401).json({ error: 'Login required' });
    if (!requireNotificationStore(res)) return;

    const category = typeof req.query.category === 'string' ? req.query.category : null;
    const limit = Math.min(Math.max(parseInt(req.query.limit, 10) || 50, 1), 100);
    try {
      let query = supabaseForSync
        .from('app_notifications')
        .select(NOTIFICATION_COLUMNS)
        .eq('recipient_id', req.userId)
        .is('dismissed_at', null);
      if (category) query = query.eq('category', category);
      const { data, error } = await query.order('created_at', { ascending: false }).limit(limit);
      if (error) throw error;
      res.json(data || []);
    } catch (error) {
      console.error('[Notifications] List failed:', error.message);
      res.status(500).json({ error: 'Failed to load notifications' });
    }
  });

  router.get('/unread-count', async (req, res) => {
    if (!req.userId) return res.status(401).json({ error: 'Login required' });
    if (!requireNotificationStore(res)) return;

    const category = typeof req.query.category === 'string' ? req.query.category : null;
    try {
      let query = supabaseForSync
        .from('app_notifications')
        .select('id', { count: 'exact', head: true })
        .eq('recipient_id', req.userId)
        .eq('is_read', false)
        .is('dismissed_at', null);
      if (category) query = query.eq('category', category);
      const { count, error } = await query;
      if (error) throw error;
      res.json({ count: count || 0 });
    } catch (error) {
      console.error('[Notifications] Unread count failed:', error.message);
      res.status(500).json({ error: 'Failed to load unread count' });
    }
  });

  async function updateOwnNotification(req, res, patch) {
    if (!req.userId) return res.status(401).json({ error: 'Login required' });
    if (!requireNotificationStore(res)) return;
    try {
      const { data, error } = await supabaseForSync
        .from('app_notifications')
        .update(patch)
        .eq('id', req.params.id)
        .eq('recipient_id', req.userId)
        .select('id');
      if (error) throw error;
      res.json({ success: Array.isArray(data) && data.length === 1 });
    } catch (error) {
      console.error('[Notifications] Update failed:', error.message);
      res.status(500).json({ error: 'Failed to update notification' });
    }
  }

  router.post('/:id/read', (req, res) =>
    updateOwnNotification(req, res, { is_read: true, read_at: new Date().toISOString() }));

  router.post('/:id/dismiss', (req, res) =>
    updateOwnNotification(req, res, {
      is_read: true,
      read_at: new Date().toISOString(),
      dismissed_at: new Date().toISOString(),
    }));

  return router;
}

/**
 * POST / — profession change request (mounted at /api/profession-change).
 * @param {{supabaseForSync: object, socketService: object}} deps
 */
function professionChangeRoute({ supabaseForSync, socketService }) {
  const router = express.Router();

  function requireNotificationStore(res) {
    if (!supabaseForSync) {
      res.status(503).json({ error: 'Notification store not available' });
      return false;
    }
    return true;
  }

  router.post('/', async (req, res) => {
    if (!req.userId) return res.status(401).json({ error: 'Login required' });
    if (!requireNotificationStore(res)) return;

    const {
      professionId,
      firstName,
      lastName,
      username,
      phone,
      profileImageUrl,
      registrationData = {},
    } = req.body || {};
    if (!professionId || !firstName || !username) {
      return res.status(400).json({ error: 'professionId, firstName and username are required' });
    }

    try {
      const { data: profession, error: professionError } = await supabaseForSync
        .from('professions')
        .select('id, name, requires_verification, category')
        .eq('id', professionId)
        .eq('is_active', true)
        .maybeSingle();
      if (professionError) throw professionError;
      if (!profession) return res.status(404).json({ error: 'Profession not found' });

      if (!profession.requires_verification) {
        const { error: updateError } = await supabaseForSync
          .from('users')
          .update({
            profession_id: professionId,
            role: profession.category === 'consumer' ? 'consumer' : 'provider',
            verification_status: 'verified',
            updated_at: new Date().toISOString(),
          })
          .eq('id', req.userId)
          .neq('role', 'admin');
        if (updateError) throw updateError;
        return res.json({ requiresVerification: false });
      }

      // The RPC enforces PENDING_EXISTS / APPROVED_EXISTS / ROLE_EXISTS atomically.
      const { data: application, error: rpcError } = await supabaseForSync.rpc(
        'create_registration_application',
        {
          p_user_id: req.userId,
          p_profession_id: professionId,
          p_first_name: firstName,
          p_last_name: lastName || '',
          p_username: username,
          p_phone: phone || null,
          p_profile_image_url: profileImageUrl || null,
          p_registration_data: registrationData,
        },
      );
      if (rpcError) {
        if (rpcError.message.includes('PENDING_EXISTS')) {
          return res.status(409).json({ error: 'คุณมีใบสมัครที่กำลังรอตรวจสอบอยู่แล้ว' });
        }
        if (rpcError.message.includes('APPROVED_EXISTS')) {
          return res.status(409).json({ error: 'คุณได้รับการอนุมัติสำหรับอาชีพนี้แล้ว' });
        }
        if (rpcError.message.includes('ROLE_EXISTS')) {
          return res.status(409).json({ error: 'คุณมีสิทธิ์ในองค์กรนี้อยู่แล้ว' });
        }
        if (rpcError.message.includes('FORBIDDEN')) {
          return res.status(403).json({ error: 'Forbidden' });
        }
        if (rpcError.message.includes('USER_NOT_FOUND')) {
          return res.status(404).json({ error: 'User not found' });
        }
        if (rpcError.message.includes('ADMIN_CANNOT_APPLY')) {
          return res
            .status(403)
            .json({ error: 'ผู้ดูแลระบบไม่สามารถสมัครเปลี่ยนอาชีพได้' });
        }
        throw rpcError;
      }

      // create_registration_application snapshots users.profession_id into
      // previous_profession_id and moves the user to the pending profession in
      // the same transaction — no separate users update needed here.

      const { data: admins, error: adminError } = await supabaseForSync
        .from('users')
        .select('id')
        .eq('role', 'admin')
        .eq('is_active', true);
      if (adminError) throw adminError;

      const applicantName = `${firstName} ${lastName || ''}`.trim();
      const title = 'มีคำขอเปลี่ยนอาชีพใหม่';
      const body = `${applicantName} ขอสมัครเป็น ${profession.name}`;
      const notificationPayload = {
        applicationId: application.id,
        userId: application.user_id,
        professionId: application.profession_id,
        route: '/admin/applications',
      };
      const recipientIds = (admins || []).map((admin) => admin.id);
      if (recipientIds.length > 0) {
        const { data: inserted, error: notifyError } = await supabaseForSync
          .from('app_notifications')
          .insert(recipientIds.map((recipientId) => ({
            profession_id: professionId,
            recipient_id: recipientId,
            category: 'admin',
            event_type: 'profession_application.created',
            title,
            body,
            payload: notificationPayload,
          })))
          .select(NOTIFICATION_COLUMNS);
        if (notifyError) {
          console.error('[ProfessionChange] Admin notification failed:', notifyError.message);
        } else {
          for (const notification of inserted || []) {
            socketService.broadcastApplicationNotification([notification.recipient_id], notification);
          }
        }
      }

      res.status(201).json({ requiresVerification: true, application });
    } catch (error) {
      console.error('[ProfessionChange] Failed:', error.message);
      res.status(500).json({ error: 'Failed to submit profession change' });
    }
  });

  return router;
}

module.exports = { notificationsRoutes, professionChangeRoute };
