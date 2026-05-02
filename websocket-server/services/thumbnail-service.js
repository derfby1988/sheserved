const { spawn } = require('child_process');
const path = require('path');
const fs = require('fs');

/**
 * Generate a WebP thumbnail (static or animated) from one or more images.
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
        const inputFilesStr = inputPaths.join(',');

        console.log(`[Thumbnail] Generating thumbnail from ${inputPaths.length} images -> ${path.basename(outputPath)}`);

        const python = spawn('python3', [pythonScriptPath, inputFilesStr, outputPath]);

        let stdout = '';
        let stderr = '';

        python.stdout.on('data', (data) => { stdout += data.toString(); });
        python.stderr.on('data', (data) => { stderr += data.toString(); });

        python.on('close', (code) => {
            try {
                const result = JSON.parse(stdout.trim());
                if (result.success && fs.existsSync(outputPath)) {
                    console.log(`[Thumbnail] ✅ Done — Thumbnail created: ${path.basename(outputPath)}`);
                    resolve({ success: true, outputPath });
                } else {
                    console.warn(`[Thumbnail] ⚠️ Failed: ${result.error || stderr}`);
                    resolve({ success: false, error: result.error });
                }
            } catch (e) {
                console.warn(`[Thumbnail] ⚠️ Parse error: ${e.message} | stdout: ${stdout} | stderr: ${stderr}`);
                resolve({ success: false, error: e.message });
            }
        });

        python.on('error', (err) => {
            console.warn(`[Thumbnail] ⚠️ Spawn error: ${err.message}`);
            resolve({ success: false, error: err.message });
        });

        // Timeout 15 seconds
        setTimeout(() => {
            python.kill();
            console.warn(`[Thumbnail] ⏱️ Timeout generating thumbnail`);
            resolve({ success: false, error: 'Timeout' });
        }, 15000);
    });
}

module.exports = { generateThumbnail };
