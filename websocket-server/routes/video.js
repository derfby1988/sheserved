const express = require('express');
const router = express.Router();
const multer = require('multer');
const path = require('path');
const fs = require('fs');
const { v4: uuidv4 } = require('uuid');
const videoService = require('../services/video-service');
const socketService = require('../services/socket-service');
const faceBlurService = require('../services/face-blur-service');
const { generateThumbnail, uploadThumbnailToBunny } = require('../services/thumbnail-service');
const thumbnailQueue = require('../services/thumbnail-queue');
const watermarkService = require('../services/watermark-service');
const { assertUuid, assertUuidOrNull, safeJoin, safeExtension, sanitizeCacheKey } = require('../utils/safe-path');
const {
    strictRateLimiter,
    rateLimiter,
    idempotencyMiddleware,
    duplicateCheckMiddleware,
    cacheAside,
    invalidateCachePattern,
    TTL,
    requireAuth,
    uploadQuotaLimiter,
    ipLimiter,
} = require('../middleware');

// ✅ Upload endpoints: 30 req/min — ลดกว่า strict แต่ยังป้องกัน abuse
const uploadRateLimiter = rateLimiter({ maxRequests: 30, windowSec: 60, keyPrefix: 'rate:upload' });

// Configure Multer for file upload
const storage = multer.diskStorage({
    destination: async (req, file, cb) => {
        const destDir = process.env.TEMP_VIDEO_PATH || path.join(__dirname, '../temp/videos');
        try {
            await fs.promises.mkdir(destDir, { recursive: true });
            cb(null, destDir);
        } catch (err) {
            cb(err);
        }
    },
    filename: (req, file, cb) => {
        try {
            const ext = safeExtension(file.originalname, 'video');
            cb(null, `${uuidv4()}${ext}`);
        } catch (err) {
            cb(err);
        }
    }
});

const MAX_VIDEO_BYTES = 20 * 1024 * 1024; // 20MB — ตรงกับ business rule
const MAX_PHOTO_BYTES = 10 * 1024 * 1024; // 10MB สำหรับรูป
const MAX_GPS_TRACKS = 5000; // R3: จำกัด GPS tracks ต่อ request
const MAX_PAGINATION_LIMIT = 100; // R2: เพดาน limit
const MAX_PAGINATION_PAGE = 1000; // R2: เพดาน page

const upload = multer({
    storage,
    limits: { fileSize: MAX_VIDEO_BYTES, files: 5 }, // R1: ตรงกับ business limit ตั้งแต่ multer
});

// R1: cleanup ไฟล์ที่ค้างเมื่อ reject หรือ error
function cleanupUploadedFile(file) {
    if (file && file.path) {
        try { fs.unlinkSync(file.path); } catch (_) {}
    }
}
function cleanupUploadedFiles(files) {
    if (Array.isArray(files)) {
        for (const f of files) { cleanupUploadedFile(f); }
    } else {
        cleanupUploadedFile(files);
    }
}

// R2: clamp pagination ใช้ทุก endpoint
function clampPagination(req) {
    const page = Math.min(Math.max(parseInt(req.query.page) || 1, 1), MAX_PAGINATION_PAGE);
    const limit = Math.min(Math.max(parseInt(req.query.limit) || 20, 1), MAX_PAGINATION_LIMIT);
    return { page, limit, offset: (page - 1) * limit };
}

// R3: bulk insert GPS tracks แทน loop query แบบเดิม
async function bulkInsertGpsTracks(pool, videoId, tracks) {
    if (!Array.isArray(tracks) || tracks.length === 0) return 0;
    if (tracks.length > MAX_GPS_TRACKS) {
        const err = new Error(`GPS tracks เกินจำนวนที่กำหนด (สูงสุด ${MAX_GPS_TRACKS} จุด)`);
        err.code = 'TOO_MANY_TRACKS';
        err.statusCode = 413;
        throw err;
    }
    const lats = [], lngs = [], offsets = [];
    for (const t of tracks) {
        lats.push(parseFloat(t.latitude));
        lngs.push(parseFloat(t.longitude));
        offsets.push(parseInt(t.timestampOffset) || 0);
    }
    await pool.query(
        `INSERT INTO video_gps_tracks (video_id, latitude, longitude, timestamp_offset)
         SELECT $1, * FROM UNNEST($2::float[], $3::float[], $4::int[])`,
        [videoId, lats, lngs, offsets]
    );
    return tracks.length;
}

// Phase 1 Middleware: Redis-based rate limiting, idempotency, and duplicate check
// are now handled by the shared middleware layer instead of in-memory Maps.

