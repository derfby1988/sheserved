'use strict';

/**
 * Phase 13.3 Step 6 — Room Authorization Data Model
 * ─────────────────────────────────────────────────────────────
 * Room taxonomy (Socket.IO room names used in this codebase):
 *
 *   video-{id} / room-video-{id}   → PUBLIC broadcast rooms
 *                                    (viewer count, like counts, route
 *                                    updates) — anyone may join.
 *   emergency-chat-{videoId}       → MEMBERSHIP room — allowed:
 *                                    • video owner / reporter
 *                                    • active responders (incident_responses
 *                                      status accepted|arrived|en_route)
 *                                    • admin role (moderation)
 *   user-{userId}                  → PERSONAL channel — self only
 *                                    (verified socket.userId === id)
 *   anything else                  → denied under strict flags; compat
 *                                    window keeps current behavior.
 *
 * Data source: local direct pool (sheserved_app role) — NOT service_role,
 * NOT the Supabase service client.  incident_responses + videos live in
 * the local DB (dual-write copy on Supabase may lag/empty).
 *
 * Redis membership cache (60s) + revocation propagation land in Step 7;
 * this module performs the authoritative check each call for now.
 */

const PUBLIC_ROOM_PREFIXES = ['video-', 'room-video-'];
const MEMBERSHIP_ROOM_PREFIX = 'emergency-chat-';
const PERSONAL_ROOM_PREFIX = 'user-';

const ACTIVE_RESPONSE_STATUSES = ['accepted', 'arrived', 'en_route'];

function classifyRoom(roomName) {
  if (!roomName || typeof roomName !== 'string') return 'unknown';
  if (roomName.startsWith(PERSONAL_ROOM_PREFIX)) return 'personal';
  if (roomName.startsWith(MEMBERSHIP_ROOM_PREFIX)) return 'membership';
  if (PUBLIC_ROOM_PREFIXES.some((p) => roomName.startsWith(p))) return 'public';
  return 'unknown';
}

/**
 * Membership check for emergency-chat-{videoId} via direct pool.
 * @returns {Promise<boolean>}
 */
async function isEmergencyChatMember(pool, videoId, userId) {
  const result = await pool.query(
    `SELECT 1 FROM (
       SELECT 1 FROM videos
        WHERE id = $1 AND user_id = $2
       UNION ALL
       SELECT 1 FROM incident_responses
        WHERE video_id = $1 AND volunteer_id = $2
          AND status = ANY($3)
     ) m LIMIT 1`,
    [videoId, userId, ACTIVE_RESPONSE_STATUSES]
  );
  return result.rows.length > 0;
}

/**
 * authorizeRoomJoin(socket, roomName) → {allowed, reason}
 *
 * @param {{pool: object|null}} deps — direct local pool (sheserved_app)
 * @param {object} socket — Socket.IO socket (must carry .userId/.userRole/
 *                          .identitySource from socket-auth middleware)
 * @param {string} roomName
 */
async function authorizeRoomJoin({ pool }, socket, roomName) {
  const kind = classifyRoom(roomName);

  switch (kind) {
    case 'public':
      return { allowed: true, reason: 'public-room' };

    case 'personal': {
      const targetUserId = roomName.slice(PERSONAL_ROOM_PREFIX.length);
      if (!socket.userId) {
        return { allowed: false, reason: 'identity-required' };
      }
      if (`${socket.userId}` !== `${targetUserId}`) {
        return { allowed: false, reason: 'not-self' };
      }
      return { allowed: true, reason: 'self' };
    }

    case 'membership': {
      if (!socket.userId) {
        return { allowed: false, reason: 'identity-required' };
      }
      if (socket.userRole === 'admin') {
        return { allowed: true, reason: 'admin' };
      }
      if (!pool) {
        // No DB → cannot verify membership → fail closed for private rooms
        return { allowed: false, reason: 'membership-unverifiable' };
      }
      const videoId = roomName.slice(MEMBERSHIP_ROOM_PREFIX.length);
      const member = await isEmergencyChatMember(pool, videoId, socket.userId);
      return member
        ? { allowed: true, reason: 'member' }
        : { allowed: false, reason: 'not-member' };
    }

    default:
      // Unknown room namespace — deny under strict, allow in compat.
      return { allowed: false, reason: 'unknown-room-namespace' };
  }
}

module.exports = {
  classifyRoom,
  authorizeRoomJoin,
  isEmergencyChatMember,
  PUBLIC_ROOM_PREFIXES,
  MEMBERSHIP_ROOM_PREFIX,
  PERSONAL_ROOM_PREFIX,
};
