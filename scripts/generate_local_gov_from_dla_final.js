#!/usr/bin/env node
/**
 * สร้าง SQL อัปเดต local_gov_type จากข้อมูลจริงของ DLA
 * (กรมส่งเสริมการปกครองท้องถิ่น - opendata.dla.go.th)
 *
 * Logic: DLA ให้ข้อมูลแต่ละ อปท. (อบต./เทศบาลตำบล/เทศบาลเมือง/เทศบาลนคร)
 * พร้อมชื่อ + จังหวัด + อำเภอ → แมพกับตาราง thai_addresses ด้วย province + district + sub_district
 *
 * Usage: node scripts/generate_local_gov_from_dla_final.js
 */

const fs = require('fs');
const path = require('path');

const CACHE_PATH = path.join(__dirname, '..', 'tmp', 'dla_data.json');
const OUTPUT_PATH = path.join(__dirname, '..', 'supabase', 'migrations', '20260227223500_local_gov_type_seed.sql');

function escapeSql(str) {
    return (str || '').replace(/'/g, "''").trim();
}

function mapGovType(orgType) {
    if (!orgType) return 'sao';
    const t = orgType.trim();
    if (t === 'ทน.' || t.includes('เทศบาลนคร')) return 'municipality_n';
    if (t === 'ทม.' || t.includes('เทศบาลเมือง')) return 'municipality_m';
    if (t === 'ทต.' || t.includes('เทศบาลตำบล')) return 'municipality_t';
    if (t === 'อบต.' || t.includes('อบต')) return 'sao';
    return 'sao';
}

function main() {
    // อ่านข้อมูล DLA ที่ cache ไว้
    if (!fs.existsSync(CACHE_PATH)) {
        console.error('❌ ไม่พบ cache file — รัน generate_local_gov_from_dla.js ก่อน');
        process.exit(1);
    }

    const raw = JSON.parse(fs.readFileSync(CACHE_PATH, 'utf8'));
    const dlaRecords = raw.rows || raw.result || raw;
    if (!Array.isArray(dlaRecords)) {
        console.error('❌ ข้อมูลไม่ถูกต้อง');
        process.exit(1);
    }

    console.log(`📋 ข้อมูล DLA: ${dlaRecords.length} อปท.`);

    // วิเคราะห์จำนวนแต่ละประเภท
    const typeCounts = {};
    for (const rec of dlaRecords) {
        const t = rec.ORG_TYPE || 'unknown';
        typeCounts[t] = (typeCounts[t] || 0) + 1;
    }
    console.log('\n📊 สรุปจำนวนตามประเภท (จาก DLA):');
    for (const [type, count] of Object.entries(typeCounts).sort((a, b) => b[1] - a[1])) {
        console.log(`   ${type}: ${count} แห่ง → ${mapGovType(type)}`);
    }

    // สร้าง mapping: key = "province|amphoe|orgName" → gov_type
    // DLA ใช้ ORG_NAME ที่อาจไม่ตรงกับ sub_district name ใน thai_addresses
    // เช่น ORG_NAME="คลองท่อมเหนือ" แต่ใน thai_addresses อาจเป็น "คลองท่อมเหนือ"
    // ดังนั้นเราจะแมพด้วย province + amphoe + orgName → sub_district

    // จัดกลุ่มตาม province + amphoe
    const amphoMap = {};
    for (const rec of dlaRecords) {
        const prov = (rec.PROVINCE_NAME || '').trim();
        const amph = (rec.AMPHUR_NAME || '').trim();
        const name = (rec.ORG_NAME || '').trim();
        const type = mapGovType(rec.ORG_TYPE);
        const key = `${prov}|${amph}`;

        if (!amphoMap[key]) amphoMap[key] = [];
        amphoMap[key].push({ name, type, orgType: rec.ORG_TYPE });
    }

    // สร้าง SQL
    let sql = `-- =====================================================\n`;
    sql += `-- อัปเดต local_gov_type จากข้อมูลจริง DLA Open Data\n`;
    sql += `-- แหล่งข้อมูล: กรมส่งเสริมการปกครองท้องถิ่น (opendata.dla.go.th)\n`;
    sql += `-- ${dlaRecords.length} อปท. ทั่วประเทศ\n`;
    sql += `-- Generated: ${new Date().toISOString()}\n`;
    sql += `-- =====================================================\n\n`;

    // Step 1: Reset ทั้งหมดเป็น sao ก่อน
    sql += `-- Step 1: Reset ทั้งหมดเป็น อบต. (default)\n`;
    sql += `UPDATE public.thai_addresses SET local_gov_type = 'sao';\n\n`;

    // Step 2: กรุงเทพมหานคร
    sql += `-- Step 2: กรุงเทพมหานคร → bma\n`;
    sql += `UPDATE public.thai_addresses SET local_gov_type = 'bma'\n`;
    sql += `  WHERE province = 'กรุงเทพมหานคร';\n\n`;

    // Step 3: เมืองพัทยา
    sql += `-- Step 3: เมืองพัทยา → pattaya\n`;
    sql += `UPDATE public.thai_addresses SET local_gov_type = 'pattaya'\n`;
    sql += `  WHERE province = 'ชลบุรี' AND district = 'บางละมุง'\n`;
    sql += `  AND sub_district IN ('นาเกลือ', 'หนองปรือ', 'หนองปลาไหล', 'โป่ง');\n\n`;

    // Step 4: อัปเดตแต่ละ อปท. ที่ไม่ใช่ อบต. (เพราะ อบต. เป็น default อยู่แล้ว)
    let municipalityNCount = 0;
    let municipalityMCount = 0;
    let municipalityTCount = 0;

    // จัดกลุ่มตาม gov_type + province + amphoe → list of sub_districts
    // เพื่อ batch UPDATE ให้เร็วขึ้น
    const batchUpdates = {}; // key: "type|province|amphoe" → [sub_districts]

    for (const rec of dlaRecords) {
        const prov = (rec.PROVINCE_NAME || '').trim();
        const amph = (rec.AMPHUR_NAME || '').trim();
        const name = (rec.ORG_NAME || '').trim();
        const type = mapGovType(rec.ORG_TYPE);

        // ข้ามถ้าเป็น อบต. (default) หรือไม่มีชื่อ
        if (type === 'sao' || !name || !prov || !amph) continue;

        const key = `${type}|${prov}|${amph}`;
        if (!batchUpdates[key]) batchUpdates[key] = [];
        batchUpdates[key].push(name);

        if (type === 'municipality_n') municipalityNCount++;
        else if (type === 'municipality_m') municipalityMCount++;
        else if (type === 'municipality_t') municipalityTCount++;
    }

    // เทศบาลนคร
    sql += `-- Step 4: เทศบาลนคร (${municipalityNCount} แห่ง)\n`;
    for (const [key, names] of Object.entries(batchUpdates)) {
        const [type, prov, amph] = key.split('|');
        if (type !== 'municipality_n') continue;
        const subs = names.map(n => `'${escapeSql(n)}'`).join(', ');
        sql += `UPDATE public.thai_addresses SET local_gov_type = 'municipality_n'\n`;
        sql += `  WHERE province = '${escapeSql(prov)}' AND district = '${escapeSql(amph)}' AND sub_district IN (${subs});\n`;
    }
    sql += '\n';

    // เทศบาลเมือง
    sql += `-- Step 5: เทศบาลเมือง (${municipalityMCount} แห่ง)\n`;
    for (const [key, names] of Object.entries(batchUpdates)) {
        const [type, prov, amph] = key.split('|');
        if (type !== 'municipality_m') continue;
        const subs = names.map(n => `'${escapeSql(n)}'`).join(', ');
        sql += `UPDATE public.thai_addresses SET local_gov_type = 'municipality_m'\n`;
        sql += `  WHERE province = '${escapeSql(prov)}' AND district = '${escapeSql(amph)}' AND sub_district IN (${subs});\n`;
    }
    sql += '\n';

    // เทศบาลตำบล
    sql += `-- Step 6: เทศบาลตำบล (${municipalityTCount} แห่ง)\n`;
    for (const [key, names] of Object.entries(batchUpdates)) {
        const [type, prov, amph] = key.split('|');
        if (type !== 'municipality_t') continue;
        const subs = names.map(n => `'${escapeSql(n)}'`).join(', ');
        sql += `UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'\n`;
        sql += `  WHERE province = '${escapeSql(prov)}' AND district = '${escapeSql(amph)}' AND sub_district IN (${subs});\n`;
    }
    sql += '\n';

    sql += `-- =====================================================\n`;
    sql += `-- สรุปสถิติ (ตรวจสอบหลังรัน)\n`;
    sql += `-- SELECT local_gov_type, COUNT(*) FROM thai_addresses GROUP BY local_gov_type ORDER BY 2 DESC;\n`;
    sql += `-- =====================================================\n`;

    fs.writeFileSync(OUTPUT_PATH, sql, 'utf8');
    console.log(`\n✅ สร้างไฟล์ SQL เรียบร้อย: ${OUTPUT_PATH}`);
    console.log(`📊 ขนาดไฟล์: ${(fs.statSync(OUTPUT_PATH).size / 1024).toFixed(1)} KB`);
    console.log(`\n📋 สรุป:`);
    console.log(`   เทศบาลนคร: ${municipalityNCount} แห่ง`);
    console.log(`   เทศบาลเมือง: ${municipalityMCount} แห่ง`);
    console.log(`   เทศบาลตำบล: ${municipalityTCount} แห่ง`);
    console.log(`   กรุงเทพมหานคร: 1 (ทุกเขต)`);
    console.log(`   พัทยา: 1 แห่ง`);
    console.log(`   อบต. (default): ที่เหลือทั้งหมด`);
}

main();
