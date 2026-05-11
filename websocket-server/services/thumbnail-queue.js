/**
 * Thumbnail Queue Service
 * 
 * Recommendation #8: Async Queue สำหรับ Thumbnail Generation
 * แยก thumbnail generation ออกจาก HTTP Request-Response cycle
 * ด้วย BullMQ — รองรับ Load สูงโดยไม่ block server
 * 
 * Flow:
 * POST /upload-photos → Respond 200 → addJob() → Worker generates → DB update → WebSocket push
 */

const { Queue, Worker } = require('bullmq');
const path = require('path');
const fs = require('fs');
const socketService = require('./socket-service');
const { generateThumbnail, uploadThumbnailToBunny } = require('./thumbnail-service');
const watermarkService = require('./watermark-service');

// ✅ Redis connection (ใช้ ENV ตามที่กำหนดใน .env)
const connection = {
    url: process.env.REDIS_URL || 'redis://localhost:6379',
};

const QUEUE_NAME = 'thumbnail-generation';

// Database pool reference (inject จาก video.js ผ่าน init)
let dbPool = null;

/**
 * Initialize Thumbnail Queue with database pool
 * @param {object} pool - PostgreSQL pool
 */
function init(pool) {
    dbPool = pool;
    console.log('✅ Thumbnail Queue initialized');
}

// ─── Queue ─────────────────────────────────────────────────
const thumbnailQueue = new Queue(QUEUE_NAME, {
    connection,
    defaultJobOptions: {
        attempts: 3,                         // Retry สูงสุด 3 ครั้ง
        backoff: { type: 'exponential', delay: 2000 }, // Retry หลัง 2s, 4s, 8s
        removeOnComplete: { count: 100 },    // เก็บ log งานสำเร็จ 100 ชิ้นสุดท้าย
        removeOnFail: { count: 200 },        // เก็บ log งานล้มเหลว 200 ชิ้นสุดท้าย
    },
});

/**
 * Add a thumbnail generation job to the queue
 * @param {object} jobData
 */
async function addJob(jobData) {
    const job = await thumbnailQueue.add('generate', jobData, {
        priority: 2, // ความสำคัญรองจาก Video Transcode
    });
    console.log(`[ThumbnailQueue] Job ${job.id} added for target: ${jobData.thumbTargetId}`);
    return job;
}