module.exports = (pool) => {
    // Initialize video service with the pool
    videoService.init(pool);

    // Get videos List by type (Local API fallback for gallery/live stream)
    router.get('/', ipLimiter, async (req, res) => {
        try {
            const { type, category_id } = req.query;
            const cacheKey = `video:list:${type || 'all'}:${category_id || 'all'}:v2`;

            const data = await cacheAside(cacheKey, async () => {
                let query = 'SELECT id, user_id, title, description, type, category_id, donation_request_id, status, thumbnail_url, bunny_url, photo_urls, address, road, soi, alley, village, created_at, updated_at FROM videos WHERE 1=1';
                let params = [];

                if (type) {
                    params.push(type);
                    query += ` AND type = $${params.length}`;
                }
                if (category_id) {
                    params.push(category_id);
                    query += ` AND category_id = $${params.length}`;
                }

                query += ' ORDER BY created_at ASC LIMIT 50';

                const result = await pool.query(query, params);
                return result.rows;
            }, TTL.DEFAULT);

            res.json(data);
        } catch (error) {
            console.error('[API] Error fetching videos list:', error);
            res.status(500).json({ error: 'Failed to fetch videos' });
        }
    });

    // Upload video
    router.post('/upload', requireAuth, idempotencyMiddleware, uploadRateLimiter, uploadQuotaLimiter, upload.single('video'), duplicateCheckMiddleware('video-upload', 5), async (req, res) => {
        try {
            const { title, description, type, donationRequestId, address, road, soi, alley, village } = req.body;
            const userId = req.userId;
            const file = req.file;

            if (!file) {
                return res.status(400).json({ error: 'No video file provided' });
            }

            // 1. File Size Validation (Enforced by Multer limits as well, but double check)
            if (file.size > MAX_VIDEO_BYTES) {
                cleanupUploadedFile(file); // R1: cleanup เมื่อ reject
                return res.status(413).json({
                    error: `File too large. Max allowed: ${MAX_VIDEO_BYTES / (1024 * 1024)}MB`
                });
            }

            const { categoryId, gpsTracks } = req.body;

            if (!userId) {
                return res.status(401).json({ error: 'Authentication required' });
            }

            // 1. Insert into Database
            const videoId = uuidv4();
            const result = await pool.query(
                `INSERT INTO videos (id, user_id, title, description, type, category_id, donation_request_id, status, address, road, soi, alley, village)
                 VALUES ($1, $2, $3, $4, $5, $6, $7, 'processing', $8, $9, $10, $11, $12) RETURNING id`,
                [videoId, userId, title, description || '', type || 'normal', categoryId || null, donationRequestId || null, address || null, road || null, soi || null, alley || null, village || null]
            );

            const videoRecord = result.rows[0];

            // 2. Handle GPS Tracks if provided
            if (gpsTracks) {
                try {
                    const tracks = JSON.parse(req.body.gpsTracks);
                    if (Array.isArray(tracks)) {
                        for (const track of tracks) {
                            await pool.query(
                                `INSERT INTO video_gps_tracks (video_id, latitude, longitude, timestamp_offset)
                                 VALUES ($1, $2, $3, $4)`,
                                [videoId, track.latitude, track.longitude, track.timestampOffset || 0]
                            );
                        }
                        console.log(`[DB] Inserted ${tracks.length} GPS tracks for video ${videoId}`);
                    }
                } catch (e) {
                    console.error('[DB] Failed to parse or insert GPS tracks:', e.message);
                }
            }

            // 3. Add to Queue for processing
            await videoService.addToQueue({
                id: videoId,
                userId,
                filePath: file.path,
                title: title,
                type: type || 'normal'
            });

            res.json({
                message: 'Video upload successful, processing started',
                video: videoRecord
            });
        } catch (error) {
            console.error('Upload Error:', error);
            if (req.file) cleanupUploadedFile(req.file); // R1: cleanup เมื่อ error
            res.status(500).json({ error: 'Failed to upload video' });
        }
    });

    // Upload multiple photos
    // รองรับทั้ง Emergency Photo (max 5) และ Thai Mhung Photo (max 3)
    // โดย enforce ตาม isThaiMhung flag ที่ส่งมาจาก Flutter
    router.post('/upload-photos', requireAuth, idempotencyMiddleware, uploadRateLimiter, uploadQuotaLimiter, upload.array('photos', 5), duplicateCheckMiddleware('upload-photos', 5), async (req, res) => {
        try {
            const userIdFromRequest = req.userId;
            const files = req.files;

            if (!files || files.length === 0) {
                return res.status(400).json({ error: 'No photos provided' });
            }

            // ✅ Quota แยกตาม Mode
            const isThaiMhung = req.body.isThaiMhung === 'true';
            const MAX_THAI_MHUNG_PHOTOS = 3;
            const MAX_EMERGENCY_PHOTOS = 5;
            const quota = isThaiMhung ? MAX_THAI_MHUNG_PHOTOS : MAX_EMERGENCY_PHOTOS;
            const modeName = isThaiMhung ? 'Thai Mhung' : 'Emergency';

            if (files.length > quota) {
                cleanupUploadedFiles(files); // R1: cleanup เมื่อ reject
                return res.status(400).json({
                    error: `${modeName} mode allows maximum ${quota} photos per upload`
                });
            }

            const { title, description, categoryId, donationRequestId, gpsTracks, incidentId } = req.body;
            const userId = req.userId;

            // ✅ Option A: validate incidentId เป็น UUID ก่อนใช้กับ filesystem
            const validatedIncidentId = assertUuidOrNull(incidentId, 'incidentId');

            // ✅ ใช้ type ตาม mode จริง แทนที่จะ hardcode 'emergency_photo' เสมอ
            const videoType = isThaiMhung ? 'thai_mhung_photo' : 'emergency_photo';

            // 2. Insert into Database first to get the videoId
            const videoId = uuidv4();
            
            // ✅ Organize files into subfolders — ใช้ safeJoin เพื่อ containment check
            const baseDir = process.env.TEMP_VIDEO_PATH || path.join(__dirname, '../temp/videos');
            
            // Structure: 
            // - Regular: baseDir/[videoId]/photos/
            // - Thai Mhung: baseDir/[incidentId]/thaimhung/[videoId]/
            let reportDir;
            if (isThaiMhung && validatedIncidentId) {
                reportDir = safeJoin(baseDir, validatedIncidentId, 'thaimhung', videoId);
            } else {
                reportDir = safeJoin(baseDir, videoId);
            }

            if (!fs.existsSync(reportDir)) {
                fs.mkdirSync(reportDir, { recursive: true });
            }

            // Fetch Watermark Config once
            let watermarkConfig = null;
            try {
                const wmRes = await pool.query('SELECT * FROM watermark_configs WHERE id = 1 AND is_enabled = true');
                if (wmRes.rows.length > 0) watermarkConfig = wmRes.rows[0];
            } catch (e) {
                console.warn('[Watermark] Failed to fetch config for photos:', e.message);
            }

            const photoUrls = [];
            const originalPaths = []; // Phase 6.12: เก็บ path ต้นฉบับเพื่อ blur แบบ background
            const localApiUrl = process.env.LOCAL_API_URL || 'http://localhost:3000';
            
            for (const file of files) {
                const newPath = path.join(reportDir, file.filename);
                // Move file from root destDir to reportDir
                fs.renameSync(file.path, newPath);
                originalPaths.push(newPath);

                // Phase 6.12: ยังไม่ blur/watermark ตอนนี้ — ทำ background หลัง respond
                const finalFilename = path.basename(newPath);
                let relativePath;
                if (isThaiMhung && validatedIncidentId) {
                    relativePath = `${validatedIncidentId}/thaimhung/${videoId}/${finalFilename}`;
                } else {
                    relativePath = `${videoId}/${finalFilename}`;
                }
                const url = `${localApiUrl}/temp/videos/${relativePath}`;
                photoUrls.push(url);
                
                // เก็บ local path เพื่อใช้ทำ Thumbnail (ใช้ original ก่อน blur)
                if (!req.localFilePaths) req.localFilePaths = [];
                req.localFilePaths.push(newPath);
            }

            // ✅ Set first photo as bunny_url for basic preview support
            const firstPhotoUrl = photoUrls.length > 0 ? photoUrls[0] : null;

            // ✅ สร้าง Thumbnail (Animated WebP) โดยรวมภาพจากทุกๆ การอัปโหลดของไทยมุง
            let thumbnailUrl = firstPhotoUrl;
            let filesForThumbnail = [];

            if (isThaiMhung && validatedIncidentId) {
                // รวบรวมภาพล่าสุด 5 ภาพจากทุกเหตุการณ์ย่อยของไทยมุงใน incident นี้
                const thaimhungBaseDir = safeJoin(baseDir, validatedIncidentId, 'thaimhung');
                if (fs.existsSync(thaimhungBaseDir)) {
                    let allPhotos = [];
                    const videoDirs = fs.readdirSync(thaimhungBaseDir);
                    for (const vDir of videoDirs) {
                        const vDirPath = path.join(thaimhungBaseDir, vDir);
                        if (fs.statSync(vDirPath).isDirectory()) {
                            const photoFiles = fs.readdirSync(vDirPath).filter(f => !f.startsWith('thumb_') && (f.endsWith('.jpg') || f.endsWith('.png') || f.endsWith('.webp') || f.endsWith('.jpeg')));
                            for (const pf of photoFiles) {
                                const pfPath = path.join(vDirPath, pf);
                                allPhotos.push({
                                    path: pfPath,
                                    mtime: fs.statSync(pfPath).mtime.getTime()
                                });
                            }
                        }
                    }
                    // เรียงจากใหม่ไปเก่า และดึงมาสูงสุด 5 ภาพ
                    allPhotos.sort((a, b) => b.mtime - a.mtime);
                    filesForThumbnail = allPhotos.slice(0, 5).map(p => p.path);
                }
            } else if (req.localFilePaths) {
                filesForThumbnail = req.localFilePaths;
            }

            if (filesForThumbnail.length > 0) {
                // ✅ Recommendation #8: ใช้ Async Queue แทนการ generate แบบ Synchronous
                // Respond ไปยัง Client ก่อน จากนั้น Worker จะ generate thumbnail แล้ว push ผ่าน WebSocket
                const thumbFilename = `thumb_${isThaiMhung ? validatedIncidentId : videoId}.webp`;
                const destDirForThumb = isThaiMhung ? safeJoin(baseDir, validatedIncidentId) : reportDir;
                const thumbLocalPath = path.join(destDirForThumb, thumbFilename);
                const thumbTargetId = isThaiMhung ? validatedIncidentId : videoId;

                if (!fs.existsSync(destDirForThumb)) {
                    fs.mkdirSync(destDirForThumb, { recursive: true });
                }

                // ✅ Set placeholder URL ทันที (ใช้รูปแรกชั่วคราว) เพื่อให้ Client มีรูปแสดง
                // จะถูกอัปเดตเป็น thumbnail จริงหลัง Worker เสร็จ
                thumbnailUrl = firstPhotoUrl;

                // ✅ Push thumbnail generation job ไปยัง Queue (Non-blocking)
                thumbnailQueue.addJob({
                    filesForThumbnail,
                    thumbLocalPath,
                    thumbFilename,
                    thumbTargetId,
                    isThaiMhung: isThaiMhung && !!validatedIncidentId,
                    incidentId: validatedIncidentId || null,
                    videoId,
                    userId: userId || userIdFromRequest,
                    localApiUrl,
                    baseDir,
                }).catch(err => {
                    console.error('[ThumbnailQueue] Failed to add job:', err.message);
                });
            }

            const result = await pool.query(
                `INSERT INTO videos (id, user_id, title, description, type, category_id, donation_request_id, photo_urls, bunny_url, thumbnail_url, incident_id, status)
                 VALUES ($1, $2, $3, $4, $5, $6, $7, $8::jsonb, $9, $10, $11, 'processing') RETURNING *`,
                [videoId, userId, title, description || '', videoType, categoryId || null, donationRequestId || null, JSON.stringify(photoUrls), firstPhotoUrl, thumbnailUrl, validatedIncidentId || null]
            );

            const videoRecord = result.rows[0];

            // ✅ อัปเดต Thumbnail ให้กับเหตุการณ์หลัก (Incident) โดยอัปเดตเสมอเพื่ออัปเดตภาพ Animated ล่าสุด
            if (isThaiMhung && validatedIncidentId && thumbnailUrl) {
                try {
                    await pool.query(
                        `UPDATE videos SET thumbnail_url = $1 WHERE id = $2`,
                        [thumbnailUrl, validatedIncidentId]
                    );
                } catch (updateErr) {
                    console.error('[Thumbnail] Failed to update main incident thumbnail:', updateErr);
                }
            }

            // 3. Handle GPS Tracks if provided — R3: bulk insert แทน loop query
            if (gpsTracks) {
                try {
                    const tracks = JSON.parse(gpsTracks);
                    if (Array.isArray(tracks)) {
                        await bulkInsertGpsTracks(pool, videoId, tracks);
                    }
                } catch (gpsError) {
                    console.error('Error inserting GPS tracks for photos:', gpsError);
                    if (gpsError.code === 'TOO_MANY_TRACKS') {
                        cleanupUploadedFiles(files); // R1: cleanup เมื่อ reject
                        return res.status(413).json({ error: gpsError.message });
                    }
                }
            }

            // 4. Mark as Ready ทันที
            await pool.query('UPDATE videos SET status = $1, progress = 100 WHERE id = $2', ['ready', videoId]);
            socketService.sendStatus(userId || userIdFromRequest, videoId, 'ready', { progress: 100 });

            // Phase 6.12: Insert thai_mhung_photos with blur_status='blurring' and respond immediately
            const thaiMhungPhotoIds = [];
            console.log(`[ThaiMhung] isThaiMhung=${isThaiMhung}, incidentId=${validatedIncidentId}, videoId=${videoId}`);
            if (isThaiMhung && validatedIncidentId) {
                const latestTrack = gpsTracks ? (() => { try { const t = JSON.parse(gpsTracks); return Array.isArray(t) && t.length > 0 ? t[t.length - 1] : null; } catch(e) { return null; } })() : null;
                for (const url of photoUrls) {
                    try {
                        // ✅ Insert with incidentId (not videoId) so gallery query can find it
                        console.log(`[ThaiMhung] Inserting photo: incidentId=${validatedIncidentId}, url=${url}`);
                        const photoRes = await pool.query(
                            `INSERT INTO thai_mhung_photos (video_id, user_id, photo_url, latitude, longitude, blur_status)
                             VALUES ($1, $2, $3, $4, $5, $6) RETURNING id`,
                            [validatedIncidentId, userId || userIdFromRequest, url, latestTrack ? latestTrack.latitude : null, latestTrack ? latestTrack.longitude : null, 'blurring']
                        );
                        const photoId = photoRes.rows[0].id;
                        thaiMhungPhotoIds.push(photoId);
                        console.log(`[ThaiMhung] Inserted photo id=${photoId} for incidentId=${validatedIncidentId}`);
                        socketService.broadcastNewThaiMhungPhoto(validatedIncidentId, {
                            photo_url: url,
                            user_id: userId || userIdFromRequest,
                            latitude: latestTrack ? latestTrack.latitude : null,
                            longitude: latestTrack ? latestTrack.longitude : null,
                            created_at: new Date().toISOString(),
                            video_id: validatedIncidentId,
                            blur_status: 'blurring',
                            photo_id: photoId,
                        });
                    } catch (insertErr) {
                        console.error('[ThaiMhung] Failed to insert thai_mhung_photos:', insertErr);
                    }
                }
                // ✅ Invalidate gallery cache so fresh data appears immediately
                invalidateCachePattern(`video:gallery:${sanitizeCacheKey(validatedIncidentId)}:*`);
            }

            // 5. ✅ Respond immediately — ไม่รอ blur/watermark
            res.json({
                message: `${modeName} photos upload successful (${files.length}/${quota})`,
                video: { ...videoRecord, photo_urls: photoUrls },
                photo_urls: photoUrls,
                incidentId: validatedIncidentId,
                status: isThaiMhung ? 'blurring' : 'ready',
                photoIds: thaiMhungPhotoIds,
            });

            // Phase 6.12: Background blur + watermark (fire-and-forget)
            if (isThaiMhung && validatedIncidentId && originalPaths.length > 0) {
                (async () => {
                    const blurredUrls = [];
                    for (let i = 0; i < originalPaths.length; i++) {
                        const originalPath = originalPaths[i];
                        const photoId = thaiMhungPhotoIds[i];
                        if (!photoId) continue;

                        let finalFilePath = originalPath;

                        // 1. Face Blur
                        const ext = path.extname(originalPath);
                        const anonFilename = `${path.basename(originalPath, ext)}_anon${ext}`;
                        const anonPath = path.join(reportDir, anonFilename);
                        const blurResult = await faceBlurService.blurFacesInImage(originalPath, anonPath);
                        if (blurResult.success) {
                            finalFilePath = anonPath;
                            try { fs.unlinkSync(originalPath); } catch (_) {}
                        } else {
                            finalFilePath = blurResult.outputPath || originalPath;
                        }

                        // 2. Watermark
                        if (watermarkConfig) {
                            const wmFilename = `${path.basename(finalFilePath, ext)}_wm${ext}`;
                            const wmPath = path.join(reportDir, wmFilename);
                            const wmResult = await watermarkService.applyImageWatermark(
                                finalFilePath, wmPath, watermarkConfig, validatedIncidentId || videoId, userId || userIdFromRequest
                            );
                            if (wmResult.success) {
                                if (finalFilePath !== originalPath) {
                                    try { fs.unlinkSync(finalFilePath); } catch (_) {}
                                }
                                finalFilePath = wmPath;
                            }
                        }

                        // 3. Build blurred URL
                        const finalFilename = path.basename(finalFilePath);
                        let relativePath;
                        if (isThaiMhung && validatedIncidentId) {
                            relativePath = `${validatedIncidentId}/thaimhung/${videoId}/${finalFilename}`;
                        } else {
                            relativePath = `${videoId}/${finalFilename}`;
                        }
                        const blurredUrl = `${localApiUrl}/temp/videos/${relativePath}`;
                        blurredUrls.push(blurredUrl);

                        // 4. Update thai_mhung_photos
                        try {
                            await pool.query(
                                `UPDATE thai_mhung_photos SET photo_url = $1, blur_status = $2 WHERE id = $3`,
                                [blurredUrl, 'completed', photoId]
                            );
                        } catch (updateErr) {
                            console.error('[ThaiMhung] Failed to update photo_url after blur:', updateErr);
                        }

                        // 5. Broadcast blur complete
                        socketService.broadcastPhotoBlurComplete(validatedIncidentId, {
                            photoId: photoId,
                            url: blurredUrl,
                            blurStatus: 'completed',
                        });
                    }

                    // 6. Update videos.photo_urls with blurred URLs
                    if (blurredUrls.length > 0) {
                        try {
                            await pool.query(
                                `UPDATE videos SET photo_urls = $1::jsonb WHERE id = $2`,
                                [JSON.stringify(blurredUrls), videoId]
                            );
                        } catch (updateErr) {
                            console.error('[ThaiMhung] Failed to update videos.photo_urls after blur:', updateErr);
                        }
                    }

                    // ✅ Invalidate gallery cache so blurred URLs appear
                    if (validatedIncidentId) {
                        invalidateCachePattern(`video:gallery:${sanitizeCacheKey(validatedIncidentId)}:*`);
                    }
                })().catch(err => {
                    console.error('[ThaiMhung] Background blur error:', err);
                });
            }
        } catch (error) {
            console.error('Upload Error:', error);
            if (req.files) cleanupUploadedFiles(req.files); // R1: cleanup เมื่อ error
            res.status(500).json({ error: 'Failed to upload photos' });
        }
    });


    // Get emergency videos list (trending) - with user info & interaction counts
    router.get('/emergency/list', ipLimiter, async (req, res) => {
        const { page, limit, offset } = clampPagination(req);
        const cacheKey = `video:emergency:list:v2:${page}:${limit}`;

        console.log(`[API] Fetching emergency videos list (page: ${page}, limit: ${limit})`);
        try {
            const data = await cacheAside(cacheKey, async () => {
                // ✅ Optimization for Massive Scale:
                // 1. Used cached_view_count/cached_like_count instead of LEFT JOIN COUNT(*) over millions of records
                // 2. Added LIMIT and OFFSET for infinite scrolling
                const result = await pool.query(`
                    SELECT v.id, v.user_id, v.title, v.description, v.type, v.category_id, v.status, v.thumbnail_url, v.bunny_url, v.photo_urls, v.created_at,
                        COALESCE(u.first_name || ' ' || u.last_name, u.username, 'ผู้ใช้งาน') AS user_name,
                        u.profile_image_url AS user_avatar,
                        dc.name AS category_name,
                        v.cached_view_count AS viewer_count,
                        v.cached_like_count AS like_count,
                        gt.latitude,
                        gt.longitude,
                        v.address, v.road, v.soi, v.alley, v.village
                    FROM videos v
                    LEFT JOIN users u ON u.id = v.user_id
                    LEFT JOIN donation_categories dc ON dc.id::text = v.category_id::text
                    LEFT JOIN (
                        SELECT DISTINCT ON (video_id) video_id, latitude, longitude
                        FROM video_gps_tracks
                        ORDER BY video_id, timestamp_offset ASC
                    ) gt ON gt.video_id = v.id
                    WHERE v.type IN ('emergency', 'emergency_photo')
                    ORDER BY v.created_at DESC
                    LIMIT $1 OFFSET $2
                `, [limit, offset]);
                return result.rows;
            }, TTL.DEFAULT);

            res.json(data);
        } catch (error) {
            console.error('Error fetching emergency videos:', error.message);
            res.status(500).json({ error: 'Failed to fetch emergency videos' });
        }
    });

    // Accept incident
    router.post('/:id/accept', requireAuth, strictRateLimiter, duplicateCheckMiddleware('accept-incident', 10), async (req, res) => {
        try {
            const { id } = req.params;
            const responderId = req.userId;
            const { latitude, longitude } = req.body;

            if (!responderId) {
                return res.status(401).json({ error: 'Authentication required' });
            }

            // ✅ ตรวจสอบวิดีโอมีอยู่ใน Local DB ก่อน
            const videoCheck = await pool.query('SELECT id FROM videos WHERE id = $1', [id]);
            if (videoCheck.rows.length === 0) {
                return res.status(404).json({ error: 'Video not found in local database' });
            }

            // ✅ Upsert — ถ้ารับงานซ้ำให้อัปเดตสถานะแทนที่จะ error
            const result = await pool.query(
                `INSERT INTO incident_responses (video_id, volunteer_id, volunteer_start_lat, volunteer_start_lng, status)
                 VALUES ($1, $2, $3, $4, 'en_route')
                 ON CONFLICT (video_id, volunteer_id) DO UPDATE
                   SET status = 'en_route',
                       volunteer_start_lat = EXCLUDED.volunteer_start_lat,
                       volunteer_start_lng = EXCLUDED.volunteer_start_lng,
                       updated_at = CURRENT_TIMESTAMP
                 RETURNING id`,
                [id, responderId, latitude || null, longitude || null]
            );

            res.json({
                message: 'Incident accepted',
                responseId: result.rows[0].id
            });
        } catch (error) {
            console.error('Accept Incident Error:', error.message);
            res.status(500).json({ error: 'Failed to accept incident', detail: error.message });
        }
    });

    // Get active responders for an incident (Local DB is the source of truth
    // for accept/status updates — see POST /:id/accept and rescue-status-update
    // socket handler, which both write to Local Postgres only).
    router.get('/:id/responders', ipLimiter, async (req, res) => {
        try {
            const { id } = req.params;
            const result = await pool.query(
                `SELECT
                    ir.id,
                    ir.volunteer_id,
                    ir.status,
                    ir.accepted_at,
                    ir.volunteer_start_lat,
                    ir.volunteer_start_lng,
                    TRIM(CONCAT(u.first_name, ' ', COALESCE(u.last_name, ''))) AS volunteer_name,
                    p.id AS profession_id,
                    p.name AS profession_name,
                    p.color_hex AS profession_color
                 FROM incident_responses ir
                 LEFT JOIN users u ON u.id = ir.volunteer_id
                 LEFT JOIN LATERAL (
                    SELECT ugr.profession_id
                    FROM user_group_roles ugr
                    WHERE ugr.user_id = ir.volunteer_id
                    LIMIT 1
                 ) ugr ON true
                 LEFT JOIN professions p ON p.id = ugr.profession_id
                 WHERE ir.video_id = $1
                   AND ir.status IN ('accepted', 'arrived', 'en_route')
                 ORDER BY ir.accepted_at ASC`,
                [id]
            );
            res.json(result.rows);
        } catch (error) {
            console.error('Get Incident Responders Error:', error.message);
            res.status(500).json({ error: 'Failed to fetch incident responders' });
        }
    });

    // Get GPS tracks for a video
    router.get('/:id/gps-tracks', ipLimiter, async (req, res) => {
        try {
            const { id } = req.params;
            const data = await cacheAside(`video:gps:${id}`, async () => {
                const result = await pool.query(
                    'SELECT * FROM video_gps_tracks WHERE video_id = $1 ORDER BY timestamp_offset',
                    [id]
                );
                return result.rows;
            }, TTL.DEFAULT);
            res.json(data);
        } catch (error) {
            res.status(500).json({ error: 'Failed to fetch GPS tracks' });
        }
    });
    // Get gallery photos for a specific incident with pagination
    // Phase 6.12: Query thai_mhung_photos directly to get blur_status for async face blur
    router.get('/:id/gallery', ipLimiter, async (req, res) => {
        try {
            const { id } = req.params;
            const { page, limit, offset } = clampPagination(req);
            const cacheKey = `video:gallery:${sanitizeCacheKey(id)}:${page}:${limit}`;
            console.log(`[Gallery] Querying gallery for video_id=${id}, page=${page}, limit=${limit}`);

            const data = await cacheAside(cacheKey, async () => {
                const result = await pool.query(
                    `SELECT id, photo_url, created_at, user_id, blur_status, latitude, longitude
                     FROM thai_mhung_photos
                     WHERE video_id = $1
                     ORDER BY created_at DESC
                     LIMIT $2 OFFSET $3`,
                    [id, limit, offset]
                );

                const mapped = result.rows.map(row => ({
                    id: row.id,
                    photo_url: row.photo_url,
                    created_at: row.created_at,
                    user_id: row.user_id,
                    blur_status: row.blur_status,
                    latitude: row.latitude,
                    longitude: row.longitude,
                }));
                console.log(`[Gallery] Returning ${mapped.length} photos for incident ${id}:`, mapped.map(p => ({ id: p.id, blur_status: p.blur_status })));
                return mapped;
            }, TTL.DEFAULT);

            res.json(data);
        } catch (error) {
            console.error('Error fetching gallery photos:', error.message);
            res.status(500).json({ error: 'Failed to fetch gallery photos' });
        }
    });
    // Get interaction summary for a video
    router.get('/:id/interactions', ipLimiter, async (req, res) => {
        try {
            const { id } = req.params;
            const data = await cacheAside(`video:interactions:${id}`, async () => {
                const views = await pool.query(
                    "SELECT COUNT(*) as cnt FROM video_interactions WHERE video_id = $1 AND type = 'view'", [id]
                );
                const likes = await pool.query(
                    "SELECT COUNT(*) as cnt FROM video_interactions WHERE video_id = $1 AND type = 'like'", [id]
                );
                const gifts = await pool.query(
                    "SELECT COALESCE(SUM(value), 0) as total FROM video_interactions WHERE video_id = $1 AND type = 'gift'", [id]
                );
                return {
                    views: parseInt(views.rows[0].cnt),
                    likes: parseInt(likes.rows[0].cnt),
                    donations: parseFloat(gifts.rows[0].total),
                };
            }, TTL.DONATION);
            res.json(data);
        } catch (error) {
            res.status(500).json({ error: 'Failed to fetch interactions' });
        }
    });
    // ✅ [Support Analytics] Get like trend — 10-second buckets, last 5 minutes
    router.get('/:id/likes/trend', ipLimiter, async (req, res) => {
        if (!pool) return res.json([]);
        try {
            const { id } = req.params;
            const result = await pool.query(`
                SELECT
                    floor(extract(epoch from created_at) / 10) * 10 AS bucket,
                    COUNT(*) AS count
                FROM video_interactions
                WHERE video_id = $1 AND type = 'like'
                    AND created_at > NOW() - INTERVAL '5 minutes'
                GROUP BY bucket
                ORDER BY bucket
            `, [id]);
            res.json(result.rows.map(r => ({
                bucket: parseFloat(r.bucket),
                count: parseInt(r.count),
            })));
        } catch (error) {
            console.error('Error fetching like trend:', error.message);
            res.status(500).json({ error: 'Failed to fetch like trend' });
        }
    });

    // ✅ [Support Analytics] Check if user already liked a video
    router.get('/:id/likes/status', ipLimiter, async (req, res) => {
        if (!pool) return res.json({ liked: false });
        try {
            const { id } = req.params;
            const userId = req.userId;
            if (!userId) return res.json({ liked: false });
            const existing = await pool.query(
                `SELECT id FROM video_interactions WHERE video_id = $1 AND user_id = $2 AND type = 'like'`,
                [id, userId]
            );
            const liked = existing.rows.length > 0;
            res.json({ liked });
        } catch (error) {
            res.status(500).json({ liked: false });
        }
    });

    // ✅ [Support Analytics] Record interaction — DB Toggle for 'like', normal INSERT for others
    router.post('/:id/interactions', requireAuth, strictRateLimiter, duplicateCheckMiddleware('video-interaction', 3), async (req, res) => {
        try {
            const { id } = req.params;
            const user_id = req.userId;
            const { type, value } = req.body;

            if (!user_id) {
                return res.status(401).json({ error: 'Authentication required' });
            }

            if (type === 'like' && pool) {
                // DB Toggle: check if like exists for this user
                const existing = await pool.query(
                    `SELECT id FROM video_interactions WHERE video_id = $1 AND user_id = $2 AND type = 'like'`,
                    [id, user_id]
                );
                let liked;
                if (existing.rows.length > 0) {
                    // Unlike: DELETE
                    await pool.query(
                        `DELETE FROM video_interactions WHERE video_id = $1 AND user_id = $2 AND type = 'like'`,
                        [id, user_id]
                    );
                    liked = false;
                } else {
                    // Like: INSERT — ON CONFLICT กัน race condition
                    // (uniq_like_per_user_video partial unique index)
                    await pool.query(
                        `INSERT INTO video_interactions (video_id, user_id, type, value, created_at)
                         VALUES ($1, $2, 'like', 0, NOW())
                         ON CONFLICT (video_id, user_id) WHERE type = 'like' DO NOTHING`,
                        [id, user_id]
                    );
                    liked = true;
                }
                // Return updated count
                const countRes = await pool.query(
                    `SELECT COUNT(*) as cnt FROM video_interactions WHERE video_id = $1 AND type = 'like'`,
                    [id]
                );
                const count = parseInt(countRes.rows[0].cnt);
                return res.json({ liked, count });
            }

            // Non-like interactions: normal INSERT
            const result = await pool.query(
                `INSERT INTO video_interactions (video_id, user_id, type, value) VALUES ($1, $2, $3, $4) RETURNING *`,
                [id, user_id, type, value || 0]
            );
            res.json(result.rows[0]);
        } catch (error) {
            console.error('Error recording interaction:', error.message);
            res.status(500).json({ error: 'Failed to record interaction' });
        }
    });

    // Get video status
    router.get('/:id', ipLimiter, async (req, res) => {
        try {
            const { id } = req.params;
            const data = await cacheAside(`video:meta:${id}:v2`, async () => {
                const result = await pool.query('SELECT id, user_id, title, description, type, category_id, donation_request_id, status, thumbnail_url, bunny_url, photo_urls, address, road, soi, alley, village, progress, created_at, updated_at FROM videos WHERE id = $1', [id]);
                return result.rows[0] || null;
            }, TTL.DEFAULT);

            if (data === null) {
                return res.status(404).json({ error: 'Video not found' });
            }

            res.json(data);
        } catch (error) {
            res.status(500).json({ error: 'Failed to fetch video status' });
        }
    });

    return router;
};
