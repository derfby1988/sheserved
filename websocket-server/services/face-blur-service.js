/**
 * face-blur-service.js
 * -----------------------------------------------------------
 * ประมวลผลภาพนิ่งด้วย Python `deface` library เพื่อเบลอ
 * เฉพาะใบหน้าบุคคล (Face Anonymization) โดยไม่เบลอทั้งภาพ
 *
 * นโยบาย: ใช้สำหรับ Thai Mhung Photos เพื่อให้ผู้ดูเห็น
 * รายละเอียดเหตุการณ์ได้ชัดเจน แต่ตัวตนผู้คนยังคงถูกปกป้อง
 * ตาม PDPA
 * -----------------------------------------------------------
 */

const { spawn } = require('child_process');
const fs = require('fs');
const path = require('path');

/**
 * เบลอเฉพาะใบหน้าในรูปภาพโดยใช้ Python deface module
 * @param {string} inputPath - Path ของไฟล์ภาพต้นฉบับ
 * @param {string} outputPath - Path ที่ต้องการบันทึกภาพที่ผ่านการเบลอแล้ว
 * @returns {Promise<{success: boolean, outputPath: string, error?: string}>}
 */
async function blurFacesInImage(inputPath, outputPath) {
    return new Promise((resolve) => {
        if (!fs.existsSync(inputPath)) {
            return resolve({ success: false, outputPath: inputPath, error: 'Input file not found' });
        }

        console.log(`[FaceBlur] Processing: ${path.basename(inputPath)}`);

        // สร้าง Python script ในรูปแบบ inline เพื่อไม่ต้องสร้างไฟล์แยก
        const pythonScript = `
import sys
import os

try:
    from deface.deface import anonymize_image
    import cv2
    import numpy as np
    import json

    input_path = sys.argv[1]
    output_path = sys.argv[2]

    # โหลดภาพด้วย OpenCV
    img = cv2.imread(input_path)
    if img is None:
        print(json.dumps({"success": False, "error": "Cannot read image"}))
        sys.exit(1)

    # ตรวจจับและเบลอใบหน้าด้วย CenterFace (built-in ใน deface)
    from deface.centerface import CenterFace
    centerface = CenterFace(in_shape=None, backend='auto')
    
    h, w = img.shape[:2]
    dets, lms = centerface(img, h, w, threshold=0.2)

    face_count = len(dets)

    for det in dets:
        x1, y1, x2, y2, score = det
        x1, y1, x2, y2 = int(x1), int(y1), int(x2), int(y2)
        # ขยายพื้นที่เล็กน้อย (20%) เพื่อให้เบลอครอบคลุมหน้าทั้งใบ
        pad_x = int((x2 - x1) * 0.2)
        pad_y = int((y2 - y1) * 0.2)
        x1 = max(0, x1 - pad_x)
        y1 = max(0, y1 - pad_y)
        x2 = min(w, x2 + pad_x)
        y2 = min(h, y2 + pad_y)

        face_region = img[y1:y2, x1:x2]
        if face_region.size > 0:
            # เบลอแบบ Gaussian เพื่อให้ดูนุ่มนวล
            blur_strength = max(31, min(71, int((x2 - x1) * 0.8)))
            if blur_strength % 2 == 0:
                blur_strength += 1
            blurred = cv2.GaussianBlur(face_region, (blur_strength, blur_strength), 0)
            img[y1:y2, x1:x2] = blurred

    # บันทึกภาพผลลัพธ์
    cv2.imwrite(output_path, img)
    print(json.dumps({"success": True, "faces_found": face_count}))

except Exception as e:
    print(json.dumps({"success": False, "error": str(e)}))
    sys.exit(1)
`;

        const python = spawn('python3', ['-c', pythonScript, inputPath, outputPath]);

        let stdout = '';
        let stderr = '';

        python.stdout.on('data', (data) => { stdout += data.toString(); });
        python.stderr.on('data', (data) => { stderr += data.toString(); });

        python.on('close', (code) => {
            try {
                const result = JSON.parse(stdout.trim());
                if (result.success && fs.existsSync(outputPath)) {
                    console.log(`[FaceBlur] ✅ Done — ${result.faces_found} face(s) blurred: ${path.basename(outputPath)}`);
                    resolve({ success: true, outputPath });
                } else {
                    console.warn(`[FaceBlur] ⚠️ Failed: ${result.error || stderr} — using original`);
                    resolve({ success: false, outputPath: inputPath, error: result.error });
                }
            } catch (e) {
                console.warn(`[FaceBlur] ⚠️ Parse error: ${e.message} | stdout: ${stdout} | stderr: ${stderr}`);
                // Fallback: ใช้ไฟล์ต้นฉบับ ไม่ขัดขวาง upload
                resolve({ success: false, outputPath: inputPath, error: e.message });
            }
        });

        python.on('error', (err) => {
            console.warn(`[FaceBlur] ⚠️ Spawn error: ${err.message} — using original`);
            resolve({ success: false, outputPath: inputPath, error: err.message });
        });

        // Timeout 30 วินาทีต่อภาพ — ไม่ให้รอนานเกินไป
        setTimeout(() => {
            python.kill();
            console.warn(`[FaceBlur] ⏱️ Timeout — using original: ${path.basename(inputPath)}`);
            resolve({ success: false, outputPath: inputPath, error: 'Timeout' });
        }, 30000);
    });
}

/**
 * ประมวลผลหลายภาพพร้อมกัน (แบบ Sequential เพื่อประหยัด CPU)
 * @param {Array<{input: string, output: string}>} imagePairs
 * @returns {Promise<Array<{success: boolean, outputPath: string}>>}
 */
async function blurFacesInImages(imagePairs) {
    const results = [];
    for (const pair of imagePairs) {
        const result = await blurFacesInImage(pair.input, pair.output);
        results.push(result);
    }
    return results;
}

module.exports = { blurFacesInImage, blurFacesInImages };