// ─── Worker ────────────────────────────────────────────────
const worker = new Worker(QUEUE_NAME, async (job) => {
    const {
        filesForThumbnail,
        thumbLocalPath,
        thumbFilename,
        thumbTargetId,
        isThaiMhung,
        incidentId,
        videoId,
        userId,
        localApiUrl,
        baseDir,
    } = job.data;

    console.log(`[ThumbnailWorker] Processing job ${job.id} for ${thumbTargetId} (${filesForThumbnail.length} photos)`);

    // ตรวจสอบว่าไฟล์ input ยังมีอยู่
    const existingFiles = filesForThumbnail.filter(f => fs.existsSync(f));
    if (existingFiles.length === 0) {
        throw new Error(`No input files exist for ${thumbTargetId}`);
    }

    // ✅ Step 1: Generate WebP Thumbnail
    const thumbResult = await generateThumbnail(existingFiles, thumbLocalPath);
    if (!thumbResult.success || !fs.existsSync(thumbLocalPath)) {
        throw new Error(thumbResult.error || 'Thumbnail file not created');
    }

    // ✅ Step 1.5: Apply Watermark to the generated Thumbnail
    if (dbPool) {
        try {
            const wmRes = await dbPool.query('SELECT * FROM watermark_configs WHERE id = 1 AND is_enabled = true');
            if (wmRes.rows.length > 0) {
                const watermarkConfig = wmRes.rows[0];
                const wmPath = thumbLocalPath.replace('.webp', '_wm.webp');
                
                const wmResult = await watermarkService.applyImageWatermark(
                    thumbLocalPath, 
                    wmPath, 
                    watermarkConfig, 
                    isThaiMhung && incidentId ? incidentId : videoId, 
                    userId
                );
                
                if (wmResult.success) {
                    fs.unlinkSync(thumbLocalPath); // delete original un-watermarked
                    fs.renameSync(wmPath, thumbLocalPath); // rename watermarked back to original name
                }
            }
        } catch (e) {
            console.warn('[ThumbnailWorker] Failed to apply watermark:', e.message);
        }
    }

    // ✅ Step 2: Try Bunny.net CDN Upload (Recommendation #9 — optional)
    let finalThumbnailUrl = null;
    const remoteKey = isThaiMhung
        ? `thumbnails/${incidentId}/${thumbFilename}`
        : `thumbnails/${videoId}/${thumbFilename}`;

    const cdnUrl = await uploadThumbnailToBunny(thumbLocalPath, remoteKey);
    if (cdnUrl) {
        // ✅ ได้ CDN URL แล้ว — ใช้เส้นนี้แทน Local
        finalThumbnailUrl = cdnUrl;
        console.log(`[ThumbnailWorker] ✅ Using Bunny CDN URL: ${cdnUrl}`);
    } else {
    // ✅ Fallback: บันทึกใน uploads/thumbnails/ (persistent — ไม่ถูก cleanup เหมือน temp/videos)
    // สร้าง directory ถ้ายังไม่มี
    const uploadsDir = path.join(__dirname, '../uploads/thumbnails');
    const targetId = isThaiMhung && incidentId ? incidentId : videoId;
    const persistDir = path.join(uploadsDir, targetId);
    if (!fs.existsSync(persistDir)) {
        fs.mkdirSync(persistDir, { recursive: true });
    }

    // Copy thumbnail ไปยัง persistent location
    const persistPath = path.join(persistDir, thumbFilename);
    try {
        fs.copyFileSync(thumbLocalPath, persistPath);
        console.log(`[ThumbnailWorker] 📁 Copied thumbnail to persistent: ${persistPath}`);
    } catch (copyErr) {
        console.warn(`[ThumbnailWorker] ⚠️ Could not copy to persistent dir: ${copyErr.message}`);
    }

    // ✅ ใช้ /uploads/thumbnails/ URL (persistent, ไม่โดน cleanup)
    finalThumbnailUrl = `${localApiUrl}/uploads/thumbnails/${targetId}/${thumbFilename}?t=${Date.now()}`;
    console.log(`[ThumbnailWorker] Using persistent local URL: ${finalThumbnailUrl}`);
    }

    // ✅ Step 3: อัปเดต DB — ใส่ thumbnail_url ให้กับ incident หลัก
    if (dbPool) {
        try {
            // อัปเดต thumbnail ของ incident หลัก (ถ้าเป็น Thai Mhung)
            if (isThaiMhung && incidentId) {
                await dbPool.query(
                    'UPDATE videos SET thumbnail_url = $1 WHERE id = $2',
                    [finalThumbnailUrl, incidentId]
                );
                console.log(`[ThumbnailWorker] ✅ Updated thumbnail for incident ${incidentId}`);
            }
            // อัปเดต thumbnail ของ video record นี้ด้วย (ถ้าไม่ใช่ Thai Mhung หรือเป็น video record ใหม่)
            if (!isThaiMhung) {
                await dbPool.query(
                    'UPDATE videos SET thumbnail_url = $1 WHERE id = $2',
                    [finalThumbnailUrl, videoId]
                );
                console.log(`[ThumbnailWorker] ✅ Updated thumbnail for video ${videoId}`);
            }
        } catch (dbErr) {
            console.error('[ThumbnailWorker] DB update failed:', dbErr.message);
            throw dbErr; // Re-throw เพื่อให้ BullMQ retry
        }
    }

    // ✅ Step 4: WebSocket push — แจ้ง TrendingPanel ให้รีเฟรช (Recommendation #7)
    const targetId = isThaiMhung && incidentId ? incidentId : videoId;
    socketService.broadcastThumbnailUpdate(targetId, {
        thumbnailUrl: finalThumbnailUrl,
    });

    return { success: true, thumbnailUrl: finalThumbnailUrl, targetId };

}, {
    connection,
    concurrency: 4, // generate thumbnail ได้สูงสุด 4 งานพร้อมกัน (เบากว่า video transcode)
});

// ─── Worker Event Handlers ──────────────────────────────────
worker.on('completed', (job, result) => {
    console.log(`[ThumbnailWorker] ✅ Job ${job.id} completed — ${result.thumbnailUrl}`);
});

worker.on('failed', (job, err) => {
    console.error(`[ThumbnailWorker] ❌ Job ${job?.id} failed (attempt ${job?.attemptsMade}): ${err.message}`);
});

worker.on('error', (err) => {
    console.error('[ThumbnailWorker] Worker error:', err.message);
});

module.exports = { addJob, init };
