/**
 * EscrowReleaseService
 * =====================================================
 * จัดการ Release Escrow เมื่อภารกิจเสร็จสมบูรณ์ (Mission Complete + Consensus)
 *
 * เรียกใช้จาก:
 *   - WebSocket event 'donate-closure-vote' (เมื่อ Responder โหวต consensus)
 *   - Admin manual release
 *
 * Flow:
 *   1. ตรวจสอบ consensus ผ่าน DB Function process_donation_consensus()
 *   2. ถ้าผ่าน → ดึง in_escrow transactions + fee snapshot
 *   3. คำนวณ FeeBreakdown (gross - fees = net)
 *   4. บันทึก donation_disbursement_logs
 *   5. อัปเดต escrow_status → released
 *   6. Emit WebSocket event ให้ทุก client ที่ subscribe
 *
 * Dependencies: @supabase/supabase-js, socket.io instance
 */

const { createClient } = require('@supabase/supabase-js');
const socketService = require('./socket-service');

// Supabase client ที่ใช้ service role (bypass RLS สำหรับ escrow operations)
// ⚠️ ต้อง set SUPABASE_SERVICE_KEY หรือ SUPABASE_SERVICE_ROLE_KEY ใน .env
const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_SERVICE_KEY = process.env.SUPABASE_SERVICE_KEY || process.env.SUPABASE_SERVICE_ROLE_KEY;

if (!SUPABASE_URL || !SUPABASE_SERVICE_KEY) {
  console.error('❌ FATAL: SUPABASE_URL and SUPABASE_SERVICE_KEY (or SUPABASE_SERVICE_ROLE_KEY) are required for escrow release service. Exiting.');
  if (process.env.NODE_ENV === 'production') process.exit(1);
}

const supabase = (SUPABASE_URL && SUPABASE_SERVICE_KEY)
  ? createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY)
  : null;

// =====================================================
// MAIN: Release Escrow หลัง Consensus ผ่าน
// =====================================================

/**
 * เรียกเมื่อ Responder ทุกราย vote แล้ว — ตรวจ consensus แล้ว release ถ้าผ่าน
 * @param {string} requestId  - donation_requests.id
 * @param {string} responderId - user_id ของ Responder ที่ vote ล่าสุด
 * @param {boolean} canContinue - true = อนุญาต, false = Veto
 * @param {string} [note] - เหตุผล (optional)
 * @returns {{ result: 'released' | 'paused' | 'pending' | 'error', message: string }}
 */
async function handleConsensusVote(requestId, responderId, canContinue, note = null) {
    try {
        console.log(`[EscrowRelease] Vote received: request=${requestId} responder=${responderId} canContinue=${canContinue}`);

        // 1. บันทึก consensus vote
        const { error: voteError } = await supabase
            .from('donation_closure_consensus')
            .upsert({
                request_id: requestId,
                responder_id: responderId,
                can_continue: canContinue,
                voted_at: new Date().toISOString(),
                note,
            }, { onConflict: 'request_id,responder_id' });

        if (voteError) throw new Error(`Vote insert failed: ${voteError.message}`);

        // 2. เรียก DB Function ตรวจ consensus และอัปเดตสถานะ
        const { data: consensusResult, error: consensusError } = await supabase
            .rpc('process_donation_consensus', { p_request_id: requestId });

        if (consensusError) throw new Error(`Consensus check failed: ${consensusError.message}`);

        const result = consensusResult?.result;
        console.log(`[EscrowRelease] Consensus result: ${result} for request=${requestId}`);

        if (result === 'paused') {
            // Consensus ไม่ผ่าน — คำร้องถูกระงับ
            const pauseDeadline = consensusResult.pause_deadline;
            _emitDonationSystemMessage(requestId, {
                type: 'donation-paused',
                message: 'การบริจาคถูกระงับชั่วคราว รอการตัดสินใจจากเจ้าหน้าที่',
                pauseDeadline,
            });
            return { result: 'paused', message: 'คำร้องถูกระงับ รอ grace period', pauseDeadline };
        }

        if (result === 'active') {
            // ตรวจว่า Responder ทุกรายโหวตแล้วหรือยัง
            const allVoted = await _checkAllRespondersVoted(requestId);
            if (!allVoted) {
                return { result: 'pending', message: 'รอ Responder บางรายโหวตเพิ่มเติม' };
            }

            // Consensus ผ่านครบ! → Release Escrow
            return await releaseEscrow(requestId, { triggeredBy: 'consensus' });
        }

        return { result: 'pending', message: 'รอ Consensus จากทุก Responder' };

    } catch (err) {
        console.error('[EscrowRelease] handleConsensusVote error:', err);
        return { result: 'error', message: err.message };
    }
}

