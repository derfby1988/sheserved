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

// Configure Multer for file upload
const storage = multer.diskStorage({
    destination: (req, file, cb) => {
        const destDir = process.env.TEMP_VIDEO_PATH || path.join(__dirname, '../temp/videos');
        if (!fs.existsSync(destDir)) {
            fs.mkdirSync(destDir, { recursive: true });
        }
        cb(null, destDir);
    },
    filename: (req, file, cb) => {
        const uniqueName = `${uuidv4()}${path.extname(file.originalname)}`;
        cb(null, uniqueName);
    }
});

const upload = multer({
    storage,
    limits: { fileSize: 500 * 1024 * 1024 } // 500MB limit
});

const lastUploadTimestamps = new Map();

module.exports = (pool) => {
    // Initialize video service with the pool
    videoService.init(pool);

    // Get videos List by type (Local API fallback for gallery/live stream)
    router.get('/', async (req, res) => {
        try {
            const { type, category_id } = req.query;
            let query = 'SELECT * FROM videos WHERE 1=1';
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
            res.json(result.rows);
        } catch (error) {
            console.error('[API] Error fetching videos list:', error);
            res.status(500).json({ error: 'Failed to fetch videos' });
        }
    });

    // Upload video
    router.post('/upload', upload.single('video'), async (req, res) => {
        try {
            const { userId, title, description, type, donationRequestId, address, road, soi, alley, village } = req.body;
            const file = req.file;

            if (!file) {
                return res.status(400).json({ error: 'No video file provided' });
            }

            // --- STRICT CONTROL ENFORCEMENT ---

            // 1. Rate Limiting (3s Cooldown)
            const now = Date.now();
            const lastUpload = lastUploadTimestamps.get(userId) || 0;
            const cooldownMs = 3000; // 3 Seconds

            if (now - lastUpload < cooldownMs) {
                const waitSec = Math.ceil((cooldownMs - (now - lastUpload)) / 1000);
                return res.status(429).json({
                    error: `Please wait ${waitSec}s before next upload`,
                    cooldownSeconds: waitSec
                });
            }

            // 2. File Size Validation (Enforced by Multer limits as well, but double check)
            const maxMB = 20;
            if (file.size > maxMB * 1024 * 1024) {
                return res.status(413).json({
                    error: `File too large. Max allowed: ${maxMB}MB`
                });
            }

            // Update timestamp after checks
            lastUploadTimestamps.set(userId, now);

            const { categoryId, gpsTracks } = req.body;

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
            res.status(500).json({ error: 'Failed to upload video' });
        }
    });

    // Upload multiple photos
    // รองรับทั้ง Emergency Photo (max 5) และ Thai Mhung Photo (max 3)
    // โดย enforce ตาม isThaiMhung flag ที่ส่งมาจาก Flutter
    router.post('/upload-photos', upload.array('photos', 5), async (req, res) => {
        try {
            const userIdFromRequest = req.body.userId;
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
                return res.status(400).json({
                    error: `${modeName} mode allows maximum ${quota} photos per upload`
                });
            }

            // 1. Rate Limiting (3s Cooldown)
            const now = Date.now();
            const lastUpload = lastUploadTimestamps.get(userIdFromRequest) || 0;
            const cooldownMs = 3000;

            if (now - lastUpload < cooldownMs) {
                const waitSec = Math.ceil((cooldownMs - (now - lastUpload)) / 1000);
                return res.status(429).json({
                    error: `Please wait ${waitSec}s before next upload`,
                    cooldownSeconds: waitSec
                });
            }

            lastUploadTimestamps.set(userIdFromRequest, now);

            const { userId, title, description, categoryId, donationRequestId, gpsTracks, incidentId } = req.body;

            // ✅ ใช้ type ตาม mode จริง แทนที่จะ hardcode 'emergency_photo' เสมอ
            const videoType = isThaiMhung ? 'thai_mhung_photo' : 'emergency_photo';

            // 2. Insert into Database first to get the videoId
            const videoId = uuidv4();
            
            // ✅ Organize files into subfolders
            const baseDir = process.env.TEMP_VIDEO_PATH || path.join(__dirname, '../temp/videos');
            
            // Structure: 
            // - Regular: baseDir/[videoId]/photos/
            // - Thai Mhung: baseDir/[incidentId]/thaimhung/[videoId]/
            let reportDir;
            if (isThaiMhung && incidentId) {
                reportDir = path.join(baseDir, incidentId, 'thaimhung', videoId);
            } else {
                reportDir = path.join(baseDir, videoId);
            }

            if (!fs.existsSync(reportDir)) {
                fs.mkdirSync(reportDir, { recursive: true });
            }

            const photoUrls = [];
            const localApiUrl = process.env.LOCAL_API_URL || 'http://localhost:3000';
            
            for (const file of files) {
                const newPath = path.join(reportDir, file.filename);
                // Move file from root destDir to reportDir
                fs.renameSync(file.path, newPath);

                // ✅ Thai Mhung Face Blur: เบลอเฉพาะใบหน้าก่อน broadcast
                // สร้างชื่อไฟล์ output แยกต่างหาก เช่น uuid_anon.jpg
                let finalFilePath = newPath;
                if (isThaiMhung) {
                    const ext = path.extname(file.filename);
                    const anonFilename = `${path.basename(file.filename, ext)}_anon${ext}`;
                    const anonPath = path.join(reportDir, anonFilename);
                    const blurResult = await faceBlurService.blurFacesInImage(newPath, anonPath);
                    if (blurResult.success) {
                        finalFilePath = anonPath;
                        // ✅ ลบไฟล์ต้นฉบับหลังเบลอสำเร็จ เพื่อปกป้อง Privacy
                        try { fs.unlinkSync(newPath); } catch (_) {}
                    }
                    // ถ้าล้มเหลว → ใช้ต้นฉบับตามเดิม (blurResult.outputPath = newPath)
                    finalFilePath = blurResult.outputPath;
                }

                // Construct URL correctly
                const finalFilename = path.basename(finalFilePath);
                let relativePath;
                if (isThaiMhung && incidentId) {
                    relativePath = `${incidentId}/thaimhung/${videoId}/${finalFilename}`;
                } else {
                    relativePath = `${videoId}/${finalFilename}`;
                }
                
                // ✅ ใช้ full URL เพื่อให้ Client แสดงผลได้ทันที
                photoUrls.push(`${localApiUrl}/temp/videos/${relativePath}`);
                
                // เก็บ local path เพื่อใช้ทำ Thumbnail
                if (!req.localFilePaths) req.localFilePaths = [];
                req.localFilePaths.push(finalFilePath);
            }

            // ✅ Set first photo as bunny_url for basic preview support
            const firstPhotoUrl = photoUrls.length > 0 ? photoUrls[0] : null;

            // ✅ สร้าง Thumbnail (Animated WebP) โดยรวมภาพจากทุกๆ การอัปโหลดของไทยมุง
            let thumbnailUrl = firstPhotoUrl;
            let filesForThumbnail = [];

            if (isThaiMhung && incidentId) {
                // รวบรวมภาพล่าสุด 5 ภาพจากทุกเหตุการณ์ย่อยของไทยมุงใน incident นี้
                const thaimhungBaseDir = path.join(baseDir, incidentId, 'thaimhung');
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
                const thumbFilename = `thumb_${isThaiMhung ? incidentId : videoId}.webp`;
                const destDirForThumb = isThaiMhung ? path.join(baseDir, incidentId) : reportDir;
                const thumbLocalPath = path.join(destDirForThumb, thumbFilename);
                const thumbTargetId = isThaiMhung ? incidentId : videoId;

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
                    isThaiMhung: isThaiMhung && !!incidentId,
                    incidentId: incidentId || null,
                    videoId,
                    localApiUrl,
                    baseDir,
                }).catch(err => {
                    console.error('[ThumbnailQueue] Failed to add job:', err.message);
                });
            }

            const result = await pool.query(
                `INSERT INTO videos (id, user_id, title, description, type, category_id, donation_request_id, photo_urls, bunny_url, thumbnail_url, incident_id, status)
                 VALUES ($1, $2, $3, $4, $5, $6, $7, $8::jsonb, $9, $10, $11, 'processing') RETURNING *`,
                [videoId, userId, title, description || '', videoType, categoryId || null, donationRequestId || null, JSON.stringify(photoUrls), firstPhotoUrl, thumbnailUrl, incidentId || null]
            );

            const videoRecord = result.rows[0];

            // ✅ อัปเดต Thumbnail ให้กับเหตุการณ์หลัก (Incident) โดยอัปเดตเสมอเพื่ออัปเดตภาพ Animated ล่าสุด
            if (isThaiMhung && incidentId && thumbnailUrl) {
                try {
                    await pool.query(
                        `UPDATE videos SET thumbnail_url = $1 WHERE id = $2`,
                        [thumbnailUrl, incidentId]
                    );
                } catch (updateErr) {
                    console.error('[Thumbnail] Failed to update main incident thumbnail:', updateErr);
                }
            }

            // 3. Handle GPS Tracks if provided
            if (gpsTracks) {
                try {
                    const tracks = JSON.parse(gpsTracks);
                    if (Array.isArray(tracks)) {
                        for (const track of tracks) {
                            await pool.query(
                                `INSERT INTO video_gps_tracks (video_id, latitude, longitude, timestamp_offset)
                                 VALUES ($1, $2, $3, $4)`,
                                 [videoId, track.latitude, track.longitude, track.timestampOffset || 0]
                            );
                        }
                    }
                } catch (gpsError) {
                    console.error('Error inserting GPS tracks for photos:', gpsError);
                }
            }

            // 4. Mark as Ready डायरेक्टली
            await pool.query('UPDATE videos SET status = $1, progress = 100 WHERE id = $2', ['ready', videoId]);
            socketService.sendStatus(userId || userIdFromRequest, videoId, 'ready', { progress: 100 });

            // 5. ✅ Broadcast ภาพใหม่ไปยังทุก Client ในห้อง Incident
            if (isThaiMhung && incidentId) {
                const latestTrack = gpsTracks ? (() => { try { const t = JSON.parse(gpsTracks); return Array.isArray(t) && t.length > 0 ? t[t.length - 1] : null; } catch(e) { return null; } })() : null;
                for (const url of photoUrls) {
                    socketService.broadcastNewThaiMhungPhoto(incidentId, {
                        photo_url: url,
                        user_id: userId || userIdFromRequest,
                        latitude: latestTrack ? latestTrack.latitude : null,
                        longitude: latestTrack ? latestTrack.longitude : null,
                        created_at: new Date().toISOString(),
                        video_id: incidentId,
                    });
                }
            }

            res.json({
                message: `${modeName} photos upload successful (${files.length}/${quota})`,
                video: { ...videoRecord, photo_urls: photoUrls },
                photo_urls: photoUrls,
                incidentId: incidentId
            });
        } catch (error) {
            console.error('Upload Error:', error);
            res.status(500).json({ error: 'Failed to upload photos' });
        }
    });


    // Get emergency videos list (trending) - with user info & interaction counts
    router.get('/emergency/list', async (req, res) => {
        const page = parseInt(req.query.page) || 1;
        const limit = parseInt(req.query.limit) || 20;
        const offset = (page - 1) * limit;

        console.log(`[API] Fetching emergency videos list (page: ${page}, limit: ${limit})`);
        try {
            // ✅ Optimization for Massive Scale: 
            // 1. Used cached_view_count/cached_like_count instead of LEFT JOIN COUNT(*) over millions of records
            // 2. Added LIMIT and OFFSET for infinite scrolling
            const result = await pool.query(`
                SELECT v.*,
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

            res.json(result.rows);
        } catch (error) {
            console.error('Error fetching emergency videos:', error.message);
            res.status(500).json({ error: 'Failed to fetch emergency videos' });
        }
    });

    // Accept incident
    router.post('/:id/accept', async (req, res) => {
        try {
            const { id } = req.params;
            const { responderId, latitude, longitude } = req.body;

            if (!responderId) {
                return res.status(400).json({ error: 'responderId is required' });
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

    // Get GPS tracks for a video
    router.get('/:id/gps-tracks', async (req, res) => {
        try {
            const { id } = req.params;
            const result = await pool.query(
                'SELECT * FROM video_gps_tracks WHERE video_id = $1 ORDER BY timestamp_offset',
                [id]
            );
            res.json(result.rows);
        } catch (error) {
            res.status(500).json({ error: 'Failed to fetch GPS tracks' });
        }
    });

    // Get gallery photos for a specific incident with pagination
    router.get('/:id/gallery', async (req, res) => {
        try {
            const { id } = req.params;
            const page = parseInt(req.query.page) || 1;
            const limit = parseInt(req.query.limit) || 20;
            const offset = (page - 1) * limit;

            const result = await pool.query(
                `SELECT id, photo_urls, created_at, user_id 
                 FROM videos 
                 WHERE type = $1 AND incident_id = $2 
                 ORDER BY created_at DESC 
                 LIMIT $3 OFFSET $4`,
                ['thai_mhung_photo', id, limit, offset]
            );

            // Transform rows to return individual photos
            const finalPhotos = [];
            for (const row of result.rows) {
                let urls = [];
                if (Array.isArray(row.photo_urls)) urls = row.photo_urls;
                else if (typeof row.photo_urls === 'string') {
                    try { urls = JSON.parse(row.photo_urls); } catch(e) {}
                }

                for (let i = 0; i < urls.length; i++) {
                    finalPhotos.push({
                        id: `${row.id}_${i}`,
                        photo_url: urls[i],
                        created_at: row.created_at,
                        user_id: row.user_id
                    });
                }
            }

            res.json(finalPhotos);
        } catch (error) {
            console.error('Error fetching gallery photos:', error.message);
            res.status(500).json({ error: 'Failed to fetch gallery photos' });
        }
    });

    // Get interaction summary for a video
    router.get('/:id/interactions', async (req, res) => {
        try {
            const { id } = req.params;
            const views = await pool.query(
                "SELECT COUNT(*) as cnt FROM video_interactions WHERE video_id = $1 AND type = 'view'", [id]
            );
            const likes = await pool.query(
                "SELECT COUNT(*) as cnt FROM video_interactions WHERE video_id = $1 AND type = 'like'", [id]
            );
            const gifts = await pool.query(
                "SELECT COALESCE(SUM(value), 0) as total FROM video_interactions WHERE video_id = $1 AND type = 'gift'", [id]
            );
            res.json({
                views: parseInt(views.rows[0].cnt),
                likes: parseInt(likes.rows[0].cnt),
                donations: parseFloat(gifts.rows[0].total),
            });
        } catch (error) {
            res.status(500).json({ error: 'Failed to fetch interactions' });
        }
    });

    // ✅ [Support Analytics] Get like trend — 10-second buckets, last 5 minutes
    router.get('/:id/likes/trend', async (req, res) => {
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
    router.get('/:id/likes/status', async (req, res) => {
        if (!pool) return res.json({ liked: false });
        try {
            const { id } = req.params;
            const { userId } = req.query;
            if (!userId) return res.json({ liked: false });
            const existing = await pool.query(
                `SELECT id FROM video_interactions WHERE video_id = $1 AND user_id = $2 AND type = 'like'`,
                [id, userId]
            );
            res.json({ liked: existing.rows.length > 0 });
        } catch (error) {
            res.status(500).json({ liked: false });
        }
    });

    // ✅ [Support Analytics] Record interaction — DB Toggle for 'like', normal INSERT for others
    router.post('/:id/interactions', async (req, res) => {
        try {
            const { id } = req.params;
            const { user_id, type, value } = req.body;

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
                    // Like: INSERT
                    await pool.query(
                        `INSERT INTO video_interactions (video_id, user_id, type, value, created_at) VALUES ($1, $2, 'like', 0, NOW())`,
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
    router.get('/:id', async (req, res) => {
        try {
            const { id } = req.params;
            const result = await pool.query('SELECT * FROM videos WHERE id = $1', [id]);

            if (result.rows.length === 0) {
                return res.status(404).json({ error: 'Video not found' });
            }

            res.json(result.rows[0]);
        } catch (error) {
            res.status(500).json({ error: 'Failed to fetch video status' });
        }
    });

    return router;
};
