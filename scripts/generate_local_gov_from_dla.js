#!/usr/bin/env node
/**
 * ดาวน์โหลดข้อมูลจาก DLA Open Data (กรมส่งเสริมการปกครองท้องถิ่น)
 * แล้ว generate SQL อัปเดต local_gov_type ตามข้อมูลจริง
 *
 * Usage: node scripts/generate_local_gov_from_dla.js
 * Output: supabase/migrations/20260227223500_local_gov_type_seed.sql
 */

const fs = require('fs');
const path = require('path');
const https = require('https');
const http = require('http');

const DLA_JSON_URL = 'https://wsg.dla.go.th/eservices/wsjson?user=public_dla&password=public_dla&queryCode=DLA_INFO62_0040';
const DLA_CSV_URL = 'https://opendata.dla.go.th/dataset/1a668c66-c6d6-4c94-bc0f-e57c81813eb8/resource/e9d61e15-d28f-467e-a018-98e0647ef2f4/download/re01_9112566tambon.csv';
const OUTPUT_PATH = path.join(__dirname, '..', 'supabase', 'migrations', '20260227223500_local_gov_type_seed.sql');
const CACHE_PATH = path.join(__dirname, '..', 'tmp', 'dla_data.json');

function download(url) {
    return new Promise((resolve, reject) => {
        const handler = url.startsWith('https') ? https : http;
        handler.get(url, { headers: { 'User-Agent': 'Mozilla/5.0' } }, (res) => {
            // Handle redirects
            if (res.statusCode >= 300 && res.statusCode < 400 && res.headers.location) {
                return download(res.headers.location).then(resolve).catch(reject);
            }
            let data = '';
            res.on('data', chunk => data += chunk);
            res.on('end', () => resolve(data));
            res.on('error', reject);
        }).on('error', reject);
    });
}

function escapeSql(str) {
    return str.replace(/'/g, "''").trim();
}

// แมพประเภท อปท. จาก DLA → local_gov_type ของเรา
function mapGovType(dlaType) {
    if (!dlaType) return 'sao';
    const t = dlaType.trim();
    if (t.includes('เทศบาลนคร')) return 'municipality_n';
    if (t.includes('เทศบาลเมือง')) return 'municipality_m';
    if (t.includes('เทศบาลตำบล')) return 'municipality_t';
    if (t.includes('อบต') || t.includes('องค์การบริหารส่วนตำบล')) return 'sao';
    if (t.includes('กรุงเทพมหานคร')) return 'bma';
    if (t.includes('พัทยา')) return 'pattaya';
    return 'sao';
}

async function main() {
    console.log('📥 กำลังดาวน์โหลดข้อมูลจาก DLA Open Data...');

    let dlaData;
    try {
        // ลองดาวน์โหลด JSON จาก DLA
        const raw = await download(DLA_JSON_URL);
        dlaData = JSON.parse(raw);
        console.log(`✅ ได้ข้อมูล ${Array.isArray(dlaData) ? dlaData.length : 'N/A'} records จาก DLA JSON API`);

        // Cache ข้อมูล
        const tmpDir = path.join(__dirname, '..', 'tmp');
        if (!fs.existsSync(tmpDir)) fs.mkdirSync(tmpDir, { recursive: true });
        fs.writeFileSync(CACHE_PATH, JSON.stringify(dlaData, null, 2), 'utf8');
        console.log(`💾 Cache ไว้ที่ ${CACHE_PATH}`);
    } catch (e) {
        console.error('❌ ดาวน์โหลด JSON ไม่สำเร็จ:', e.message);
        // ลอง CSV
        try {
            console.log('📥 ลองดาวน์โหลด CSV...');
            const csvRaw = await download(DLA_CSV_URL);
            const tmpDir = path.join(__dirname, '..', 'tmp');
            if (!fs.existsSync(tmpDir)) fs.mkdirSync(tmpDir, { recursive: true });
            fs.writeFileSync(path.join(tmpDir, 'dla_data.csv'), csvRaw, 'utf8');
            console.log(`💾 CSV saved: ${csvRaw.length} bytes`);
            // Parse CSV
            dlaData = parseCSV(csvRaw);
        } catch (e2) {
            console.error('❌ ดาวน์โหลด CSV ไม่สำเร็จ:', e2.message);
            process.exit(1);
        }
    }

    if (!Array.isArray(dlaData) || dlaData.length === 0) {
        // ถ้าเป็น object ที่มี key เช่น { result: [...] }
        if (dlaData && dlaData.result && Array.isArray(dlaData.result)) {
            dlaData = dlaData.result;
        } else {
            console.log('⚠️ ข้อมูลไม่ใช่ array, ลองดู structure:');
            console.log(JSON.stringify(dlaData).substring(0, 500));
            // ลอง keys ทั่วไป
            const keys = Object.keys(dlaData);
            for (const key of keys) {
                if (Array.isArray(dlaData[key])) {
                    dlaData = dlaData[key];
                    console.log(`📋 ใช้ key "${key}" (${dlaData.length} records)`);
                    break;
                }
            }
        }
    }

    // ดูโครงสร้างข้อมูล
    if (dlaData.length > 0) {
        console.log('\n📋 ตัวอย่างข้อมูล (record แรก):');
        console.log(JSON.stringify(dlaData[0], null, 2));
        console.log(`\n📋 Keys: ${Object.keys(dlaData[0]).join(', ')}`);
    }

    // สร้าง mapping: province + district + sub_district → gov_type
    // ค้นหา key ที่เก็บข้อมูลจังหวัด อำเภอ ตำบล ประเภท
    const sample = dlaData[0];
    const keys = Object.keys(sample);
    console.log(`\n📋 ทั้งหมด ${dlaData.length} records`);
    console.log(`📋 keys: ${keys.join(', ')}`);

    // พิมพ์ sample เพื่อดูค่า
    for (const rec of dlaData.slice(0, 5)) {
        const vals = keys.map(k => `${k}=${rec[k]}`).join(' | ');
        console.log(vals);
    }

    // Save raw data for analysis
    const tmpDir = path.join(__dirname, '..', 'tmp');
    if (!fs.existsSync(tmpDir)) fs.mkdirSync(tmpDir, { recursive: true });
    fs.writeFileSync(path.join(tmpDir, 'dla_sample.json'),
        JSON.stringify(dlaData.slice(0, 20), null, 2), 'utf8');
    console.log('💾 Sample saved to tmp/dla_sample.json');
}

function parseCSV(csvText) {
    const lines = csvText.split('\n').filter(l => l.trim());
    if (lines.length < 2) return [];
    const headers = lines[0].split(',').map(h => h.trim().replace(/"/g, ''));
    return lines.slice(1).map(line => {
        const vals = line.split(',').map(v => v.trim().replace(/"/g, ''));
        const obj = {};
        headers.forEach((h, i) => obj[h] = vals[i] || '');
        return obj;
    });
}

main();