/**
 * Release Escrow ให้ Reporter หลังภารกิจสมบูรณ์
 * @param {string} requestId
 * @param {{ triggeredBy: 'consensus' | 'manual_admin' }} options
 */
async function releaseEscrow(requestId, options = { triggeredBy: 'consensus' }) {
    console.log(`[EscrowRelease] Starting escrow release for request=${requestId} (by ${options.triggeredBy})`);

    // 1. ดึงข้อมูลคำร้องและ fee_snapshot
    const { data: request, error: reqError } = await supabase
        .from('donation_requests')
        .select('id, user_id, escrow_status, current_amount, fee_snapshot, category_id')
        .eq('id', requestId)
        .single();

    if (reqError) throw new Error(`Request not found: ${reqError.message}`);

    if (request.escrow_status === 'released') {
        console.warn(`[EscrowRelease] Request ${requestId} already released — skipping`);
        return { result: 'already_released', message: 'Escrow ถูก release ไปแล้ว' };
    }

    if (request.escrow_status !== 'in_escrow') {
        return { result: 'skipped', message: `escrow_status = ${request.escrow_status} — ไม่สามารถ release ได้` };
    }

    // 2. ดึง in_escrow transactions ทั้งหมด (ป้องกัน race condition — lock ก่อน)
    const { data: transactions, error: txError } = await supabase
        .from('donation_transactions')
        .select('id, amount')
        .eq('request_id', requestId)
        .eq('status', 'in_escrow');

    if (txError) throw new Error(`Transaction fetch failed: ${txError.message}`);
    if (!transactions || transactions.length === 0) {
        return { result: 'no_funds', message: 'ไม่มี transaction ที่อยู่ใน escrow' };
    }

    // 3. Lock transactions ด้วย SQL Function (ป้องกัน Race Condition ด้วย FOR UPDATE NOWAIT)
    const lockedTxIds = [];
    for (const tx of transactions) {
        // ใช้ Database RPC ที่รับประกัน Pessimistic Locking
        const { data: lockOk, error: lockErr } = await supabase.rpc('process_escrow_transfer', { p_transaction_id: tx.id });
        if (!lockErr && lockOk) {
            lockedTxIds.push(tx.id);
        } else if (lockErr) {
            console.warn(`[EscrowRelease] Lock fail for ${tx.id}:`, lockErr.message);
        }
    }

    if (lockedTxIds.length === 0) {
        return { result: 'no_funds', message: 'ไม่สามารถ Lock transaction ใดๆ ได้ อาจโดน process ไปแล้ว' };
    }

    // 4. คำนวณยอดรวม (gross) และค่าธรรมเนียม จากเฉพาะรายการที่ Lock สำเร็จ 100%
    const lockedTransactions = transactions.filter(t => lockedTxIds.includes(t.id));
    const grossAmount = lockedTransactions.reduce((sum, t) => sum + parseFloat(t.amount), 0);
    const feeBreakdown = _calculateFees(grossAmount, request.fee_snapshot || []);

    console.log(`[EscrowRelease] Gross=฿${grossAmount.toFixed(2)} Fees=฿${feeBreakdown.totalFees.toFixed(2)} Net=฿${feeBreakdown.netAmount.toFixed(2)}`);

    // 5. บันทึก DisbursementLog
    const { data: logData, error: logError } = await supabase
        .from('donation_disbursement_logs')
        .insert({
            request_id: requestId,
            disbursed_at: new Date().toISOString(),
            gross_amount: grossAmount,
            net_amount: feeBreakdown.netAmount,
            total_fees: feeBreakdown.totalFees,
            fee_breakdown: feeBreakdown.items,
            disbursed_by: options.triggeredBy === 'manual_admin' ? 'manual_admin' : 'system',
        })
        .select('id')
        .single();

    if (logError) throw new Error(`DisbursementLog insert failed: ${logError.message}`);
    console.log(`[EscrowRelease] DisbursementLog created: ${logData.id}`);

    // 6. อัปเดต transactions → disbursed
    await supabase
        .from('donation_transactions')
        .update({
            status: 'disbursed',
            updated_at: new Date().toISOString(),
        })
        .in('id', lockedTxIds);

    // 7. อัปเดต donation_requests → escrow_status: released + closed_at
    await supabase
        .from('donation_requests')
        .update({
            escrow_status: 'released',
            escrow_released_at: new Date().toISOString(),
            closed_at: new Date().toISOString(),
            closed_reason: 'incident_resolved',
            updated_at: new Date().toISOString(),
        })
        .eq('id', requestId);

    // 8. Emit WebSocket events ให้ทุก client ที่ subscribe
    _emitDonationSystemMessage(requestId, {
        type: 'donation-released',
        message: `เงินบริจาคสุทธิ ฿${feeBreakdown.netAmount.toFixed(2)} ถูกโอนให้ผู้รับบริจาคแล้ว`,
        grossAmount,
        netAmount: feeBreakdown.netAmount,
        totalFees: feeBreakdown.totalFees,
        feeBreakdown: feeBreakdown.items,
    });

    console.log(`[EscrowRelease] ✅ Escrow released for request=${requestId}`);
    return {
        result: 'released',
        message: 'Release สำเร็จ',
        grossAmount,
        netAmount: feeBreakdown.netAmount,
        disbursementLogId: logData.id,
    };
}

