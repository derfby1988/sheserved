const { spawn } = require('child_process');
const path = require('path');
const fs = require('fs');
const axios = require('axios');

/**
 * Generate a WebP thumbnail (static or animated) from one or more images.
 * 
 * Bug Fixes:
 * - #1: Race Condition fixed — ใช้ resolveOnce() + clearTimeout() ป้องกัน double-resolve
 * - #2: Comma-path Bug fixed — ส่ง JSON Array แทน comma-separated string
 * 
 * @param {string[]} inputPaths - Array of file paths to source images
 * @param {string} outputPath - Path to save the resulting WebP file
 * @returns {Promise<{success: boolean, outputPath: string, error?: string}>}
 */
async function generateThumbnail(inputPaths, outputPath) {
    return new Promise((resolve) => {
        if (!inputPaths || inputPaths.length === 0) {
            return resolve({ success: false, error: 'No input paths provided' });
        }

        const pythonScriptPath = path.join(__dirname, 'generate_thumbnail.py');

        // ✅ Bug #2 Fix: ส่ง JSON Array แทน comma-separated เพื่อรองรับ path ที่มี comma
        const inputFilesJson = JSON.stringify(inputPaths);

        console.log(`[Thumbnail] Generating thumbnail from ${inputPaths.length} images -> ${path.basename(outputPath)}`);

        const python = spawn('python3', [pythonScriptPath, inputFilesJson, outputPath]);

        let stdout = '';
        let stderr = '';

        // ✅ Bug #1 Fix: ใช้ resolveOnce() + flag ป้องกัน double-resolve
        let resolved = false;
        let timer = null;

        const resolveOnce = (result) => {
            if (!resolved) {
                resolved = true;
                if (timer) {
                    clearTimeout(timer); // ✅ ยกเลิก timeout ทันทีที่ process จบ
                    timer = null;
                }
                resolve(result);
            }
        };

        python.stdout.on('data', (data) => { stdout += data.toString(); });
        python.stderr.on('data', (data) => { stderr += data.toString(); });

        python.on('close', (code) => {
            try {
                const result = JSON.parse(stdout.trim());
                if (result.success && fs.existsSync(outputPath)) {
                    console.log(`[Thumbnail] ✅ Done — Thumbnail created: ${path.basename(outputPath)}`);
                    resolveOnce({ success: true, outputPath });
                } else {
                    console.warn(`[Thumbnail] ⚠️ Failed: ${result.error || stderr}`);
                    resolveOnce({ success: false, error: result.error });
                }
            } catch (e) {
                console.warn(`[Thumbnail] ⚠️ Parse error: ${e.message} | stdout: ${stdout} | stderr: ${stderr}`);
                resolveOnce({ success: false, error: e.message });
            }
        });

        python.on('error', (err) => {
            console.warn(`[Thumbnail] ⚠️ Spawn error: ${err.message}`);
            resolveOnce({ success: false, error: err.message });
        });

        // ✅ Bug #1 Fix: Timeout 15 วินาที — ใช้ resolveOnce() ป้องกัน double-resolve
        timer = setTimeout(() => {
            python.kill('SIGKILL');
            console.warn(`[Thumbnail] ⏱️ Timeout generating thumbnail`);
            resolveOnce({ success: false, error: 'Timeout' });
        }, 15000);
    });
}

/**
 * Upload a thumbnail file to Bunny.net CDN Storage (Optional — ทำงานเฉพาะเมื่อ credentials ถูกตั้งค่าแล้ว)
 * Recommendation #9: Bunny.net CDN สำหรับรองรับผู้ใช้นอก LAN
 * 
 * @param {string} localPath - Path ของไฟล์ thumbnail บนเครื่อง
 * @param {string} remoteKey  - Key ใน Bunny.net Storage เช่น 'thumbnails/incidentId/thumb.webp'
 * @returns {Promise<string|null>} CDN URL หรือ null ถ้าไม่ได้ตั้งค่า Bunny.net
 */
async function uploadThumbnailToBunny(localPath, remoteKey) {
    const apiKey = process.env.BUNNY_API_KEY;
    const storageZone = process.env.BUNNY_STORAGE_ZONE;
    const cdnUrl = process.env.BUNNY_CDN_URL;

    // ✅ ข้ามถ้า credentials ยังเป็น placeholder หรือไม่ถูกตั้งค่า
    if (!apiKey || !storageZone || apiKey === 'your_api_key_here' || storageZone === 'your_storage_zone') {
        console.log('[Bunny.net] CDN not configured — using local URL for thumbnail.');
        return null;
    }

    try {
        const fileData = fs.readFileSync(localPath);
        const bunnyStorageUrl = `https://storage.bunnycdn.com/${storageZone}/${remoteKey}`;

        await axios.put(bunnyStorageUrl, fileData, {
            headers: {
                'AccessKey': apiKey,
                'Content-Type': 'image/webp',
            },
            maxBodyLength: Infinity,
        });

        const cdnBase = cdnUrl && cdnUrl !== 'https://your-pull-zone.b-cdn.net'
            ? cdnUrl
            : `https://${storageZone}.b-cdn.net`;

        const cdnThumbnailUrl = `${cdnBase}/${remoteKey}`;
        console.log(`[Bunny.net] ✅ Thumbnail uploaded to CDN: ${cdnThumbnailUrl}`);
        return cdnThumbnailUrl;
    } catch (err) {
        console.error(`[Bunny.net] ❌ Failed to upload thumbnail: ${err.message}`);
        return null; // Non-fatal — ใช้ Local URL แทน
    }
}

module.exports = { generateThumbnail, uploadThumbnailToBunny };
