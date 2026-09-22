const express = require('express');
const router = express.Router();
const multer = require('multer');
const path = require('path');
const fs = require('fs');
const { v4: uuidv4 } = require('uuid');
const faceBlurService = require('../services/face-blur-service');
const { safeExtension } = require('../utils/safe-path');
const { rateLimiter } = require('../middleware');

// PDPA face blur สำหรับ client ที่ไม่มี ML Kit (Flutter Web) —
// ใช้ pipeline deface/CenterFace ชุดเดียวกับ routes/video.js
// Fail-closed: ถ้า blur ไม่สำเร็จจะไม่คืนภาพต้นฉบับ (unblurred) กลับไป
const blurRateLimiter = rateLimiter({ maxRequests: 30, windowSec: 60, keyPrefix: 'rate:faceblur' });

const MAX_IMAGE_BYTES = 10 * 1024 * 1024; // 10MB — ตรงกับ MAX_PHOTO_BYTES ของ video upload

const storage = multer.diskStorage({
    destination: async (req, file, cb) => {
        const destDir = process.env.TEMP_MEDIA_PATH || path.join(__dirname, '../temp/media');
        try {
            await fs.promises.mkdir(destDir, { recursive: true });
            cb(null, destDir);
        } catch (err) {
            cb(err);
        }
    },
    filename: (req, file, cb) => {
        try {
            const ext = safeExtension(file.originalname, 'image');
            cb(null, `${uuidv4()}${ext}`);
        } catch (err) {
            cb(err);
        }
    }
});

const upload = multer({
    storage,
    limits: { fileSize: MAX_IMAGE_BYTES, files: 1 },
});

function cleanupFile(filePath) {
    if (filePath) {
        try { fs.unlinkSync(filePath); } catch (_) {}
    }
}

const MIME_BY_EXT = {
    '.jpg': 'image/jpeg',
    '.jpeg': 'image/jpeg',
    '.png': 'image/png',
    '.webp': 'image/webp',
};

// POST /api/media/face-blur
// multipart field: `image` (jpg/jpeg/png/webp ≤10MB)
// response: 200 image bytes (blurred) | 400/415/503 error json
router.post('/face-blur', blurRateLimiter, upload.single('image'), async (req, res) => {
    if (!req.userId) {
        cleanupFile(req.file && req.file.path);
        return res.status(401).json({ error: 'Login required' });
    }
    if (!req.file) {
        return res.status(400).json({ error: 'Missing image file' });
    }

    const inputPath = req.file.path;
    const ext = path.extname(inputPath);
    const outputPath = path.join(
        path.dirname(inputPath),
        `${path.basename(inputPath, ext)}_blurred${ext}`
    );

    try {
        const result = await faceBlurService.blurFacesInImage(inputPath, outputPath);
        if (!result.success || !fs.existsSync(outputPath)) {
            // Fail-closed: ไม่ส่งภาพต้นฉบับที่ยังไม่เบลอกลับไป
            return res.status(503).json({ error: 'Face blur unavailable', detail: result.error || 'blur failed' });
        }
        res.setHeader('Content-Type', MIME_BY_EXT[ext] || 'application/octet-stream');
        res.setHeader('Cache-Control', 'no-store');
        res.sendFile(outputPath, (err) => {
            cleanupFile(inputPath);
            cleanupFile(outputPath);
            if (err && !res.headersSent) {
                res.status(500).json({ error: 'Failed to send blurred image' });
            }
        });
    } catch (err) {
        cleanupFile(inputPath);
        cleanupFile(outputPath);
        res.status(500).json({ error: 'Face blur failed', detail: err.message });
    }
});

module.exports = { mediaRoutes: () => router };
