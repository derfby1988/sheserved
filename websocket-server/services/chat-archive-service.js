'use strict';

/**
 * Chat archive helper — moved out of server.js during Phase 13.3
 * route extraction (P1-3).  Takes `pool` explicitly instead of reading
 * module state so both socket handlers and REST routes can use it.
 */
async function archiveChatMessages(pool, videoId, status) {
  if (!pool) return;
  try {
    // Copy messages to archive
    await pool.query(
      `INSERT INTO chat_messages_archive (id, room_id, video_id, sender_id, content, created_at, metadata)
       SELECT m.id, m.room_id, r.video_id, m.sender_id, m.content, m.created_at, m.metadata
       FROM chat_messages m
       JOIN chat_rooms r ON m.room_id = r.id
       WHERE r.video_id = $1
       ON CONFLICT (id) DO NOTHING`,
      [videoId]
    );
    // Delete from active messages
    await pool.query(
      `DELETE FROM chat_messages WHERE room_id IN (SELECT id FROM chat_rooms WHERE video_id = $1)`,
      [videoId]
    );
    // Mark room as archived
    await pool.query(
      `UPDATE chat_rooms SET last_message = $1, updated_at = NOW() WHERE video_id = $2`,
      [`[Archived: ${status}]`, videoId]
    );
    console.log(`[Archive] Video ${videoId} archived successfully (${status})`);
  } catch (err) {
    console.error(`[Archive] Failed to archive video ${videoId}:`, err.message);
  }
}

module.exports = { archiveChatMessages };
