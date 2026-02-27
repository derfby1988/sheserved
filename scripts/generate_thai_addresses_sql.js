#!/usr/bin/env node
/**
 * Script: ดาวน์โหลดข้อมูลที่อยู่ไทย (ครบทุกตำบลทั่วประเทศ) แล้วสร้างไฟล์ SQL INSERT
 * Source: jquery.Thailand.js (Open Source Thai Address Database)
 * 
 * Usage: node scripts/generate_thai_addresses_sql.js
 * Output: supabase/migrations/20260227215500_thai_addresses_seed.sql
 */

const https = require('https');
const fs = require('fs');
const path = require('path');

const DATA_URL = 'https://raw.githubusercontent.com/earthchie/jquery.Thailand.js/master/jquery.Thailand.js/database/raw_database/raw_database.json';
const OUTPUT_PATH = path.join(__dirname, '..', 'supabase', 'migrations', '20260227215500_thai_addresses_seed.sql');

function downloadJSON(url) {
    return new Promise((resolve, reject) => {
        https.get(url, (res) => {
            let data = '';
            res.on('data', (chunk) => (data += chunk));
            res.on('end', () => {
                try {
                    resolve(JSON.parse(data));
                } catch (e) {
                    reject(e);
                }
            });
            res.on('error', reject);
        }).on('error', reject);
    });
}

function escapeSql(str) {
    return str.replace(/'/g, "''");
}

async function main() {
    console.log('📥 กำลังดาวน์โหลดข้อมูลที่อยู่ไทย...');
    const records = await downloadJSON(DATA_URL);
    console.log(`✅ ดาวน์โหลดเรียบร้อย: ${records.length} ตำบลทั่วประเทศ`);

    // Deduplicate (บางแหล่งข้อมูลมีซ้ำ)
    const seen = new Set();
    const unique = records.filter((r) => {
        const key = `${r.zipcode}-${r.province}-${r.amphoe}-${r.district}`;
        if (seen.has(key)) return false;
        seen.add(key);
        return true;
    });
    console.log(`📊 หลัง Deduplicate: ${unique.length} รายการ`);

    // สร้าง SQL
    let sql = `-- =====================================================\n`;
    sql += `-- Thai Address Seed Data\n`;
    sql += `-- ข้อมูลที่อยู่ไทยครบทุกตำบลทั่วประเทศ (${unique.length} รายการ)\n`;
    sql += `-- Source: jquery.Thailand.js Open Source Database\n`;
    sql += `-- Generated: ${new Date().toISOString()}\n`;
    sql += `-- =====================================================\n\n`;
    sql += `-- ลบข้อมูลเดิม (ถ้ามี)\n`;
    sql += `TRUNCATE TABLE public.thai_addresses RESTART IDENTITY;\n\n`;

    // แบ่ง batch ละ 500 rows เพื่อไม่ให้ SQL ใหญ่เกินไป
    const BATCH_SIZE = 500;
    for (let i = 0; i < unique.length; i += BATCH_SIZE) {
        const batch = unique.slice(i, i + BATCH_SIZE);
        sql += `INSERT INTO public.thai_addresses (postal_code, province, district, sub_district) VALUES\n`;
        sql += batch
            .map((r, idx) => {
                const zipcode = String(r.zipcode).padStart(5, '0');
                const province = escapeSql(r.province);
                const amphoe = escapeSql(r.amphoe);
                const tambon = escapeSql(r.district);
                const end = idx === batch.length - 1 ? ';' : ',';
                return `  ('${zipcode}', '${province}', '${amphoe}', '${tambon}')${end}`;
            })
            .join('\n');
        sql += '\n\n';
    }

    // เขียนไฟล์
    fs.mkdirSync(path.dirname(OUTPUT_PATH), { recursive: true });
    fs.writeFileSync(OUTPUT_PATH, sql, 'utf8');
    console.log(`\n✅ สร้างไฟล์ SQL เรียบร้อย: ${OUTPUT_PATH}`);
    console.log(`📊 ขนาดไฟล์: ${(fs.statSync(OUTPUT_PATH).size / 1024).toFixed(1)} KB`);

    // สรุปสถิติ
    const provinces = new Set(unique.map(r => r.province));
    const amphoes = new Set(unique.map(r => `${r.province}-${r.amphoe}`));
    console.log(`\n📋 สรุป:`);
    console.log(`   จังหวัด: ${provinces.size}`);
    console.log(`   อำเภอ/เขต: ${amphoes.size}`);
    console.log(`   ตำบล/แขวง: ${unique.length}`);
    console.log(`   รหัสไปรษณีย์: ${new Set(unique.map(r => r.zipcode)).size}`);
}

main().catch(console.error);
