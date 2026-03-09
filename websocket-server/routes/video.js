const express = require('express');
const router = express.Router();
const multer = require('multer');
const path = require('path');
const fs = require('fs');
const { v4: uuidv4 } = require('uuid');
const videoService = require('../services/video-service');

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

    // Upload video
    router.post('/upload', upload.single('video'), async (req, res) => {
        try {
            const { userId, title, description, type, donationRequestId } = req.body;
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
                `INSERT INTO videos (id, user_id, title, description, type, category_id, donation_request_id, status)
                 VALUES ($1, $2, $3, $4, $5, $6, $7, 'processing') RETURNING id`,
                [videoId, userId, title, description || '', type || 'normal', categoryId || null, donationRequestId || null]
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
    router.post('/upload-photos', upload.array('photos', 5), async (req, res) => {
        try {
            const userIdFromRequest = req.body.userId;
            const files = req.files;

            if (!files || files.length === 0) {
                return res.status(400).json({ error: 'No photos provided' });
            }

            if (files.length > 5) {
                return res.status(400).json({ error: 'Maximum 5 photos allowed' });
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

            const { userId, title, description, categoryId, donationRequestId, gpsTracks } = req.body;

            const photoUrls = files.map(f => `/uploads/videos/${f.filename}`);

            // 1. Insert into Database
            const videoId = uuidv4();
            const result = await pool.query(
                `INSERT INTO videos (id, user_id, title, description, type, category_id, donation_request_id, photo_urls, status)
                 VALUES ($1, $2, $3, $4, 'emergency_photo', $5, $6, $7::jsonb, 'processing') RETURNING id`,
                [videoId, userId, title, description || '', categoryId || null, donationRequestId || null, JSON.stringify(photoUrls)]
            );

            const videoRecord = result.rows[0];

            // 2. Handle GPS Tracks if provided
            if (gpsTracks) {
                try {
                    const tracks = JSON.parse(gpsTracks);
                    if (Array.isArray(tracks)) {
                        for (const track of tracks) {
                            await pool.query(
                                `INSERT INTO video_gps_tracks (video_id, latitude, longitude, timestamp_offset)
                                 VALUES ($1, $2, $3, $4)`,
                                [videoRecord.id, track.latitude, track.longitude, track.timestampOffset]
                            );
                        }
                    }
                } catch (gpsError) {
                    console.error('Error inserting GPS tracks for photos:', gpsError);
                }
            }

            // 3. Mark as Ready directly since there's no transcoding needed for photos right now
            await pool.query('UPDATE videos SET status = $1, progress = 100 WHERE id = $2', ['ready', videoRecord.id]);
            io.to(`video-${videoRecord.id}`).emit('video-status', {
                videoId: videoRecord.id,
                status: 'ready',
                progress: 100
            });

            res.json({
                message: 'Photos upload successful',
                video: videoRecord
            });
        } catch (error) {
            console.error('Upload Error:', error);
            res.status(500).json({ error: 'Failed to upload photos' });
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
