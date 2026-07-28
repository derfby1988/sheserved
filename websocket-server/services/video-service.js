const { Queue, Worker } = require('bullmq');
const ffmpeg = require('fluent-ffmpeg');
const { spawn } = require('child_process');
// ✅ ใช้ ENV แทน hardcoded path เพื่อรองรับ Linux/macOS/Windows
// ตั้งค่าใน .env: FFMPEG_PATH=/usr/bin/ffmpeg (Linux) หรือ /opt/homebrew/bin/ffmpeg (macOS)
// ถ้าไม่ตั้งค่าจะใช้ 'ffmpeg' จาก PATH ของระบบ
ffmpeg.setFfmpegPath(process.env.FFMPEG_PATH || 'ffmpeg');

const path = require('path');
const fs = require('fs');
const axios = require('axios');
const sharp = require('sharp');
const socketService = require('./socket-service');
const thumbnailQueue = require('./thumbnail-queue');
const { createBullmqConnection } = require('./bullmq-connection');
const { resolveQueueOptions } = require('../utils/queue-config');
const { invalidateCacheMany } = require('../middleware');
const { assertUuid, safeJoin, assertAllowedCommand, resolveExecutable } = require('../utils/safe-path');

// Shared BullMQ connection config (reuses the existing Redis source of truth)
const connection = createBullmqConnection();

// Database pool reference
let dbPool = null;

function init(pool) {
    dbPool = pool;
    // ✅ Bug #3 Fix: เริ่ม Thumbnail Queue Worker ด้วย pool เดียวกัน
    thumbnailQueue.init(pool);
}

// Initialize Queue
const QUEUE_NAME = 'video-processing';
const queueOptions = resolveQueueOptions(QUEUE_NAME, {
    defaultJobOptions: {
        attempts: 3,
        backoff: { type: 'fixed', delay: 5000 },
        removeOnComplete: { count: 200 },
        removeOnFail: { count: 200 },
    },
    concurrency: 1,
});

