const { Queue, Worker } = require('bullmq');
const ffmpeg = require('fluent-ffmpeg');
ffmpeg.setFfmpegPath('/opt/homebrew/bin/ffmpeg');
const path = require('path');
const fs = require('fs');
const axios = require('axios');
const socketService = require('./socket-service');

// Redis connection config
const connection = {
    url: process.env.REDIS_URL || 'redis://localhost:6379'
};

// Database pool reference
let dbPool = null;

function init(pool) {
    dbPool = pool;
}

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
 * Upload directory to Bunny.net storage
 */
async function uploadToBunny(outputDir, videoId) {
    const apiKey = process.env.BUNNY_API_KEY;
    const storageZone = process.env.BUNNY_STORAGE_ZONE;

    if (!apiKey || !storageZone || apiKey === 'your_api_key_here') {
        console.warn('[Bunny.net] API Key not configured. Skipping upload.');
        return;
    }

    const files = fs.readdirSync(outputDir);
    for (const file of files) {
        const filePath = path.join(outputDir, file);
        const fileData = fs.readFileSync(filePath);
        // Note: the URL must end with a trailing slash for a directory or the complete file name
        const bunnyUrl = `https://storage.bunnycdn.com/${storageZone}/${videoId}/${file}`;

        try {
            await axios.put(bunnyUrl, fileData, {
                headers: {
                    'AccessKey': apiKey,
                    'Content-Type': 'application/octet-stream'
                }
            });
            console.log(`[Bunny.net] Uploaded ${file}`);
        } catch (error) {
            console.error(`[Bunny.net] Upload error for ${file}:`, error.message);
            throw error;
        }
    }
}

/**
 * Worker to process video transcode
 */
const worker = new Worker('video-processing', async (job) => {
    const { id: videoId, userId, filePath, title } = job.data;
    const baseDir = process.env.TEMP_VIDEO_PATH || path.join(__dirname, '../temp/videos');
    const outputDir = path.join(baseDir, videoId);
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
                '-vf scale=-2:360', // บีบอัดความละเอียดลงมาที่ 360p (ส่วนสูง 360px กว้างปรับหดตามอัตราส่วนอัตโนมัติ)
                '-start_number 0',
                '-hls_time 2',      // ลดเวลาของแต่ละ segment จาก 10 วินาทีเหลือ 2 วินาที เพื่อให้โหลดตอนแรกไวขึ้น
                '-hls_list_size 0',
                '-f hls'
            ])
            .on('progress', (progress) => {
                const percent = Math.floor(progress.percent || 0);
                socketService.sendProgress(userId, videoId, percent);
                if (dbPool) {
                    dbPool.query('UPDATE videos SET progress = $1 WHERE id = $2', [percent, videoId])
                        .catch(err => console.error('DB progress update failed:', err.message));
                }
            })
            .on('end', async () => {
                console.log(`[Worker] Transcoding finished: ${videoId}`);
                try {
                    // Start Bunny.net Upload
                    socketService.sendStatus(userId, videoId, 'uploading');

                    if (dbPool) {
                        await dbPool.query('UPDATE videos SET status = $1 WHERE id = $2', ['uploading', videoId]);
                    }

                    await uploadToBunny(outputDir, videoId);

                    const finalUrl = process.env.BUNNY_CDN_URL && process.env.BUNNY_CDN_URL !== 'https://your-pull-zone.b-cdn.net'
                        ? `${process.env.BUNNY_CDN_URL}/${videoId}/playlist.m3u8`
                        : null; // Set to null. App will dynamically generate local URL via AppConfig.localApiUrl

                    if (dbPool) {
                        await dbPool.query('UPDATE videos SET status = $1, progress = 100, bunny_url = $2 WHERE id = $3', ['ready', finalUrl, videoId]);
                    }

                    socketService.sendStatus(userId, videoId, 'ready', { url: finalUrl });

                    // Cleanup
                    const keepOutputDir = (finalUrl === null);
                    cleanup(filePath, outputDir, keepOutputDir);
                    resolve();
                } catch (error) {
                    console.error('[Worker] Error after transcode:', error);
                    if (dbPool) {
                        await dbPool.query('UPDATE videos SET status = $1 WHERE id = $2', ['error', videoId]);
                    }
                    socketService.sendStatus(userId, videoId, 'error', { error: error.message });
                    reject(error);
                }
            })
            .on('error', (err) => {
                console.error(`[Worker] FFmpeg Error: ${err.message}`);
                if (dbPool) {
                    dbPool.query('UPDATE videos SET status = $1 WHERE id = $2', ['error', videoId]).catch(e => { });
                }
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
 * @param {boolean} keepOutputDir 
 */
function cleanup(originalPath, outputDir, keepOutputDir = false) {
    try {
        if (fs.existsSync(originalPath)) fs.unlinkSync(originalPath); // Delete the original mp4

        if (!keepOutputDir && fs.existsSync(outputDir)) {
            fs.rmSync(outputDir, { recursive: true, force: true });
        }
        console.log(`[Cleanup] Removed temp files for ${originalPath}${keepOutputDir ? ' (kept transcoded HLS files)' : ''}`);
    } catch (error) {
        console.error(`[Cleanup] Error: ${error.message}`);
    }
}

module.exports = {
    addToQueue,
    init
};
