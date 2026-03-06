const { Queue, Worker } = require('bullmq');
const ffmpeg = require('fluent-ffmpeg');
const path = require('path');
const fs = require('fs');
const axios = require('axios');
const socketService = require('./socket-service');

// Redis connection config
const connection = {
    url: process.env.REDIS_URL || 'redis://localhost:6379'
};

// Initialize Queue
const videoQueue = new Queue('video-processing', { connection });

/**
 * Add video to processing queue
 * @param {object} videoData 
 */
async function addToQueue(videoData) {
    const priority = videoData.type === 'emergency' ? 1 : 2;
    await videoQueue.add('transcode', videoData, { priority });
    console.log(`[Queue] Added video ${videoData.id} (Type: ${videoData.type}, Priority: ${priority})`);
}

/**
 * Worker to process video transcode
 */
const worker = new Worker('video-processing', async (job) => {
    const { id: videoId, userId, filePath, title } = job.data;
    const outputDir = path.join(__dirname, '../temp/videos', videoId);
    const hlsPath = path.join(outputDir, 'playlist.m3u8');

    if (!fs.existsSync(outputDir)) {
        fs.mkdirSync(outputDir, { recursive: true });
    }

    console.log(`[Worker] Processing video ${videoId}: ${filePath}`);
    socketService.sendStatus(userId, videoId, 'processing');

    return new Promise((resolve, reject) => {
        ffmpeg(filePath)
            .outputOptions([
                '-profile:v baseline',
                '-level 3.0',
                '-start_number 0',
                '-hls_time 10',
                '-hls_list_size 0',
                '-f hls'
            ])
            .on('progress', (progress) => {
                socketService.sendProgress(userId, videoId, progress.percent);
                // Also update DB progress if needed
            })
            .on('end', async () => {
                console.log(`[Worker] Transcoding finished: ${videoId}`);
                try {
                    // Start Bunny.net Upload (Placeholder for now)
                    socketService.sendStatus(userId, videoId, 'uploading');

                    // TODO: Implement Bunny.net upload logic
                    // await uploadToBunny(outputDir, videoId);

                    socketService.sendStatus(userId, videoId, 'ready', {
                        url: `${process.env.BUNNY_CDN_URL}/${videoId}/playlist.m3u8`
                    });

                    // Cleanup
                    cleanup(filePath, outputDir);
                    resolve();
                } catch (error) {
                    reject(error);
                }
            })
            .on('error', (err) => {
                console.error(`[Worker] FFmpeg Error: ${err.message}`);
                socketService.sendStatus(userId, videoId, 'error', { error: err.message });
                reject(err);
            })
            .save(hlsPath);
    });
}, {
    connection,
    concurrency: parseInt(process.env.MAX_CONCURRENT_TRANSCODES || '2')
});

/**
 * Cleanup temporary files
 * @param {string} originalPath 
 * @param {string} outputDir 
 */
function cleanup(originalPath, outputDir) {
    try {
        if (fs.existsSync(originalPath)) fs.unlinkSync(originalPath);
        if (fs.existsSync(outputDir)) {
            fs.rmSync(outputDir, { recursive: true, force: true });
        }
        console.log(`[Cleanup] Removed temp files for ${originalPath}`);
    } catch (error) {
        console.error(`[Cleanup] Error: ${error.message}`);
    }
}

module.exports = {
    addToQueue
};