const videoQueue = new Queue(QUEUE_NAME, {
    connection,
    defaultJobOptions: queueOptions.defaultJobOptions,
});

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
const worker = new Worker(QUEUE_NAME, async (job) => {
    const { id: videoId, userId, filePath, title } = job.data;
    const baseDir = process.env.TEMP_VIDEO_PATH || path.join(__dirname, '../temp/videos');
    assertUuid(videoId, 'videoId');
    const outputDir = safeJoin(baseDir, videoId);
    const hlsPath = path.join(outputDir, 'playlist.m3u8');

    if (!fs.existsSync(outputDir)) {
        fs.mkdirSync(outputDir, { recursive: true });
    }

    let inputVideoPath = filePath;

    console.log(`[Worker] Processing video ${videoId}: ${inputVideoPath}`);
    socketService.sendStatus(userId, videoId, 'processing');

    // Fetch Watermark Config
    let watermarkConfig = null;
    if (dbPool) {
        try {
            const res = await dbPool.query('SELECT * FROM watermark_configs WHERE id = 1 AND is_enabled = true');
            if (res.rows.length > 0) watermarkConfig = res.rows[0];
        } catch (e) {
            console.warn('[Watermark] Failed to fetch config:', e.message);
        }
    }

    // --- Face Blur (Open Source: deface) ---
    // รันการเบลอหน้าด้วย python-deface ก่อนแปลงไฟล์
    try {
        assertUuid(videoId, 'videoId');
        const blurredPath = safeJoin(baseDir, `${videoId}_blurred.mp4`);
        console.log(`[Worker] Applying Face Blur to ${videoId}...`);
        
        // ✅ Option A: ใช้ spawn แทน execSync เพื่อป้องกัน Command Injection
        // ส่ง argument แบบ array ไม่ผ่าน shell
        const defaceBin = resolveExecutable('DEFACE_PATH', 'deface');
        assertAllowedCommand(defaceBin);
        
        await new Promise((resolve, reject) => {
            const defaceProc = spawn(defaceBin, [
                inputVideoPath,
                '-o', blurredPath,
                '--replacewith', 'blur',
                '--keep-audio',
            ], { stdio: 'pipe' });
            
            let stderr = '';
            defaceProc.stderr.on('data', (data) => { stderr += data.toString(); });
            
            defaceProc.on('error', (err) => {
                reject(new Error(`deface spawn error: ${err.message}`));
            });
            
            defaceProc.on('close', (code) => {
                if (code === 0) {
                    resolve();
                } else {
                    reject(new Error(`deface exited with code ${code}: ${stderr}`));
                }
            });
        });
        
        if (fs.existsSync(blurredPath)) {
            console.log(`[Worker] Face Blur complete for ${videoId}`);
            inputVideoPath = blurredPath; // Use the blurred video for transcoding
        }
    } catch (blurError) {
        console.warn(`[Worker] Face Blur failed for ${videoId}, falling back to original video:`, blurError.message);
        // Continue with original video if blur fails
    }

    let tempTextImgPath = null;
    let tempForensicImgPath = null;

    if (watermarkConfig) {
        // Generate Text Watermark Image if needed
        if (watermarkConfig.type === 'text') {
            const text = watermarkConfig.text_content || 'Watermark';
            const opacity = watermarkConfig.opacity || 0.5;
            const svgText = `
            <svg width="400" height="60">
              <style>.t { fill: rgba(255, 255, 255, ${opacity}); font-size: 32px; font-family: sans-serif; font-weight: bold; }</style>
              <text x="10" y="40" class="t">${text}</text>
            </svg>`;
            tempTextImgPath = safeJoin(baseDir, `${videoId}_wm_text.png`);
            await sharp(Buffer.from(svgText)).png().toFile(tempTextImgPath);
        }

        // Generate Forensic Text Image if needed
        let forensicText = '';
        if (watermarkConfig.show_incident_id) forensicText += `Ref: ${videoId}  `;
        if (watermarkConfig.show_uploader_id) forensicText += `User: ${userId}`;
        forensicText = forensicText.trim();
        
        if (forensicText) {
            const svgForensic = `
            <svg width="600" height="40">
              <style>.t { fill: rgba(255, 255, 255, 0.5); font-size: 14px; font-family: sans-serif; }</style>
              <text x="10" y="20" class="t">${forensicText}</text>
            </svg>`;
            tempForensicImgPath = safeJoin(baseDir, `${videoId}_wm_forensic.png`);
            await sharp(Buffer.from(svgForensic)).png().toFile(tempForensicImgPath);
        }
    }

    return new Promise((resolve, reject) => {
        let ffCommand = ffmpeg(inputVideoPath);

        let outputOptions = [
            '-profile:v baseline',
            '-level 3.0',
            '-start_number 0',
            '-hls_time 2',
            '-hls_list_size 0',
            '-f hls'
        ];

        if (watermarkConfig) {
            const opacity = watermarkConfig.opacity || 0.5;
            let inputs = ['[0:v]scale=-2:360[bg]'];
            let currentBg = '[bg]';
            let inputIdx = 1;

            // Base X and Y positions
            let xPos = 'W-w-10';
            let yPos = 'H-h-10'; // bottom-right
            if (watermarkConfig.position === 'top-left') { xPos = '10'; yPos = '10'; }
            else if (watermarkConfig.position === 'top-right') { xPos = 'W-w-10'; yPos = '10'; }
            else if (watermarkConfig.position === 'bottom-left') { xPos = '10'; yPos = 'H-h-10'; }
            else if (watermarkConfig.position === 'center') { xPos = '(W-w)/2'; yPos = '(H-h)/2'; }

            // Animations
            if (watermarkConfig.animation_type === 'marquee') {
                xPos = 'W-t*100'; // move left 100px per sec
            } else if (watermarkConfig.animation_type === 'bounce') {
                xPos = '(W-w)/2+(W/4)*sin(t)'; // Bounce
                yPos = '(H-h)/2+(H/4)*cos(t*1.5)';
            } else if (watermarkConfig.animation_type === 'random') {
                xPos = 'if(eq(mod(t\\,5)\\,0)\\,random(1)*(W-w)\\,x)';
                yPos = 'if(eq(mod(t\\,5)\\,0)\\,random(1)*(H-h)\\,y)';
            }

            if (watermarkConfig.type === 'text' && tempTextImgPath) {
                ffCommand.input(tempTextImgPath);
                // The opacity is already in the SVG, so no colorchannelmixer needed
                inputs.push(`${currentBg}[${inputIdx}:v]overlay=x='${xPos}':y='${yPos}'[bg${inputIdx}]`);
                currentBg = `[bg${inputIdx}]`;
                inputIdx++;
            } else if (watermarkConfig.type === 'image' && watermarkConfig.image_url) {
                const imgPath = path.join(__dirname, '..', watermarkConfig.image_url);
                if (fs.existsSync(imgPath)) {
                    ffCommand.input(imgPath);
                    inputs.push(`[${inputIdx}:v]colorchannelmixer=aa=${opacity}[wm${inputIdx}]`);
                    inputs.push(`${currentBg}[wm${inputIdx}]overlay=x='${xPos}':y='${yPos}'[bg${inputIdx}]`);
                    currentBg = `[bg${inputIdx}]`;
                    inputIdx++;
                }
            }

            if (tempForensicImgPath) {
                ffCommand.input(tempForensicImgPath);
                inputs.push(`${currentBg}[${inputIdx}:v]overlay=x=10:y=H-h-10[bg${inputIdx}]`);
                currentBg = `[bg${inputIdx}]`;
                inputIdx++;
            }

            if (inputIdx > 1) {
                let filterStr = inputs.join(';');
                ffCommand.complexFilter(filterStr, currentBg.replace(/\[|\]/g, ''));
            } else {
                outputOptions.unshift('-vf', 'scale=-2:360');
            }
        } else {
            outputOptions.unshift('-vf', 'scale=-2:360');
        }

        ffCommand
            .outputOptions(outputOptions)
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

                    const localApiUrl = process.env.LOCAL_API_URL || 'http://localhost:3000';
                    const finalUrl = process.env.BUNNY_CDN_URL && process.env.BUNNY_CDN_URL !== 'https://your-pull-zone.b-cdn.net'
                        ? `${process.env.BUNNY_CDN_URL}/${videoId}/playlist.m3u8`
                        : `${localApiUrl}/temp/videos/${videoId}/playlist.m3u8`;

                    if (dbPool) {
                        await dbPool.query('UPDATE videos SET status = $1, progress = 100, bunny_url = $2 WHERE id = $3', ['ready', finalUrl, videoId]);
                    }

                    // Phase 2: Invalidate video caches so consumers get fresh metadata
                    try {
                        await invalidateCacheMany(
                            `video:meta:${videoId}`,
                            `video:emergency:list:*`,
                            `video:list:*`
                        );
                    } catch (cacheErr) {
                        console.warn(`[VideoWorker] Cache invalidation warning for ${videoId}:`, cacheErr.message);
                    }

                    socketService.sendStatus(userId, videoId, 'ready', { url: finalUrl });

                    // ✅ Bug #3 Fix: Extract Thumbnail Frame จากวิดีโอหลัง Transcode เสร็จ
                    // ส่งงานไปยัง ThumbnailQueue เพื่อไม่ block main processing
                    const thumbFilename = `thumb_${videoId}.jpg`;
                    const thumbPath = path.join(outputDir, thumbFilename);
                    try {
                        await extractVideoThumbnail(inputVideoPath, thumbPath);
                        if (fs.existsSync(thumbPath)) {
                            // อัปโหลด frame thumbnail ผ่าน thumbnailQueue (รองรับ Bunny CDN)
                            thumbnailQueue.addJob({
                                filesForThumbnail: [thumbPath],
                                thumbLocalPath: path.join(outputDir, `thumb_${videoId}.webp`),
                                thumbFilename: `thumb_${videoId}.webp`,
                                thumbTargetId: videoId,
                                isThaiMhung: false,
                                incidentId: null,
                                videoId,
                                userId,
                                localApiUrl,
                                baseDir,
                            }).catch(e => console.warn('[VideoThumb] Queue add failed:', e.message));
                        }
                    } catch (thumbErr) {
                        console.warn(`[VideoThumb] Frame extraction failed (non-critical): ${thumbErr.message}`);
                    }

                    // Determine if we should keep the HLS files locally (if not using Bunny CDN)
                    const isLocalUrl = finalUrl.startsWith(localApiUrl) || finalUrl.includes('localhost') || !process.env.BUNNY_CDN_URL || process.env.BUNNY_CDN_URL === 'https://your-pull-zone.b-cdn.net';
                    const keepOutputDir = isLocalUrl;

                    cleanup(filePath, outputDir, keepOutputDir);
                    // Cleanup blurred file if it was created
                    if (inputVideoPath !== filePath && fs.existsSync(inputVideoPath)) {
                        fs.unlinkSync(inputVideoPath);
                    }
                    if (tempTextImgPath && fs.existsSync(tempTextImgPath)) fs.unlinkSync(tempTextImgPath);
                    if (tempForensicImgPath && fs.existsSync(tempForensicImgPath)) fs.unlinkSync(tempForensicImgPath);
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
                if (tempTextImgPath && fs.existsSync(tempTextImgPath)) fs.unlinkSync(tempTextImgPath);
                if (tempForensicImgPath && fs.existsSync(tempForensicImgPath)) fs.unlinkSync(tempForensicImgPath);
                reject(err);
            })
            .save(hlsPath);
    });
}, {
    connection,
    concurrency: queueOptions.concurrency,
});