// =====================================================
// FEE CALCULATION (Node.js mirror ของ FeeCalculatorService)
// =====================================================

/**
 * คำนวณ FeeBreakdown จาก gross amount และ fee_snapshot
 * @param {number} grossAmount
 * @param {Array} feeSnapshot  - จาก donation_requests.fee_snapshot (JSON)
 * @returns {{ totalFees: number, netAmount: number, items: Array }}
 */
function _calculateFees(grossAmount, feeSnapshot) {
    let totalFees = 0;
    const items = [];

    for (const fee of feeSnapshot) {
        if (!fee.name) continue;
        let deducted = 0;

        switch (fee.fee_type) {
            case 'percent_of_gross':
                deducted = grossAmount * (fee.rate || 0) / 100;
                break;
            case 'fixed_baht':
                deducted = fee.fixed_amount || 0;
                break;
            case 'percent_per_transaction':
                // ณ ตอน disburse: คำนวณจาก gross รวม (approximation)
                deducted = grossAmount * (fee.rate || 0) / 100;
                break;
            default:
                continue;
        }

        totalFees += deducted;
        items.push({
            name: fee.name,
            fee_type: fee.fee_type,
            rate: fee.rate || null,
            fixed_amount: fee.fixed_amount || null,
            deducted: Math.round(deducted * 100) / 100,
        });
    }

    const netAmount = Math.max(0, grossAmount - totalFees);
    return {
        totalFees: Math.round(totalFees * 100) / 100,
        netAmount: Math.round(netAmount * 100) / 100,
        items,
    };
}

// =====================================================
// HELPERS
// =====================================================

/**
 * ตรวจว่า Responder ทุกรายใน incident_responses ของ video นี้โหวตแล้วหรือยัง
 */
async function _checkAllRespondersVoted(requestId) {
    // ดึง video_id จาก donation_requests
    const { data: req } = await supabase
        .from('donation_requests')
        .select('video_id')
        .eq('id', requestId)
        .single();

    if (!req?.video_id) return true; // ถ้าไม่มี video_id ถือว่าผ่าน

    // ดึง responders ที่ active ของ video นี้
    const { data: responders } = await supabase
        .from('incident_responses')
        .select('volunteer_id')
        .eq('video_id', req.video_id)
        .eq('status', 'active');

    if (!responders || responders.length === 0) return true;

    // ดึง votes ที่มีอยู่แล้ว
    const { data: votes } = await supabase
        .from('donation_closure_consensus')
        .select('responder_id')
        .eq('request_id', requestId);

    const votedIds = new Set((votes || []).map(v => v.responder_id));
    return responders.every(r => votedIds.has(r.volunteer_id));
}

/**
 * Emit 'donation-system-message' ผ่าน WebSocket ให้ทุก client ที่ subscribe
 */
function _emitDonationSystemMessage(requestId, payload) {
    try {
        const io = socketService.getIO();
        if (io) {
            io.emit('donation-system-message', {
                requestId,
                timestamp: new Date().toISOString(),
                ...payload,
            });
            console.log(`[EscrowRelease] Emitted donation-system-message for request=${requestId}`);
        }
    } catch (e) {
        console.warn('[EscrowRelease] Failed to emit WebSocket event:', e.message);
    }
}

module.exports = {
    handleConsensusVote,
    releaseEscrow,
};
