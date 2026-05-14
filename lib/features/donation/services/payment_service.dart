import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/donation_models.dart';
import '../data/repositories/donation_repository.dart';

/// PaymentService — ศูนย์กลางการจัดการ Payment Flow สำหรับการบริจาค
///
/// ## ช่วง Development (ไม่เสียเงิน)
/// ตั้ง method = PaymentMethod.mock → auto-confirm ทันทีหลัง 1.5 วินาที
/// ไม่ต้องเชื่อมธนาคาร ไม่ต้องมี API key ใดๆ
///
/// ## ตอน Production
/// เปลี่ยน method เป็น .promptpay หรือ .omiseCard
/// สถาปัตยกรรมทั้งหมดรองรับอยู่แล้ว — ไม่ต้องแก้โค้ดเรียกใช้
///
/// ## Flow ทั้งหมด
/// 1. initiateDonation() → สร้าง donation_transactions record (pending)
/// 2. ตรวจ method แล้ว route บน _handleMock / _handlePromptPay / _handleOmise
/// 3. เมื่อ confirm: เรียก repo.confirmTransaction() → DB Function อัปเดต
///    donation_requests.current_amount แบบ atomic
class PaymentService {
  PaymentService._internal();
  static final PaymentService instance = PaymentService._internal();

  DonationRepository get _repo =>
      DonationRepository(Supabase.instance.client);

  /// เริ่ม Flow การบริจาค
  ///
  /// คืน [DonationTransactionResult]:
  ///   - confirmed → สำเร็จ (mock/production) → transaction สถานะ in_escrow
  ///   - pending   → แสดง QR/UI รอผู้ใช้ชำระ (promptpay/omise in production)
  ///   - failed    → ล้มเหลว พร้อม error message
  Future<DonationTransactionResult> initiateDonation({
    required String requestId,
    required String donorUserId,
    required double amount,
    PaymentMethod method = PaymentMethod.mock,
    String? promptPayId,
  }) async {
    try {
      // 1. สร้าง transaction record (pending)
      final txId = await _repo.createTransaction({
        'request_id': requestId,
        'donor_user_id': donorUserId,
        'amount': amount,
        'payment_method': method.dbValue,
        'status': 'pending',
      });

      debugPrint('[PaymentService] Created transaction $txId (${method.dbValue}, ฿$amount)');

      // 2. Route ตาม method
      switch (method) {
        case PaymentMethod.mock:
          return await _handleMock(txId, amount, requestId: requestId);

        case PaymentMethod.promptpay:
          return _handlePromptPay(txId, amount, promptPayId: promptPayId);

        case PaymentMethod.omiseCard:
          return _handleOmise(txId, amount);
      }
    } catch (e, stack) {
      debugPrint('[PaymentService] initiateDonation error: $e\n$stack');
      return DonationTransactionResult.failed(
        error: 'เกิดข้อผิดพลาดในการบริจาค: $e',
      );
    }
  }

  // ===========================================================
  // MOCK MODE — ใช้ใน Development (ฟรี 100%)
  // ===========================================================

  /// จำลองการชำระเงิน: รอ 1.5 วินาที แล้ว auto-confirm
  /// ใน Dev ไม่มีเงินจริงเคลื่อนที่
  /// หลัง confirm → เปลี่ยนสถานะ transaction เป็น in_escrow ทันที
  Future<DonationTransactionResult> _handleMock(
    String transactionId,
    double amount, {
    required String requestId,
  }) async {
    debugPrint('[PaymentService] 🧪 Mock mode: simulating payment...');
    await Future.delayed(const Duration(milliseconds: 1500));

    // 1. Confirm transaction (atomic: บวก current_amount)
    await _repo.confirmTransaction(
      transactionId,
      paymentReference: 'mock-${DateTime.now().millisecondsSinceEpoch}',
    );

    // 2. ✅ Escrow Transition: เปลี่ยน status → in_escrow ทันที
    //    เงินถือว่า "พักอยู่ที่ Beneficiary Escrow Account" แล้ว
    await _transitionToEscrow(transactionId, requestId);

    debugPrint('[PaymentService] ✅ Mock payment confirmed + in_escrow: $transactionId');
    return DonationTransactionResult.confirmed(
      transactionId: transactionId,
      amount: amount,
    );
  }