/**
 * Extract a single thumbnail frame from video using FFmpeg
 * Bug #3 Fix: ดึง Frame จากวิดีโอเพื่อใช้เป็น Thumbnail ของการ์ดยอดนิยม
 * @param {string} videoPath - Path ของวิดีโอต้นฉบับ (ก่อนหรือหลัง HLS)
 * @param {string} outputPath - Path เซฟรูป Thumbnail (.jpg)
 * @returns {Promise<void>}
 */
function extractVideoThumbnail(videoPath, outputPath) {
    return new Promise((resolve, reject) => {
        if (!fs.existsSync(videoPath)) {
            return reject(new Error(`Video file not found: ${videoPath}`));
        }
        ffmpeg(videoPath)
            .screenshots({
                count: 1,
                timemarks: ['00:00:01'], // ดึง Frame ที่วินาทีที่ 1
                size: '400x?',           // กว้าง 400px ความสูงปรับตามอัตราส่วน
                folder: require('path').dirname(outputPath),
                filename: require('path').basename(outputPath),
            })
            .on('end', () => resolve())
            .on('error', (err) => reject(err));
    });
}

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

async function shutdown() {
    await Promise.allSettled([
        worker.close(),
        videoQueue.close(),
    ]);
}

module.exports = {
    addToQueue,
    init,
    videoQueue,
    worker,
    shutdown
};
