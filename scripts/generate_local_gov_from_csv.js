#!/usr/bin/env node
/**
 * สร้าง SQL อัปเดต local_gov_type จากข้อมูลจริง DLA CSV
 * (กรมส่งเสริมการปกครองท้องถิ่น)
 *
 * CSV มีข้อมูลระดับ ตำบล → ประเภท อปท. ครบทุกตำบลทั่วประเทศ
 * columns: จังหวัด,อำเภอ,ตำบล,รหัส อปท.,ประเภท อปท.,อปท.,...
 */

const fs = require('fs');
const path = require('path');

const CSV_PATH = path.join(__dirname, '..', 'tmp', 'dla_tambon.csv');
const OUTPUT_PATH = path.join(__dirname, '..', 'supabase', 'migrations', '20260227223500_local_gov_type_seed.sql');

function escapeSql(str) {
    return (str || '').replace(/'/g, "''").trim();
}

function mapGovType(orgType) {
    if (!orgType) return null;
    const t = orgType.trim();
    if (t === 'เทศบาลนคร') return 'municipality_n';
    if (t === 'เทศบาลเมือง') return 'municipality_m';
    if (t === 'เทศบาลตำบล') return 'municipality_t';
    if (t === 'อบต.') return 'sao';
    if (t === 'อบจ.') return null; // อบจ. ไม่ใช่ระดับตำบล ข้าม
    if (t === 'ท้องถิ่นรูปแบบพิเศษ') return null; // กทม./พัทยา จัดการแยก
    return null;
}

function main() {
    if (!fs.existsSync(CSV_PATH)) {
        console.error('❌ ไม่พบ', CSV_PATH);
        process.exit(1);
    }

    const raw = fs.readFileSync(CSV_PATH, 'utf8');
    // Remove BOM
    const clean = raw.replace(/^\uFEFF/, '');
    const lines = clean.split('\n').filter(l => l.trim());

    console.log(`📋 อ่าน ${lines.length} บรรทัด (รวม header)`);

    // Parse CSV
    // columns: จังหวัด(0),อำเภอ(1),ตำบล(2),รหัส อปท.(3),ประเภท อปท.(4),ชื่ออปท.(5),...
    const records = [];
    for (let i = 1; i < lines.length; i++) {
        const cols = lines[i].split(',');
        if (cols.length < 6) continue;
        const province = cols[0].trim();
        const district = cols[1].trim();
        const subDistrict = cols[2].trim();
        const orgType = cols[4].trim();
        const orgName = cols[5].trim(); // ชื่อ อปท. สำคัญมากสำหรับแมพ
        const govType = mapGovType(orgType);

        if (!govType || !province || !district || !subDistrict) continue;
        records.push({ province, district, subDistrict, govType, orgName });
    }

    console.log(`📋 Records จาก CSV: ${records.length}`);

    // สรุปจำนวนตามประเภท
    const typeCounts = {};
    for (const r of records) {
        typeCounts[r.govType] = (typeCounts[r.govType] || 0) + 1;
    }
    console.log('\n📊 สรุปจากข้อมูล DLA CSV:');
    for (const [type, count] of Object.entries(typeCounts).sort((a, b) => b[1] - a[1])) {
        console.log(`   ${type}: ${count} ตำบล`);
    }

    // ========================================================================
    // Deduplicate: ตำบลเดียวกันอาจปรากฏหลายครั้ง (อยู่ภายใต้หลาย อปท.)
    //
    // Logic ที่ถูกต้อง: ดูว่า อปท. ไหน "เป็นเจ้าของตำบลนั้น"
    // → ถ้า orgName ตรงกับ subDistrict = อปท. หลักของตำบลนั้น ใช้เลย
    // → ถ้าไม่มีตรง → ใช้ priority ต่ำสุด (sao) เป็น default
    //
    // ตัวอย่าง:
    //   ตาก,เมืองตาก,ป่ามะม่วง,เทศบาลเมือง,ตาก      ← overlap (ชื่อ อปท.="ตาก" ≠ "ป่ามะม่วง")
    //   ตาก,เมืองตาก,ป่ามะม่วง,อบต.,ป่ามะม่วง         ← ตรง! (ชื่อ อปท.="ป่ามะม่วง" = ตำบล)
    // ========================================================================
    const uniqueMap = {}; // key: "province|district|subDistrict" → { govType, isDirectMatch }

    for (const r of records) {
        const key = `${r.province}|${r.district}|${r.subDistrict}`;
        const isDirectMatch = r.orgName === r.subDistrict;
        const existing = uniqueMap[key];

        if (!existing) {
            // ยังไม่มี → ใส่เลย
            uniqueMap[key] = { govType: r.govType, isDirectMatch };
        } else if (isDirectMatch && !existing.isDirectMatch) {
            // entry ใหม่ชื่อตรงกับตำบล → ใช้ entry ใหม่ (เป็นเจ้าของจริง)
            uniqueMap[key] = { govType: r.govType, isDirectMatch: true };
        }
        // ถ้า existing ตรงอยู่แล้ว หรือทั้งสองไม่ตรง → เก็บ existing ไว้
    }

    console.log(`\n📋 Unique ตำบล: ${Object.keys(uniqueMap).length}`);

    // สรุปหลัง deduplicate
    const finalCounts = {};
    for (const { govType } of Object.values(uniqueMap)) {
        finalCounts[govType] = (finalCounts[govType] || 0) + 1;
    }
    console.log('\n📊 สรุปหลัง deduplicate (ใช้ orgName ตรงกับตำบล):');
    for (const [type, count] of Object.entries(finalCounts).sort((a, b) => b[1] - a[1])) {
        console.log(`   ${type}: ${count} ตำบล`);
    }

    // ตรวจสอบ ป่ามะม่วง
    const testKey = 'ตาก|เมืองตาก|ป่ามะม่วง';
    if (uniqueMap[testKey]) {
        console.log(`\n🔍 ป่ามะม่วง: ${uniqueMap[testKey].govType} (directMatch: ${uniqueMap[testKey].isDirectMatch})`);
    }

    // จัดกลุ่ม batch UPDATE ตาม govType + province + district
    const batchUpdates = {}; // key: "govType|province|district" → [subDistricts]
    for (const [key, { govType }] of Object.entries(uniqueMap)) {
        if (govType === 'sao') continue; // skip default
        const [prov, dist, sub] = key.split('|');
        const batchKey = `${govType}|${prov}|${dist}`;
        if (!batchUpdates[batchKey]) batchUpdates[batchKey] = [];
        batchUpdates[batchKey].push(sub);
    }

    // สร้าง SQL
    let sql = `-- =====================================================\n`;
    sql += `-- อัปเดต local_gov_type จากข้อมูลจริง DLA Open Data (CSV)\n`;
    sql += `-- แหล่งข้อมูล: กรมส่งเสริมการปกครองท้องถิ่น (opendata.dla.go.th)\n`;
    sql += `-- จำนวน: ${Object.keys(uniqueMap).length} ตำบลทั่วประเทศ\n`;
    sql += `-- Generated: ${new Date().toISOString()}\n`;
    sql += `-- =====================================================\n\n`;

    sql += `-- Step 1: Reset ทั้งหมดเป็น อบต. (default)\n`;
    sql += `UPDATE public.thai_addresses SET local_gov_type = 'sao';\n\n`;

    sql += `-- Step 2: กรุงเทพมหานคร → bma\n`;
    sql += `UPDATE public.thai_addresses SET local_gov_type = 'bma'\n`;
    sql += `  WHERE province = 'กรุงเทพมหานคร';\n\n`;

    sql += `-- Step 3: เมืองพัทยา → pattaya\n`;
    sql += `UPDATE public.thai_addresses SET local_gov_type = 'pattaya'\n`;
    sql += `  WHERE province = 'ชลบุรี' AND district = 'บางละมุง'\n`;
    sql += `  AND sub_district IN ('นาเกลือ', 'หนองปรือ', 'หนองปลาไหล', 'โป่ง');\n\n`;

    // เทศบาลนคร
    const nEntries = Object.entries(batchUpdates).filter(([k]) => k.startsWith('municipality_n|'));
    sql += `-- Step 4: เทศบาลนคร (${nEntries.reduce((s, [, v]) => s + v.length, 0)} ตำบล)\n`;
    for (const [key, subs] of nEntries) {
        const [, prov, dist] = key.split('|');
        const subList = subs.map(s => `'${escapeSql(s)}'`).join(', ');
        sql += `UPDATE public.thai_addresses SET local_gov_type = 'municipality_n'\n`;
        sql += `  WHERE province = '${escapeSql(prov)}' AND district = '${escapeSql(dist)}' AND sub_district IN (${subList});\n`;
    }
    sql += '\n';

    // เทศบาลเมือง
    const mEntries = Object.entries(batchUpdates).filter(([k]) => k.startsWith('municipality_m|'));
    sql += `-- Step 5: เทศบาลเมือง (${mEntries.reduce((s, [, v]) => s + v.length, 0)} ตำบล)\n`;
    for (const [key, subs] of mEntries) {
        const [, prov, dist] = key.split('|');
        const subList = subs.map(s => `'${escapeSql(s)}'`).join(', ');
        sql += `UPDATE public.thai_addresses SET local_gov_type = 'municipality_m'\n`;
        sql += `  WHERE province = '${escapeSql(prov)}' AND district = '${escapeSql(dist)}' AND sub_district IN (${subList});\n`;
    }
    sql += '\n';

    // เทศบาลตำบล
    const tEntries = Object.entries(batchUpdates).filter(([k]) => k.startsWith('municipality_t|'));
    sql += `-- Step 6: เทศบาลตำบล (${tEntries.reduce((s, [, v]) => s + v.length, 0)} ตำบล)\n`;
    for (const [key, subs] of tEntries) {
        const [, prov, dist] = key.split('|');
        const subList = subs.map(s => `'${escapeSql(s)}'`).join(', ');
        sql += `UPDATE public.thai_addresses SET local_gov_type = 'municipality_t'\n`;
        sql += `  WHERE province = '${escapeSql(prov)}' AND district = '${escapeSql(dist)}' AND sub_district IN (${subList});\n`;
    }
    sql += '\n';

    sql += `-- =====================================================\n`;
    sql += `-- สรุปสถิติ (ตรวจสอบหลังรัน)\n`;
    sql += `-- SELECT local_gov_type, COUNT(*) FROM thai_addresses GROUP BY local_gov_type ORDER BY 2 DESC;\n`;
    sql += `-- =====================================================\n`;

    fs.writeFileSync(OUTPUT_PATH, sql, 'utf8');
    console.log(`\n✅ สร้างไฟล์ SQL เรียบร้อย: ${OUTPUT_PATH}`);
    console.log(`📊 ขนาดไฟล์: ${(fs.statSync(OUTPUT_PATH).size / 1024).toFixed(1)} KB`);
}

main();
