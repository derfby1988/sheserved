const sharp = require('sharp');
const fs = require('fs');
const path = require('path');

/**
 * Apply watermark to an image using Sharp
 * @param {string} inputPath 
 * @param {string} outputPath 
 * @param {object} config - The watermark config from DB
 * @param {string} videoId - Optional video/incident ID for forensic tracking
 * @param {string} userId - Optional user ID for forensic tracking
 * @returns {Promise<{success: boolean, outputPath?: string, error?: string}>}
 */
async function applyImageWatermark(inputPath, outputPath, config, videoId, userId) {
    if (!config || !config.is_enabled) {
        // Just copy the file if watermark is disabled or no config
        if (inputPath !== outputPath) {
            fs.copyFileSync(inputPath, outputPath);
        }
        return { success: true, outputPath };
    }

    try {
        const image = sharp(inputPath);
        const metadata = await image.metadata();
        const width = metadata.width;
        const height = metadata.height;

        let compositeOptions = [];

        // Build forensic text
        let forensicText = '';
        if (config.show_incident_id && videoId) forensicText += `Ref: ${videoId}  `;
        if (config.show_uploader_id && userId) forensicText += `User: ${userId}`;
        forensicText = forensicText.trim();

        // SVG string for text watermark
        const opacity = config.opacity !== undefined ? config.opacity : 0.5;
        
        let positionOptions = { gravity: 'southeast' }; // default
        if (config.position === 'top-left') positionOptions.gravity = 'northwest';
        else if (config.position === 'top-right') positionOptions.gravity = 'northeast';
        else if (config.position === 'bottom-left') positionOptions.gravity = 'southwest';
        else if (config.position === 'center') positionOptions.gravity = 'center';

        if (config.type === 'text' && config.text_content) {
            const fontSize = Math.max(24, Math.floor(width * 0.05)); // Adaptive font size
            
            let textAnchor = 'end';
            let x = width - 20;
            let y = height - 20;
            let dominantBaseline = 'auto';

            if (positionOptions.gravity === 'northwest') { textAnchor = 'start'; x = 20; y = 20 + fontSize; }
            else if (positionOptions.gravity === 'northeast') { textAnchor = 'end'; x = width - 20; y = 20 + fontSize; }
            else if (positionOptions.gravity === 'southwest') { textAnchor = 'start'; x = 20; y = height - 20; }
            else if (positionOptions.gravity === 'center') { textAnchor = 'middle'; x = width/2; y = height/2; dominantBaseline='middle'; }

            const svgOverlay = `
                <svg width="${width}" height="${height}">
                    <style>
                    .watermark { fill: rgba(255, 255, 255, ${opacity}); font-size: ${fontSize}px; font-weight: bold; font-family: Arial, sans-serif; text-shadow: 2px 2px 4px rgba(0,0,0,0.8); }
                    .forensic { fill: rgba(255, 255, 255, 0.4); font-size: ${Math.max(12, Math.floor(width * 0.02))}px; font-family: monospace; text-shadow: 1px 1px 2px rgba(0,0,0,0.8); }
                    </style>
                    <text x="${x}" y="${y}" text-anchor="${textAnchor}" dominant-baseline="${dominantBaseline}" class="watermark">${config.text_content}</text>
                    ${forensicText ? `<text x="10" y="${height - 10}" text-anchor="start" class="forensic">${forensicText}</text>` : ''}
                </svg>
            `;

            compositeOptions.push({
                input: Buffer.from(svgOverlay),
                top: 0,
                left: 0
            });
        } else if (config.type === 'image' && config.image_url) {
            const imgPath = path.join(__dirname, '..', config.image_url);
            if (fs.existsSync(imgPath)) {
                // Resize watermark image relative to main image size (e.g., 20% width)
                const wmWidth = Math.floor(width * 0.2);
                const wmBuffer = await sharp(imgPath)
                    .resize({ width: wmWidth })
                    .ensureAlpha()
                    .raw()
                    .toBuffer({ resolveWithObject: true });

                // Modify alpha channel for opacity
                for (let i = 3; i < wmBuffer.data.length; i += 4) {
                    wmBuffer.data[i] = Math.round(wmBuffer.data[i] * opacity);
                }

                const wmProcessed = await sharp(wmBuffer.data, {
                    raw: {
                        width: wmBuffer.info.width,
                        height: wmBuffer.info.height,
                        channels: 4
                    }
                }).png().toBuffer();

                compositeOptions.push({
                    input: wmProcessed,
                    gravity: positionOptions.gravity
                });

                if (forensicText) {
                    const fontSize = Math.max(12, Math.floor(width * 0.02));
                    const svgForensic = `
                        <svg width="${width}" height="${height}">
                            <style>
                            .forensic { fill: rgba(255, 255, 255, 0.4); font-size: ${fontSize}px; font-family: monospace; text-shadow: 1px 1px 2px rgba(0,0,0,0.8); }
                            </style>
                            <text x="10" y="${height - 10}" text-anchor="start" class="forensic">${forensicText}</text>
                        </svg>
                    `;
                    compositeOptions.push({
                        input: Buffer.from(svgForensic),
                        top: 0,
                        left: 0
                    });
                }
            } else if (forensicText) {
                 const fontSize = Math.max(12, Math.floor(width * 0.02));
                 const svgForensic = `
                     <svg width="${width}" height="${height}">
                         <style>
                         .forensic { fill: rgba(255, 255, 255, 0.4); font-size: ${fontSize}px; font-family: monospace; text-shadow: 1px 1px 2px rgba(0,0,0,0.8); }
                         </style>
                         <text x="10" y="${height - 10}" text-anchor="start" class="forensic">${forensicText}</text>
                     </svg>
                 `;
                 compositeOptions.push({
                     input: Buffer.from(svgForensic),
                     top: 0,
                     left: 0
                 });
            }
        } else if (forensicText) {
            const fontSize = Math.max(12, Math.floor(width * 0.02));
            const svgForensic = `
                <svg width="${width}" height="${height}">
                    <style>
                    .forensic { fill: rgba(255, 255, 255, 0.4); font-size: ${fontSize}px; font-family: monospace; text-shadow: 1px 1px 2px rgba(0,0,0,0.8); }
                    </style>
                    <text x="10" y="${height - 10}" text-anchor="start" class="forensic">${forensicText}</text>
                </svg>
            `;
            compositeOptions.push({
                input: Buffer.from(svgForensic),
                top: 0,
                left: 0
            });
        }

        if (compositeOptions.length > 0) {
            await image.composite(compositeOptions).toFile(outputPath);
        } else {
            if (inputPath !== outputPath) {
                fs.copyFileSync(inputPath, outputPath);
            }
        }

        return { success: true, outputPath };
    } catch (error) {
        console.error('[WatermarkService] Error applying watermark:', error);
        return { success: false, error: error.message };
    }
}

module.exports = {
    applyImageWatermark
};