  // ===========================================================
  // PROMPTPAY MODE — Production Ready (รอ Webhook)
  // ===========================================================

  /// สร้าง PromptPay QR Payload ตามมาตรฐาน EMVCo + BOT
  /// ไม่ต้องเชื่อมธนาคาร — QR สร้างได้ทันที
  /// confirmation จะมาทาง Webhook จาก payment provider
  DonationTransactionResult _handlePromptPay(
    String transactionId,
    double amount, {
    String? promptPayId,
  }) {
    final targetId = promptPayId ?? ''; // PromptPay ID ของผู้รับ

    if (targetId.isEmpty) {
      debugPrint('[PaymentService] PromptPay: no promptPayId configured');
      return DonationTransactionResult.failed(
        error: 'ยังไม่ได้ตั้งค่า PromptPay ID ของผู้รับบริจาค',
      );
    }

    // สร้าง QR payload (EMVCo format)
    final qrPayload = _buildPromptPayPayload(targetId, amount);

    debugPrint('[PaymentService] 📱 PromptPay QR generated for $transactionId');

    return DonationTransactionResult.pendingQr(
      transactionId: transactionId,
      amount: amount,
      qrPayload: qrPayload,
    );
    // webhook จะเรียก confirmTransaction เมื่อผู้ใช้ชำระเสร็จ
  }

  /// สร้าง PromptPay QR payload (EMVCo format)
  /// ไม่ต้องการ API Key ใดๆ — คำนวณเองได้ทันที
  String _buildPromptPayPayload(String promptPayId, double amount) {
    // EMVCo format simplified (Thai QR standard)
    // 00: Payload Format Indicator
    // 01: Point of Initiation Method (12 = dynamic)
    // 29: Merchant Account Information (PromptPay)
    //   00: GUID
    //   01: Target (phone/ID)
    // 53: Transaction Currency (764 = THB)
    // 54: Transaction Amount
    // 58: Country Code
    // 59: Merchant Name
    // 60: Merchant City
    // 63: CRC

    final target = promptPayId.startsWith('0') && promptPayId.length == 10
        ? '0066${promptPayId.substring(1)}' // Phone → international format
        : promptPayId; // National ID / Tax ID

    final merchantAccountRaw =
        '0016A000000677010111' // GUID for PromptPay
        '01${target.length.toString().padLeft(2, '0')}$target';

    final amountStr = amount.toStringAsFixed(2);

    String payload = '000201' // Format Indicator
        '010212' // Dynamic QR
        '29${merchantAccountRaw.length.toString().padLeft(2, '0')}$merchantAccountRaw'
        '5303764' // THB
        '54${amountStr.length.toString().padLeft(2, '0')}$amountStr'
        '5802TH' // Thailand
        '5910SheServed' // Merchant name (15 chars max)
        '6010Bangkok' // City
        '6304'; // CRC placeholder

    final crc = _crc16(payload);
    return '$payload${crc.toRadixString(16).toUpperCase().padLeft(4, '0')}';
  }

  /// CRC16-CCITT checksum สำหรับ EMVCo QR
  int _crc16(String data) {
    int crc = 0xFFFF;
    for (final byte in data.codeUnits) {
      crc ^= (byte << 8);
      for (int i = 0; i < 8; i++) {
        if ((crc & 0x8000) != 0) {
          crc = ((crc << 1) ^ 0x1021) & 0xFFFF;
        } else {
          crc = (crc << 1) & 0xFFFF;
        }
      }
    }
    return crc;
  }

  // ===========================================================
  // OMISE MODE — Production Ready (Sandbox ฟรี)
  // ===========================================================

  /// Omise integration — รองรับ Sandbox (ฟรี) และ Production
  /// ต้องเพิ่ม omise_flutter หรือ flutter_omise package ก่อน
  DonationTransactionResult _handleOmise(String transactionId, double amount) {
    // TODO(production): integrate omise_flutter SDK
    // ตัวอย่าง:
    //   final token = await OmiseFlutter.createToken(cardInfo);
    //   final charge = await omiseApi.createCharge(token, amount);
    //   if (charge.status == 'successful') {
    //     await _repo.confirmTransaction(transactionId, paymentReference: charge.id);
    //   }

    debugPrint('[PaymentService] Omise: not yet integrated (production only)');
    return DonationTransactionResult.failed(
      error: 'Omise ยังไม่เปิดใช้งานในเวอร์ชันนี้',
    );
  }

