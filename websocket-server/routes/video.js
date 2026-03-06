const express = require('express');
const router = express.Router();
const multer = require('multer');
const path = require('path');
const { v4: uuidv4 } = require('uuid');
const videoService = require('../services/video-service');

// Configure Multer for file upload
const storage = multer.diskStorage({
    destination: (req, file, cb) => {
        cb(null, path.join(__dirname, '../temp/videos'));
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

module.exports = (pool) => {
    // Upload video
    router.post('/upload', upload.single('video'), async (req, res) => {
        try {
            const { userId, title, description, type, donationRequestId } = req.body;
            const file = req.file;

            if (!file) {
                return res.status(400).json({ error: 'No video file provided' });
            }

            // 1. Insert into Database
            const videoId = uuidv4();
            const result = await pool.query(
                `INSERT INTO videos (id, user_id, title, description, type, donation_request_id, status)
                 VALUES ($1, $2, $3, $4, $5, $6, 'processing')
                 RETURNING *`,
                [videoId, userId, title, description || '', type || 'normal', donationRequestId || null]
            );

            const videoRecord = result.rows[0];

            // 2. Add to Queue for processing
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
