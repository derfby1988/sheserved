/**
 * InventoryAlertChecker (Scheduled Job)
 * =====================================================
 * ตรวจสอบสต็อกสินค้าและสร้างแจ้งเตือนอัตโนมัติ (Low Stock, Expiry Warning, Expired)
 *
 * ทำงานทุก __ ชั่วโมง (กำหนดด้วย INVENTORY_ALERT_CHECK_INTERVAL_MS ใน .env)
 * ค่า default: ทุก 24 ชั่วโมง (86400000 ms)
 *
 * การทำงาน:
 *   1. ดึงรายการ profession_id ทั้งหมดที่มี inventory_items
 *   2. เรียก RPC check_inventory_alerts(p_profession_id) สำหรับแต่ละ profession
 *   3. บันทึกผลลัพธ์ลง log
 *
 * Dependencies: @supabase/supabase-js
 */

const { createClient } = require('@supabase/supabase-js');

const supabase = createClient(
    process.env.SUPABASE_URL,
    process.env.SUPABASE_SERVICE_KEY || process.env.SUPABASE_ANON_KEY
);

const CHECK_INTERVAL_MS = parseInt(process.env.INVENTORY_ALERT_CHECK_INTERVAL_MS || String(24 * 60 * 60 * 1000));

let _intervalHandle = null;
let _isRunning = false;

// =====================================================
// START / STOP
// =====================================================

/**
 * เริ่ม Scheduled Job
 * เรียกครั้งเดียวใน server.js ตอน startup
 */
function start() {
    if (_intervalHandle) {
        console.warn('[InventoryAlertChecker] Already running — skipping start()');
        return;
    }

    console.log(`[InventoryAlertChecker] Started (interval=${CHECK_INTERVAL_MS / 3600000} hours)`);

    // รันทันทีครั้งแรก แล้วค่อย interval
    _runCheck();
    _intervalHandle = setInterval(_runCheck, CHECK_INTERVAL_MS);
}

/**
 * หยุด Scheduled Job (สำหรับ graceful shutdown)
 */
function stop() {
    if (_intervalHandle) {
        clearInterval(_intervalHandle);
        _intervalHandle = null;
        console.log('[InventoryAlertChecker] Stopped');
    }
}

// =====================================================
// MAIN CHECK LOOP
// =====================================================

async function _runCheck() {
    if (_isRunning) {
        console.log('[InventoryAlertChecker] Previous check still running — skipping');
        return;
    }

    _isRunning = true;
    const now = new Date().toISOString();

    try {
        // ดึง profession_id ทั้งหมดที่มี inventory_items
        const { data: professions, error } = await supabase
            .from('inventory_items')
            .select('profession_id')
            .eq('is_active', true)
            .limit(1000);

        if (error) {
            console.error('[InventoryAlertChecker] Query professions error:', error.message);
            return;
        }

        if (!professions || professions.length === 0) {
            console.log('[InventoryAlertChecker] No active inventory items found');
            return;
        }

        // Deduplicate profession_ids
        const professionIds = [...new Set(professions.map(p => p.profession_id))];
        console.log(`[InventoryAlertChecker] Checking ${professionIds.length} profession(s)`);

        let totalAlerts = 0;
        for (const professionId of professionIds) {
            try {
                const { data: count, error: rpcError } = await supabase
                    .rpc('check_inventory_alerts', { p_profession_id: professionId });

                if (rpcError) {
                    console.error(`[InventoryAlertChecker] RPC error for profession=${professionId}:`, rpcError.message);
                    continue;
                }

                const alertCount = count || 0;
                if (alertCount > 0) {
                    console.log(`[InventoryAlertChecker] Profession ${professionId}: ${alertCount} alert(s) created`);
                }
                totalAlerts += alertCount;
            } catch (profErr) {
                console.error(`[InventoryAlertChecker] Error processing profession=${professionId}:`, profErr.message);
            }
        }

        console.log(`[InventoryAlertChecker] ✅ Completed at ${now}. Total alerts created: ${totalAlerts}`);

    } catch (err) {
        console.error('[InventoryAlertChecker] Unexpected error in check loop:', err);
    } finally {
        _isRunning = false;
    }
}

module.exports = { start, stop };
