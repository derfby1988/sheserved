'use strict';

const fs = require('fs');
const path = require('path');
const multer = require('multer');
const { v4: uuidv4 } = require('uuid');
const { safeExtension } = require('./safe-path');

const MAX_VIDEO_BYTES = 20 * 1024 * 1024; // 20MB — ตรงกับ business rule
const MAX_PHOTO_BYTES = 10 * 1024 * 1024; // 10MB สำหรับรูป
const MAX_UPLOAD_FILES = 5;

function createStorage(kind) {
    return multer.diskStorage({
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
                const ext = safeExtension(file.originalname, kind);
                cb(null, `${uuidv4()}${ext}`);
            } catch (err) {
                cb(err);
            }
        }
    });
}

const videoUpload = multer({
    storage: createStorage('video'),
    limits: { fileSize: MAX_VIDEO_BYTES, files: MAX_UPLOAD_FILES },
});

const photoUpload = multer({
    storage: createStorage('image'),
    limits: { fileSize: MAX_PHOTO_BYTES, files: MAX_UPLOAD_FILES },
});

function photoUploadErrorHandler(err, req, res, next) {
    if (err.code === 'LIMIT_FILE_SIZE') {
        return res.status(413).json({
            error: `Photo file exceeds the ${MAX_PHOTO_BYTES / (1024 * 1024)} MB limit`,
        });
    }
    if (err.statusCode === 415) {
        return res.status(415).json({ error: err.message });
    }
    if (err.name === 'MulterError') {
        return res.status(400).json({ error: 'Invalid photo upload' });
    }
    return next(err);
}

module.exports = {
    videoUpload,
    photoUpload,
    photoUploadErrorHandler,
    MAX_VIDEO_BYTES,
    MAX_PHOTO_BYTES,
    MAX_UPLOAD_FILES,
};