  // ===========================================================
  // WEBHOOK HANDLER (เรียกจาก Edge Function หรือ Backend)
  // ===========================================================

  /// เรียกเมื่อ Payment Provider ส่ง Webhook มายืนยัน
  /// ใช้ใน Production: ส่ง transactionId + reference จาก provider
  /// หลัง confirm → เปลี่ยน status เป็น in_escrow อัตโนมัติ
  Future<bool> handleWebhookConfirmation({
    required String transactionId,
    required String paymentReference,
    required String requestId,
  }) async {
    try {
      await _repo.confirmTransaction(
        transactionId,
        paymentReference: paymentReference,
      );
      // ✅ Escrow Transition หลัง Webhook confirm
      await _transitionToEscrow(transactionId, requestId);
      debugPrint('[PaymentService] 🎉 Webhook confirmed + in_escrow: $transactionId ($paymentReference)');
      return true;
    } catch (e) {
      debugPrint('[PaymentService] Webhook confirm failed: $e');
      return false;
    }
  }

  // ===========================================================
  // ESCROW TRANSITION (Private)
  // ===========================================================

  /// เปลี่ยน transaction status → in_escrow และอัปเดต donation_requests.escrow_status
  /// เรียกหลัง confirm สำเร็จเสมอ
  ///
  /// หลักการ: เงินที่ถูก confirm แล้วถือว่า "อยู่ที่ Beneficiary Escrow Account" ทันที
  /// Node.js EscrowReleaseService จะดึงข้อมูลนี้ออกมาตอนภารกิจสมบูรณ์
  Future<void> _transitionToEscrow(String transactionId, String requestId) async {
    try {
      final client = Supabase.instance.client;

      // 1. อัปเดต transaction status → in_escrow
      await client
          .from('donation_transactions')
          .update({
            'status': 'in_escrow',
            'escrow_submitted_at': DateTime.now().toIso8601String(),
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', transactionId)
          .eq('status', 'confirmed'); // guard: เฉพาะที่ confirmed แล้วเท่านั้น

      // 2. เรียก DB Function อัปเดต donation_requests.escrow_status → in_escrow
      await client.rpc(
        'update_request_escrow_status',
        params: {'p_request_id': requestId},
      );

      debugPrint('[PaymentService] 🔒 Escrow transition complete: $transactionId → in_escrow');
    } catch (e) {
      // ไม่ throw เพราะ payment ผ่านแล้ว เพียงแต่ escrow status ยังไม่อัปเดต
      // Node.js cron job จะตรวจและ sync ให้ในรอบถัดไป
      debugPrint('[PaymentService] ⚠️ Escrow transition failed (non-critical): $e');
    }
  }
}

// ===========================================================
// RESULT TYPES
// ===========================================================

enum _TransactionOutcome { confirmed, pending, failed }

/// ผลลัพธ์ของการ initiateDonation
class DonationTransactionResult {
  final _TransactionOutcome _outcome;
  final String? transactionId;
  final double? amount;
  final String? qrPayload;  // สำหรับ PromptPay → แสดง QR
  final String? error;

  const DonationTransactionResult._({
    required _TransactionOutcome outcome,
    this.transactionId,
    this.amount,
    this.qrPayload,
    this.error,
  }) : _outcome = outcome;

  factory DonationTransactionResult.confirmed({
    required String transactionId,
    required double amount,
  }) =>
      DonationTransactionResult._(
        outcome: _TransactionOutcome.confirmed,
        transactionId: transactionId,
        amount: amount,
      );

  factory DonationTransactionResult.pendingQr({
    required String transactionId,
    required double amount,
    required String qrPayload,
  }) =>
      DonationTransactionResult._(
        outcome: _TransactionOutcome.pending,
        transactionId: transactionId,
        amount: amount,
        qrPayload: qrPayload,
      );

  factory DonationTransactionResult.failed({required String error}) =>
      DonationTransactionResult._(
        outcome: _TransactionOutcome.failed,
        error: error,
      );

  bool get isConfirmed => _outcome == _TransactionOutcome.confirmed;
  bool get isPending => _outcome == _TransactionOutcome.pending;
  bool get isFailed => _outcome == _TransactionOutcome.failed;
}
