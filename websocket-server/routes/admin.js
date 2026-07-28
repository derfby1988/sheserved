const express = require('express');
const multer = require('multer');
const path = require('path');
const fs = require('fs');
const { safeExtension } = require('../utils/safe-path');
const {
    authRateLimiter,
    strictRateLimiter,
    cacheAside,
    TTL,
    invalidateCache,
    requireRole,
} = require('../middleware');

module.exports = (pool) => {
    const router = express.Router();

    // Configure Multer for watermark image upload
    const storage = multer.diskStorage({
        destination: (req, file, cb) => {
            const dir = path.join(__dirname, '../uploads/watermarks');
            if (!fs.existsSync(dir)){
                fs.mkdirSync(dir, { recursive: true });
            }
            cb(null, dir);
        },
        filename: (req, file, cb) => {
            try {
                const ext = safeExtension(file.originalname, 'image');
                cb(null, 'watermark' + ext);
            } catch (err) {
                cb(err);
            }
        }
    });

    const upload = multer({
        storage: storage,
        limits: { fileSize: 5 * 1024 * 1024 }, // 5MB limit
        fileFilter: (req, file, cb) => {
            if (file.mimetype === 'image/png') {
                cb(null, true);
            } else {
                cb(new Error('Only PNG format is allowed for watermark images!'));
            }
        }
    });

    // GET /api/admin/watermark - Get current watermark config
    router.get('/watermark', authRateLimiter, async (req, res) => {
        try {
            const data = await cacheAside('admin:watermark:config', async () => {
                const result = await pool.query('SELECT * FROM watermark_configs WHERE id = 1');
                return result.rows[0] || null;
            }, TTL.DEFAULT);

            if (data === null) {
                return res.status(404).json({ error: 'Watermark configuration not found' });
            }
            res.json(data);
        } catch (err) {
            console.error('Error fetching watermark config:', err);
            res.status(500).json({ error: 'Server error' });
        }
    });

    // PUT /api/admin/watermark - Update watermark config
    router.put('/watermark', authRateLimiter, requireRole('admin'), strictRateLimiter, async (req, res) => {
        const { is_enabled, type, text_content, position, animation_type, opacity, show_incident_id, show_uploader_id } = req.body;
        
        try {
            const result = await pool.query(
                `UPDATE watermark_configs 
                 SET is_enabled = $1, type = $2, text_content = $3, position = $4, animation_type = $5, opacity = $6, show_incident_id = $7, show_uploader_id = $8, updated_at = CURRENT_TIMESTAMP
                 WHERE id = 1 RETURNING *`,
                [is_enabled, type, text_content, position, animation_type, opacity, show_incident_id, show_uploader_id]
            );
            
            if (result.rows.length === 0) {
                return res.status(404).json({ error: 'Watermark configuration not found' });
            }
            
            await invalidateCache('admin:watermark:config');
            res.json({ message: 'Watermark configuration updated successfully', data: result.rows[0] });
        } catch (err) {
            console.error('Error updating watermark config:', err);
            res.status(500).json({ error: 'Server error' });
        }
    });

    // POST /api/admin/watermark/upload - Upload watermark image
    router.post('/watermark/upload', authRateLimiter, requireRole('admin'), strictRateLimiter, upload.single('watermark_image'), async (req, res) => {
        try {
            if (!req.file) {
                return res.status(400).json({ error: 'Please upload a PNG file' });
            }

            // Generate URL for the uploaded image (accessible statically)
            const imageUrl = `/uploads/watermarks/${req.file.filename}`;

            // Update database with the new image URL
            await pool.query(
                'UPDATE watermark_configs SET image_url = $1, updated_at = CURRENT_TIMESTAMP WHERE id = 1',
                [imageUrl]
            );

            res.json({ 
                message: 'Watermark image uploaded successfully', 
                imageUrl: imageUrl 
            });
        } catch (err) {
            console.error('Error uploading watermark image:', err);
            res.status(500).json({ error: err.message || 'Server error during upload' });
        }
    });

    return router;
};
