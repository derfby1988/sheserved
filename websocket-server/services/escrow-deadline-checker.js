/**
 * EscrowDeadlineChecker (Scheduled Job)
 * =====================================================
 * ตรวจสอบ Grace Period ที่เกิน Deadline และดำเนินการโอนเงิน Beneficiary
 *
 * ทำงานทุก __ นาที (กำหนดด้วย ESCROW_CHECK_INTERVAL_MS ใน .env)
 * ค่า default: ทุก 15 นาที
 *
 * กรณีที่ตรวจสอบ:
 *   1. pause_deadline — คำร้องถูกระงับ (Consensus ไม่ผ่าน) จนหมดเวลา
 *   2. transfer_failed deadline — Reporter ไม่แก้ไขบัญชีภายใน grace period
 *   3. cancellation deadline — ผู้บริจาคไม่ตัดสินใจ Refund vs Beneficiary
 *
 * Dependencies: @supabase/supabase-js
 */

const { createClient } = require('@supabase/supabase-js');
const socketService = require('./socket-service');

const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_SERVICE_KEY = process.env.SUPABASE_SERVICE_KEY || process.env.SUPABASE_SERVICE_ROLE_KEY;

if (!SUPABASE_URL || !SUPABASE_SERVICE_KEY) {
  console.error('❌ FATAL: SUPABASE_URL and SUPABASE_SERVICE_KEY (or SUPABASE_SERVICE_ROLE_KEY) are required for escrow deadline checker. Exiting.');
  if (process.env.NODE_ENV === 'production') process.exit(1);
}

const supabase = (SUPABASE_URL && SUPABASE_SERVICE_KEY)
  ? createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY)
  : null;

const CHECK_INTERVAL_MS = parseInt(process.env.ESCROW_CHECK_INTERVAL_MS || String(15 * 60 * 1000));

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
        console.warn('[EscrowDeadlineChecker] Already running — skipping start()');
        return;
    }

    console.log(`[EscrowDeadlineChecker] Started (interval=${CHECK_INTERVAL_MS / 60000} min)`);

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
        console.log('[EscrowDeadlineChecker] Stopped');
    }
}

// =====================================================
// MAIN CHECK LOOP
// =====================================================

async function _runCheck() {
    if (_isRunning) {
        console.log('[EscrowDeadlineChecker] Previous check still running — skipping');
        return;
    }

    _isRunning = true;
    const now = new Date().toISOString();

    try {
        await Promise.all([
            _checkPauseDeadlines(now),
            _checkCancellationDeadlines(now),
            _checkTransferFailureDeadlines(now),
        ]);
    } catch (err) {
        console.error('[EscrowDeadlineChecker] Unexpected error in check loop:', err);
    } finally {
        _isRunning = false;
    }
}

// =====================================================
// CASE 1: Pause Deadline (Consensus ไม่ผ่าน)
// =====================================================

/**
 * ดึงคำร้องที่ถูกระงับและเลย pause_deadline แล้ว
 * → โอนเงินใน escrow ให้ Beneficiary ถาวร
 */
async function _checkPauseDeadlines(now) {
    const { data: pausedRequests, error } = await supabase
        .from('donation_requests')
        .select('id, category_id, current_amount, fee_snapshot')
        .eq('is_paused', true)
        .eq('escrow_status', 'in_escrow')
        .lt('pause_deadline', now); // deadline ล่วงเลยแล้ว

    if (error) {
        console.error('[EscrowDeadlineChecker] pause_deadline query error:', error.message);
        return;
    }

    if (!pausedRequests || pausedRequests.length === 0) return;

    console.log(`[EscrowDeadlineChecker] Found ${pausedRequests.length} request(s) with expired pause deadline`);

    for (const req of pausedRequests) {
        await _transferToBeneficiary(req.id, req.category_id, 'pause_deadline');
    }
}

// =====================================================
// CASE 2: Cancellation Deadline
// =====================================================

/**
 * ดึงคำร้องที่ถูกยกเลิก และ cancellation_grace_hours ล่วงเลยแล้ว
 * โดยที่ผู้บริจาคยังไม่ตัดสินใจ → โอนให้ Beneficiary อัตโนมัติ
 */
