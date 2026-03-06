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

module.exports = {
    init,
    sendProgress,
    sendStatus,
    broadcastInteraction
};
