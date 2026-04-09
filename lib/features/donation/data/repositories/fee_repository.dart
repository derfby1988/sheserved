import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/fee_models.dart';

/// Repository สำหรับ CRUD ค่าธรรมเนียมแพลตฟอร์ม (category_fee_items)
/// และสร้าง Fee Snapshot ตอนสร้างคำร้องบริจาค
///
/// ## Auth Guidelines (ตาม /auth_data_guidelines.md)
/// ❌ ห้ามใช้ `Supabase.instance.client.auth.currentUser`
/// ✅ UI ที่เรียก write methods ต้องตรวจสิทธิ์ Super Admin ก่อน
///    โดยดึง userId จาก ServiceLocator.instance.currentUser?.id
///
/// ## หน้าที่หลัก
/// 1. CRUD รายการค่าธรรมเนียมต่อ category (Admin ใช้)
/// 2. สร้าง fee snapshot ตอนผู้ใช้สร้างคำร้อง (ป้องกัน Admin เปลี่ยน fee ย้อนหลัง)
/// 3. คำนวณ Gross Target จาก Net Goal แบบ real-time (สำหรับ FeeCalculatorService)
/// 4. บันทึก DisbursementLog เมื่อ escrow ถูก release
class FeeRepository {
  final SupabaseClient _client;

  FeeRepository(this._client);

  // =====================================================
  // READ
  // =====================================================

  /// ดึง fee items ทั้งหมดของ category นี้ (เรียงตาม display_order)
  Future<List<CategoryFeeItem>> getFeeItems(String categoryId) async {
    final response = await _client
        .from('category_fee_items')
        .select()
        .eq('category_id', categoryId)
        .order('display_order', ascending: true);
    return (response as List)
        .map((json) => CategoryFeeItem.fromJson(json))
        .toList();
  }

  /// ดึงเฉพาะ fee items ที่ is_active = true
  Future<List<CategoryFeeItem>> getActiveFeeItems(String categoryId) async {
    final response = await _client
        .from('category_fee_items')
        .select()
        .eq('category_id', categoryId)
        .eq('is_active', true)
        .order('display_order', ascending: true);
    return (response as List)
        .map((json) => CategoryFeeItem.fromJson(json))
        .toList();
  }

  /// ดึง DisbursementLog ทั้งหมดของ request นี้
  Future<List<DisbursementLog>> getDisbursementLogs(String requestId) async {
    final response = await _client
        .from('donation_disbursement_logs')
        .select()
        .eq('request_id', requestId)
        .order('disbursed_at', ascending: false);
    return (response as List)
        .map((json) => DisbursementLog.fromJson(json))
        .toList();
  }

  /// ดึง DisbursementLogs ทั้งหมด (สำหรับหน้า Reporting / CSV Export)
  /// [limit] จำกัดจำนวนรายการ, [offset] สำหรับ pagination
  Future<List<DisbursementLog>> getAllDisbursementLogs({
    int limit = 50,
    int offset = 0,
  }) async {
    final response = await _client
        .from('donation_disbursement_logs')
        .select()
        .order('disbursed_at', ascending: false)
        .range(offset, offset + limit - 1);
    return (response as List)
        .map((json) => DisbursementLog.fromJson(json))
        .toList();
  }

  // =====================================================
  // FEE CALCULATION
  // =====================================================

  /// คำนวณ FeeBreakdown จาก fee items ที่ active ของ category
  /// ใช้ใน:
  ///   1. Admin — Live Preview ตอนตั้งค่า Net Goal
  ///   2. Donor — Pre-payment Disclosure ก่อนยืนยันชำระ
  ///   3. Disbursement — ก่อน release escrow ให้ Reporter
  ///
  /// [grossAmount]       = ยอด escrow รวม (หรือ Gross Target คาดการณ์)
  /// [categoryId]        = id ของ category (ดึง active fee items เอง)
  /// [feeItems]          = ถ้ามี items อยู่แล้ว ไม่ต้องดึงจาก DB อีก (ใน-memory)
  Future<FeeBreakdown> calculateFees({
    required double grossAmount,
    String? categoryId,
    List<CategoryFeeItem>? feeItems,
  }) async {
    // โหลด fee items ถ้าไม่ได้ส่งมา
    final items = feeItems ?? (categoryId != null
        ? await getActiveFeeItems(categoryId)
        : <CategoryFeeItem>[]);

    double totalFees = 0;
    final lineItems = <FeeLineItem>[];

    for (final item in items) {
      // percentPerTransaction คิดต่อ transaction ไม่ใช่ต่อ gross
      // ในกรณีคำนวณล่วงหน้า ให้ข้ามไป (จะคำนวณได้แม่นยำตอน disburse จริง)
      if (item.feeType == FeeType.percentPerTransaction) continue;

      final deducted = item.calculateDeduction(grossAmount: grossAmount);
      totalFees += deducted;

      lineItems.add(FeeLineItem(
        name: item.name,
        feeType: item.feeType,
        rate: item.rate,
        fixedAmount: item.amount,
        deducted: deducted,
      ));
    }

    final netAmount = (grossAmount - totalFees).clamp(0.0, double.infinity);

    return FeeBreakdown(
      grossAmount: grossAmount,
      totalFees: totalFees,
      netAmount: netAmount,
      items: lineItems,
    );
  }

