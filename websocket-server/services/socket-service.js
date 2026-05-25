const { Server } = require('socket.io');

let io = null;

/**
 * Initialize Socket.io service
 * @param {Server} ioInstance 
 */
function init(ioInstance) {
    io = ioInstance;
    console.log('✅ Socket Service initialized');
}

/**
 * Send progress update to a specific user
 * @param {string} userId 
 * @param {string} videoId 
 * @param {number} progress 
 */
function sendProgress(userId, videoId, progress) {
    if (!io) return;
    io.to(`user-${userId}`).emit('video-progress', {
        videoId,
        progress: Math.round(progress)
    });
}

/**
 * Send status update to a specific user
 * @param {string} userId 
 * @param {string} videoId 
 * @param {string} status 
 * @param {object} additionalData 
 */
function sendStatus(userId, videoId, status, additionalData = {}) {
    if (!io) return;
    io.to(`user-${userId}`).emit('video-status', {
        videoId,
        status,
        ...additionalData
    });
}

/**
 * Broadcast interaction (Like/Gift) to all viewers of a video
 * @param {string} videoId 
 * @param {object} interactionData 
 */
function broadcastInteraction(videoId, interactionData) {
    if (!io) return;
    // Assuming viewers join a room named 'video-{videoId}'
    io.to(`video-${videoId}`).emit('video-interaction', interactionData);
}

/**
 * Broadcast emergency chat message to all participants in a video's chat room
 * @param {string} videoId 
 * @param {object} messageData 
 */
function broadcastEmergencyMessage(videoId, messageData) {
    if (!io) return;
    io.to(`emergency-chat-${videoId}`).emit('emergency-chat-message', messageData);
}

/**
 * Broadcast new Thai Mhung photo to all viewers in the incident room
 * @param {string} incidentId - The video/incident ID that viewers have joined
 * @param {object} photoData - { photo_url, user_id, latitude, longitude, created_at }
 */
function broadcastNewThaiMhungPhoto(incidentId, photoData) {
    if (!io) return;
    console.log(`[ThaiMhung] Broadcasting new photo to room video-${incidentId}`);
    io.to(`video-${incidentId}`).emit('new-thaimhung-photo', {
        incidentId,
        ...photoData,
    });
}

/**
 * Broadcast thumbnail update to all clients — ให้ TrendingPanel รีเฟรชรูปพื้นหลัง Real-time
 * Recommendation #7: WebSocket thumbnail-updated event
 * @param {string} incidentId - ID ของ incident ที่ thumbnail เปลี่ยน
 * @param {object} data - { incidentId, thumbnailUrl }
 */
function broadcastThumbnailUpdate(incidentId, data) {
    if (!io) return;
    console.log(`[Thumbnail] Broadcasting thumbnail-updated for incident ${incidentId}`);
    // Broadcast ไปยังทุก client ที่อยู่ในห้อง video นั้น
    io.to(`room-video-${incidentId}`).emit('thumbnail-updated', {
        incidentId,
        ...data,
    });
    // ✅ Broadcast ไปยัง room หลักด้วย (สำหรับ Home page TrendingPanel ที่ไม่ได้ join video room)
    io.emit('thumbnail-updated', {
        incidentId,
        ...data,
    });
}

/**
 * Broadcast emergency health data release to responders in incident room
 * @param {string} incidentId
 * @param {object} releaseData - { sessionId, patientId, releasedFields, autoReleasedAt }
 */
function broadcastEmergencyHealthReleased(incidentId, releaseData) {
    if (!io) return;
    console.log(`[EmergencyHealth] Broadcasting health released for incident ${incidentId}`);
    io.to(`video-${incidentId}`).emit('emergency-health-released', {
        incidentId,
        ...releaseData,
    });
}

module.exports = {
    init,
    sendProgress,
    sendStatus,
    broadcastInteraction,
    broadcastEmergencyMessage,
    broadcastNewThaiMhungPhoto,
    broadcastThumbnailUpdate,
    broadcastEmergencyHealthReleased,
    /// คืน io instance สำหรับ services อื่นที่ต้องการ emit events โดยตรง
    getIO: () => io,
};
