import 'package:flutter/foundation.dart';

import '../data/repositories/fee_repository.dart';
import '../models/fee_models.dart';

/// FeeCalculatorService — คำนวณค่าธรรมเนียมแพลตฟอร์มแบบ Real-time
///
/// ## หน้าที่
/// - คำนวณ Gross Target จาก Net Goal (ใช้ใน Admin UI Live Preview)
/// - คำนวณ Net ที่ Reporter ได้รับจาก Gross (ใช้ใน Pre-payment Disclosure)
/// - Cache fee items เพื่อลด DB query ซ้ำๆ ในขณะผู้ใช้กรอกข้อมูล
///
/// ## การใช้งาน
/// ```dart
/// final calc = FeeCalculatorService(feeRepo);
/// await calc.loadForCategory(categoryId);
///
/// // ตอน Admin ตั้งค่า Net Goal
/// final grossTarget = calc.grossFromNet(50000);
///
/// // ตอน Donor ดู Pre-payment Disclosure
/// final breakdown = calc.breakdown(grossAmount: 55000);
/// ```
class FeeCalculatorService {
  final FeeRepository _feeRepo;

  /// fee items ที่ cache ไว้สำหรับ category ปัจจุบัน
  List<CategoryFeeItem> _cachedItems = [];
  String? _cachedCategoryId;

  FeeCalculatorService(this._feeRepo);

  // =====================================================
  // LOAD & CACHE
  // =====================================================

  /// โหลด fee items ของ category นี้ และ cache ไว้ใน instance
  /// เรียกครั้งแรกก่อนใช้งานเสมอ
  Future<void> loadForCategory(String categoryId) async {
    if (_cachedCategoryId == categoryId && _cachedItems.isNotEmpty) return;
    _cachedItems = await _feeRepo.getActiveFeeItems(categoryId);
    _cachedCategoryId = categoryId;
    debugPrint('[FeeCalculatorService] Loaded ${_cachedItems.length} fee items for category $categoryId');
  }

  /// ล้าง cache (ใช้เมื่อ Admin แก้ไข fee items แล้วต้องการ refresh)
  void clearCache() {
    _cachedItems = [];
    _cachedCategoryId = null;
  }

  // =====================================================
  // CALCULATION — Gross from Net
  // =====================================================

  /// คำนวณ Gross Target จาก Net Goal แบบ synchronous (ใช้ cache)
  /// สูตร: gross = (net + Σfixed) / (1 - Σpercent_of_gross%)
  ///
  /// ใช้ใน:
  ///   - Admin UI Live Preview ตอนพิมพ์ Net Goal
  ///   - สร้างคำร้อง: คำนวณ goal_amount_gross ก่อน insert
  double grossFromNet(double netGoal) {
    double totalPercentRate = 0;
    double totalFixed = 0;

    for (final item in _cachedItems) {
      if (!item.isActive) continue;
      switch (item.feeType) {
        case FeeType.percentOfGross:
          totalPercentRate += (item.rate ?? 0);
          break;
        case FeeType.fixedBaht:
          totalFixed += (item.amount ?? 0);
          break;
        case FeeType.percentPerTransaction:
          break; // ไม่รวมใน gross calculation ล่วงหน้า
      }
    }

    final divisor = 1 - (totalPercentRate / 100);
    if (divisor <= 0) {
      debugPrint('[FeeCalculatorService] ⚠️ Total fee rate >= 100%');
      return double.infinity;
    }

    return (netGoal + totalFixed) / divisor;
  }

  // =====================================================
  // CALCULATION — Breakdown from Gross
  // =====================================================

  /// คำนวณ FeeBreakdown จาก Gross Amount แบบ synchronous
  /// ใช้ cache — ต้อง loadForCategory() ก่อน
  ///
  /// ใช้ใน:
  ///   - Pre-payment Disclosure Dialog ก่อนผู้บริจาคยืนยัน
  ///   - Progress Bar ฝั่ง Viewer (netRatio)
  FeeBreakdown breakdown({required double grossAmount}) {
    double totalFees = 0;
    final lineItems = <FeeLineItem>[];

    for (final item in _cachedItems) {
      if (!item.isActive) continue;
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

  // =====================================================
  // FEE SNAPSHOT
  // =====================================================

  /// สร้าง FeeLineItem snapshot จาก cache สำหรับเก็บลงคำร้อง
  /// เรียกตอน User กด "สร้างคำร้อง" — ล็อค fee ณ วันที่สร้าง
  List<FeeLineItem> createSnapshot() {
    return _cachedItems
        .where((item) => item.isActive)
        .map((item) => FeeLineItem(
              name: item.name,
              feeType: item.feeType,
              rate: item.rate,
              fixedAmount: item.amount,
              deducted: 0, // จะคำนวณตอน disburse จริงเท่านั้น
            ))
        .toList();
  }

  // =====================================================
  // HELPERS
  // =====================================================

  /// คืน fee items ที่ cache อยู่ (read-only)
  List<CategoryFeeItem> get cachedItems => List.unmodifiable(_cachedItems);

  /// ตรวจสอบว่า category นี้ยังไม่มี fee ใดเลย
  bool get hasNoFees => _cachedItems.where((e) => e.isActive).isEmpty;

  /// คำนวณ % สุทธิที่ Reporter จะได้ (จาก percentOfGross เท่านั้น)
  double get netRatioFromGross {
    final totalPercent = _cachedItems
        .where((e) => e.isActive && e.feeType == FeeType.percentOfGross)
        .fold<double>(0, (sum, e) => sum + (e.rate ?? 0));
    return (100 - totalPercent) / 100;
  }
}