  /// คำนวณ Gross Target จาก Net Goal (กลับทิศทาง)
  /// สูตร: gross = net / (1 - Σ percent_of_gross%) + Σ fixed_baht
  /// ใช้ใน Admin UI — Live Preview "ถ้าต้องการรับ ฿X ต้องระดมทุน ฿Y"
  Future<double> calculateGrossFromNet({
    required double netGoal,
    String? categoryId,
    List<CategoryFeeItem>? feeItems,
  }) async {
    final items = feeItems ?? (categoryId != null
        ? await getActiveFeeItems(categoryId)
        : <CategoryFeeItem>[]);

    double totalPercentRate = 0;
    double totalFixed = 0;

    for (final item in items) {
      if (!item.isActive) continue;
      if (item.feeType == FeeType.percentOfGross) {
        totalPercentRate += (item.rate ?? 0);
      } else if (item.feeType == FeeType.fixedBaht) {
        totalFixed += (item.amount ?? 0);
      }
      // percentPerTransaction ไม่รวมใน gross calculation (ขึ้นกับจำนวน txn)
    }

    final divisor = 1 - (totalPercentRate / 100);
    if (divisor <= 0) {
      debugPrint('[FeeRepository] ⚠️ Total fee rate >= 100% — Gross Target infinite');
      return double.infinity;
    }

    final gross = (netGoal + totalFixed) / divisor;
    return gross;
  }

  /// สร้าง fee snapshot สำหรับเก็บลง donation_requests.fee_snapshot
  /// เรียกตอนผู้ใช้กด "สร้างคำร้อง" — ล็อค fee ณ วันที่สร้าง ป้องกัน retroactive change
  Future<List<FeeLineItem>> createFeeSnapshot(String categoryId) async {
    final items = await getActiveFeeItems(categoryId);
    return items.map((item) {
      return FeeLineItem(
        name: item.name,
        feeType: item.feeType,
        rate: item.rate,
        fixedAmount: item.amount,
        deducted: 0, // deducted ยังไม่รู้ตอนสร้าง snapshot — คำนวณตอน disburse
      );
    }).toList();
  }

  // =====================================================
  // WRITE (Super Admin only)
  // =====================================================

  /// เพิ่ม fee item ใหม่ให้ category
  Future<String> addFeeItem(Map<String, dynamic> data) async {
    final response = await _client
        .from('category_fee_items')
        .insert(data)
        .select('id')
        .single();

    debugPrint('[FeeRepository] Added fee item: ${response['id']}');
    return response['id'] as String;
  }

  /// อัปเดต fee item
  Future<void> updateFeeItem(String feeItemId, Map<String, dynamic> data) async {
    data['updated_at'] = DateTime.now().toIso8601String();
    await _client
        .from('category_fee_items')
        .update(data)
        .eq('id', feeItemId);

    debugPrint('[FeeRepository] Updated fee item: $feeItemId');
  }

  /// ลบ fee item (ถ้ายังมีคำร้องที่ snapshot ใช้ item นี้ อาจต้อง deactivate แทน)
  Future<void> deleteFeeItem(String feeItemId) async {
    await _client
        .from('category_fee_items')
        .delete()
        .eq('id', feeItemId);

    debugPrint('[FeeRepository] Deleted fee item: $feeItemId');
  }

  /// Deactivate fee item (ปลอดภัยกว่าลบ — ไม่กระทบ snapshot เก่า)
  Future<void> deactivateFeeItem(String feeItemId) async {
    await _client
        .from('category_fee_items')
        .update({
          'is_active': false,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', feeItemId);

    debugPrint('[FeeRepository] Deactivated fee item: $feeItemId');
  }

  /// อัปเดต display_order ของ fee items ทั้งหมดใน category
  Future<void> updateFeeItemsOrder(List<Map<String, dynamic>> orderData) async {
    for (final item in orderData) {
      await _client
          .from('category_fee_items')
          .update({'display_order': item['display_order']})
          .eq('id', item['id']);
    }
    debugPrint('[FeeRepository] Updated ${orderData.length} fee item orders');
  }

  // =====================================================
  // DISBURSEMENT
  // =====================================================

  /// บันทึก DisbursementLog เมื่อ escrow ถูก release ให้ Reporter
  /// เรียกจาก Node.js EscrowReleaseService (ผ่าน service_role key)
  /// หรือจาก Admin manual release
  Future<String> recordDisbursement({
    required String requestId,
    required FeeBreakdown breakdown,
    String? recipientAccount,
    String? transferRef,
    String disbursedBy = 'system',
  }) async {
    final response = await _client
        .from('donation_disbursement_logs')
        .insert({
          'request_id': requestId,
          'disbursed_at': DateTime.now().toIso8601String(),
          'gross_amount': breakdown.grossAmount,
          'net_amount': breakdown.netAmount,
          'total_fees': breakdown.totalFees,
          'fee_breakdown': breakdown.items.map((e) => e.toJson()).toList(),
          'recipient_account': recipientAccount,
          'transfer_ref': transferRef,
          'disbursed_by': disbursedBy,
        })
        .select('id')
        .single();

    final logId = response['id'] as String;
    debugPrint('[FeeRepository] Recorded disbursement: $logId (net=฿${breakdown.netAmount.toStringAsFixed(2)})');
    return logId;
  }
}