async function _checkCancellationDeadlines(now) {
    // ดึงคำร้องที่ closed_reason = 'manual_close' และมีเงินใน escrow ค้างอยู่
    const { data: cancelledRequests, error } = await supabase
        .from('donation_requests')
        .select('id, category_id, closed_at, fee_snapshot')
        .eq('closed_reason', 'manual_close')
        .eq('escrow_status', 'in_escrow');

    if (error) {
        console.error('[EscrowDeadlineChecker] cancellation query error:', error.message);
        return;
    }

    if (!cancelledRequests || cancelledRequests.length === 0) return;

    for (const req of cancelledRequests) {
        // ดึง cancellation_grace_hours ของ category นี้
        const { data: cat } = await supabase
            .from('donation_categories')
            .select('cancellation_grace_hours')
            .eq('id', req.category_id)
            .single();

        const graceHours = cat?.cancellation_grace_hours ?? 24;
        const closedAt = new Date(req.closed_at);
        const deadline = new Date(closedAt.getTime() + graceHours * 60 * 60 * 1000);

        if (new Date(now) >= deadline) {
            console.log(`[EscrowDeadlineChecker] Cancellation deadline exceeded for request=${req.id}`);
            await _transferToBeneficiary(req.id, req.category_id, 'cancellation');
        }
    }
}

// =====================================================
// CASE 3: Transfer Failure Deadline
// =====================================================

/**
 * ดึง transactions ที่โอนให้ Responder ไม่สำเร็จ (transfer_failed)
 * และเกิน transfer_failure_grace_hours แล้ว
 * → โอนส่วนนั้นไปให้ Beneficiary อัตโนมัติ
 */
async function _checkTransferFailureDeadlines(now) {
    const { data: failedTxs, error } = await supabase
        .from('donation_transactions')
        .select('id, request_id, updated_at')
        .eq('status', 'transfer_failed');

    if (error) {
        console.error('[EscrowDeadlineChecker] transfer_failed query error:', error.message);
        return;
    }

    if (!failedTxs || failedTxs.length === 0) return;

    // หา categories
    const reqIds = [...new Set(failedTxs.map(t => t.request_id))];
    const { data: reqs } = await supabase
        .from('donation_requests')
        .select('id, category_id')
        .in('id', reqIds);

    const reqMap = (reqs || []).reduce((acc, r) => { acc[r.id] = r.category_id; return acc; }, {});
    const catIds = [...new Set(Object.values(reqMap))];
    
    const { data: cats } = await supabase
        .from('donation_categories')
        .select('id, transfer_failure_grace_hours')
        .in('id', catIds);

    const catMap = (cats || []).reduce((acc, c) => { acc[c.id] = c.transfer_failure_grace_hours; return acc; }, {});

    for (const tx of failedTxs) {
        const categoryId = reqMap[tx.request_id];
        if (!categoryId) continue;

        const graceHours = catMap[categoryId] || 48; // Default 48h
        const failedAt = new Date(tx.updated_at);
        const deadline = new Date(failedAt.getTime() + graceHours * 60 * 60 * 1000);

        if (new Date(now) >= deadline) {
            console.log(`[EscrowDeadlineChecker] Transfer failure deadline exceeded for request=${tx.request_id}`);
            await _transferToBeneficiary(tx.request_id, categoryId, 'transfer_failed');
        }
    }
}

// =====================================================
// CORE: โอนเงินให้ Beneficiary ถาวร
// =====================================================

/**
 * โอนเงินจาก donation_transactions (in_escrow) ไปยัง Beneficiary ถาวร
 * บันทึกลง beneficiary_transfer_logs และอัปเดตสถานะคำร้อง
 *
 * @param {string} requestId
 * @param {string} categoryId
 * @param {'pause_deadline'|'transfer_failed'|'cancellation'} reason
 */
async function _transferToBeneficiary(requestId, categoryId, reason) {
    console.log(`[EscrowDeadlineChecker] Transferring to beneficiary: request=${requestId} reason=${reason}`);

    try {
        // 1. หา Beneficiary ที่ใช้งานได้ (category-specific หรือ global default)
        const { data: beneficiaryId } = await supabase
            .rpc('get_effective_beneficiary', { p_category_id: categoryId });

        if (!beneficiaryId) {
            console.error(`[EscrowDeadlineChecker] No beneficiary found for category=${categoryId} — BLOCKED`);
            _emitAdminAlert(requestId, 'no_beneficiary', 'ไม่มี Beneficiary ที่ใช้งานได้ — กรุณาตั้งค่าใน Admin');
            // อัปเดต transaction → transfer_blocked_no_beneficiary
            await supabase
                .from('donation_transactions')
                .update({ status: 'transfer_blocked_no_beneficiary', updated_at: new Date().toISOString() })
                .eq('request_id', requestId)
                .eq('status', 'in_escrow');
            return;
        }

        // 2. ดึง in_escrow และ transfer_failed transactions และ lock
        const { data: transactions } = await supabase
            .from('donation_transactions')
            .select('id, amount, status')
            .eq('request_id', requestId)
            .in('status', ['in_escrow', 'transfer_failed']);

        if (!transactions || transactions.length === 0) {
            console.log(`[EscrowDeadlineChecker] No in_escrow or transfer_failed transactions for request=${requestId}`);
            return;
        }

        const txIds = transactions.map(t => t.id);
        const totalAmount = transactions.reduce((sum, t) => sum + parseFloat(t.amount), 0);

        // Lock ก่อน
        await supabase
            .from('donation_transactions')
            .update({ status: 'processing_transfer', updated_at: new Date().toISOString() })
            .in('id', txIds)
            .in('status', ['in_escrow', 'transfer_failed']);

        // 3. บันทึก beneficiary_transfer_logs
        const { error: transferLogError } = await supabase
            .from('beneficiary_transfer_logs')
            .insert({
                request_id: requestId,
                beneficiary_id: beneficiaryId,
                amount: Math.round(totalAmount * 100) / 100,
                reason,
                transferred_at: new Date().toISOString(),
                note: `Auto-transfer by EscrowDeadlineChecker (${reason})`,
            });

        if (transferLogError) throw new Error(`Transfer log insert: ${transferLogError.message}`);

        // 4. อัปเดต transaction → transferred_to_beneficiary
        await supabase
            .from('donation_transactions')
            .update({
                status: 'transferred_to_beneficiary',
                updated_at: new Date().toISOString(),
            })
            .in('id', txIds);

        // 5. อัปเดต donation_requests
        await supabase
            .from('donation_requests')
            .update({
                escrow_status: 'returned',
                beneficiary_transfer_at: new Date().toISOString(),
                closed_at: new Date().toISOString(),
                closed_reason: 'transferred_to_beneficiary',
                updated_at: new Date().toISOString(),
            })
            .eq('id', requestId);

        // 6. Emit WebSocket notification
        _emitDonationSystemMessage(requestId, {
            type: 'donation-transferred-to-beneficiary',
            message: `เงินบริจาครวม ฿${totalAmount.toFixed(2)} ถูกโอนให้หน่วยงานผู้รับมรดกแล้ว (${reason})`,
            amount: totalAmount,
            reason,
        });

        console.log(`[EscrowDeadlineChecker] ✅ Transferred ฿${totalAmount.toFixed(2)} to beneficiary=${beneficiaryId} (reason=${reason})`);

    } catch (err) {
        console.error(`[EscrowDeadlineChecker] _transferToBeneficiary error (request=${requestId}):`, err);

        // Rollback lock: คืน status กลับเป็นของเดิม เพื่อให้ retry ได้ในรอบหน้า
        try {
            await supabase
                .from('donation_transactions')
                .update({ status: reason === 'transfer_failed' ? 'transfer_failed' : 'in_escrow', updated_at: new Date().toISOString() })
                .eq('request_id', requestId)
                .eq('status', 'processing_transfer');
        } catch (rollbackErr) {
            console.error('[EscrowDeadlineChecker] Rollback failed:', rollbackErr);
        }
    }
}

// =====================================================
// HELPERS
// =====================================================

function _emitDonationSystemMessage(requestId, payload) {
    try {
        const io = socketService.getIO();
        if (io) {
            io.emit('donation-system-message', {
                requestId,
                timestamp: new Date().toISOString(),
                ...payload,
            });
        }
    } catch (e) {
        console.warn('[EscrowDeadlineChecker] Failed to emit WebSocket:', e.message);
    }
}

function _emitAdminAlert(requestId, alertType, message) {
    try {
        const io = socketService.getIO();
        if (io) {
            io.emit('admin-alert', { requestId, alertType, message, timestamp: new Date().toISOString() });
        }
    } catch (e) { /* ignore */ }
}

module.exports = { start, stop };
