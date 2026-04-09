/// ======================================================
/// Fee & Disbursement Models
/// ======================================================
/// ไฟล์นี้เก็บ Models สำหรับระบบค่าธรรมเนียมแพลตฟอร์ม
/// ใช้คู่กับ FeeRepository และ FeeCalculatorService

// ======================================================
// CategoryFeeItem
// ======================================================

/// ประเภทของค่าธรรมเนียม
enum FeeType {
  /// คิดเป็น % จาก gross amount รวมทั้งหมด ณ เวลา disburse
  percentOfGross,

  /// คงที่ (฿) ต่อการ disburse 1 ครั้ง
  fixedBaht,

  /// คิดเป็น % จากยอดของ transaction แต่ละรายการที่ confirm
  percentPerTransaction;

  String get dbValue {
    switch (this) {
      case FeeType.percentOfGross:
        return 'percent_of_gross';
      case FeeType.fixedBaht:
        return 'fixed_baht';
      case FeeType.percentPerTransaction:
        return 'percent_per_transaction';
    }
  }

  static FeeType fromString(String? value) {
    switch (value) {
      case 'fixed_baht':
        return FeeType.fixedBaht;
      case 'percent_per_transaction':
        return FeeType.percentPerTransaction;
      case 'percent_of_gross':
      default:
        return FeeType.percentOfGross;
    }
  }

  String get displayLabel {
    switch (this) {
      case FeeType.percentOfGross:
        return '% ของยอดรวม';
      case FeeType.fixedBaht:
        return 'คงที่ (฿)';
      case FeeType.percentPerTransaction:
        return '% ต่อธุรกรรม';
    }
  }
}

/// รายการค่าธรรมเนียม 1 รายการของ Category
/// Admin กำหนดใน Category Admin UI (ไม่จำกัดจำนวน)
class CategoryFeeItem {
  final String id;
  final String categoryId;
  final String name;        // ชื่อแสดง เช่น "Sheserved Service Fee"
  final FeeType feeType;
  final double? rate;       // % (เช่น 2.5 = 2.5%) — ใช้เมื่อ feeType != fixedBaht
  final double? amount;     // ฿ คงที่ — ใช้เมื่อ feeType == fixedBaht
  final int displayOrder;
  final bool isActive;
  final String? note;
  final DateTime createdAt;
  final DateTime updatedAt;

  const CategoryFeeItem({
    required this.id,
    required this.categoryId,
    required this.name,
    required this.feeType,
    this.rate,
    this.amount,
    this.displayOrder = 0,
    this.isActive = true,
    this.note,
    required this.createdAt,
    required this.updatedAt,
  });

  factory CategoryFeeItem.fromJson(Map<String, dynamic> json) {
    double? parseDoubleNullable(dynamic v) {
      if (v == null) return null;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString());
    }

    return CategoryFeeItem(
      id: json['id'] as String,
      categoryId: json['category_id'] as String,
      name: json['name'] as String,
      feeType: FeeType.fromString(json['fee_type']?.toString()),
      rate: parseDoubleNullable(json['rate']),
      amount: parseDoubleNullable(json['amount']),
      displayOrder: (json['display_order'] as num?)?.toInt() ?? 0,
      isActive: json['is_active'] as bool? ?? true,
      note: json['note']?.toString(),
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'category_id': categoryId,
      'name': name,
      'fee_type': feeType.dbValue,
      'rate': rate,
      'amount': amount,
      'display_order': displayOrder,
      'is_active': isActive,
      'note': note,
    };
  }

  /// คำนวณยอดที่หักจริงจาก fee item นี้
  /// [grossAmount] = ยอดรวมทั้งหมดใน escrow ณ เวลาที่คำนวณ
  /// [transactionAmount] = ยอดของ transaction นั้นๆ (ใช้สำหรับ percentPerTransaction)
  double calculateDeduction({
    required double grossAmount,
    double transactionAmount = 0,
  }) {
    if (!isActive) return 0;
    switch (feeType) {
      case FeeType.percentOfGross:
        return grossAmount * (rate ?? 0) / 100;
      case FeeType.fixedBaht:
        return amount ?? 0;
      case FeeType.percentPerTransaction:
        return transactionAmount * (rate ?? 0) / 100;
    }
  }

  /// แสดงค่า rate/amount แบบ human-readable
  String get displayValue {
    switch (feeType) {
      case FeeType.percentOfGross:
      case FeeType.percentPerTransaction:
        return '${rate?.toStringAsFixed(2) ?? '0.00'}%';
      case FeeType.fixedBaht:
        return '฿${amount?.toStringAsFixed(2) ?? '0.00'}';
    }
  }

  CategoryFeeItem copyWith({
    String? name,
    FeeType? feeType,
    double? rate,
    double? amount,
    int? displayOrder,
    bool? isActive,
    String? note,
  }) {
    return CategoryFeeItem(
      id: id,
      categoryId: categoryId,
      name: name ?? this.name,
      feeType: feeType ?? this.feeType,
      rate: rate ?? this.rate,
      amount: amount ?? this.amount,
      displayOrder: displayOrder ?? this.displayOrder,
      isActive: isActive ?? this.isActive,
      note: note ?? this.note,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }
}

// ======================================================
// FeeBreakdown — ผลลัพธ์การคำนวณค่าธรรมเนียม
// ======================================================

/// รายการค่าธรรมเนียม 1 รายการที่ถูกหักจริง
/// เก็บใน fee_breakdown JSONB ของ donation_disbursement_logs
class FeeLineItem {
  final String name;
  final FeeType feeType;
  final double? rate;
  final double? fixedAmount;
  final double deducted; // ยอดที่หักจริง (฿)

  const FeeLineItem({
    required this.name,
    required this.feeType,
    this.rate,
    this.fixedAmount,
    required this.deducted,
  });

  factory FeeLineItem.fromJson(Map<String, dynamic> json) {
    double parseDouble(dynamic v) {
      if (v == null) return 0.0;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString()) ?? 0.0;
    }
    double? parseDoubleNullable(dynamic v) {
      if (v == null) return null;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString());
    }

    return FeeLineItem(
      name: json['name'] as String,
      feeType: FeeType.fromString(json['fee_type']?.toString()),
      rate: parseDoubleNullable(json['rate']),
      fixedAmount: parseDoubleNullable(json['fixed_amount']),
      deducted: parseDouble(json['deducted']),
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'fee_type': feeType.dbValue,
        'rate': rate,
        'fixed_amount': fixedAmount,
        'deducted': deducted,
      };
}

/// ผลลัพธ์การคำนวณค่าธรรมเนียมทั้งหมด
/// ใช้ใน Pre-payment Disclosure (แสดงก่อนผู้บริจาคยืนยัน)
/// และเก็บ snapshot ลง donation_disbursement_logs
class FeeBreakdown {
  final double grossAmount;       // ยอดรวมใน escrow
  final double totalFees;         // ค่าธรรมเนียมรวม
  final double netAmount;         // ยอดสุทธิที่ Reporter ได้รับ
  final List<FeeLineItem> items;  // รายละเอียดแต่ละรายการ

  const FeeBreakdown({
    required this.grossAmount,
    required this.totalFees,
    required this.netAmount,
    required this.items,
  });

  factory FeeBreakdown.fromJson(Map<String, dynamic> json) {
    double parseDouble(dynamic v) {
      if (v == null) return 0.0;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString()) ?? 0.0;
    }

    final rawItems = json['items'] as List? ?? [];
    return FeeBreakdown(
      grossAmount: parseDouble(json['gross_amount']),
      totalFees: parseDouble(json['total_fees']),
      netAmount: parseDouble(json['net_amount']),
      items: rawItems.map((e) => FeeLineItem.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'gross_amount': grossAmount,
        'total_fees': totalFees,
        'net_amount': netAmount,
        'items': items.map((e) => e.toJson()).toList(),
      };

  /// % ที่ Reporter ได้รับสุทธิจากยอดรวม (สำหรับแสดงใน Progress Bar)
  double get netRatio => grossAmount > 0 ? netAmount / grossAmount : 1.0;

  /// แปลง feeSnapshot JSONB (List<Map>) เป็น List<FeeLineItem> สำหรับ snapshot ที่เก็บตอนสร้างคำร้อง
  static List<FeeLineItem> parseFeeSnapshot(List<dynamic>? snapshot) {
    if (snapshot == null) return [];
    return snapshot
        .map((e) => FeeLineItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}

// ======================================================
// DisbursementLog — บันทึกการจ่ายเงินให้ Reporter
// ======================================================

/// บันทึกการ Release Escrow ให้ Reporter (Mission Complete)
/// เก็บใน donation_disbursement_logs
class DisbursementLog {
  final String id;
  final String requestId;
  final DateTime disbursedAt;
  final double grossAmount;
  final double netAmount;
  final double totalFees;
  final List<FeeLineItem> feeBreakdown;
  final String? recipientAccount;
  final String? transferRef;
  final String disbursedBy; // 'system' | 'manual_admin'

  const DisbursementLog({
    required this.id,
    required this.requestId,
    required this.disbursedAt,
    required this.grossAmount,
    required this.netAmount,
    required this.totalFees,
    required this.feeBreakdown,
    this.recipientAccount,
    this.transferRef,
    this.disbursedBy = 'system',
  });

  factory DisbursementLog.fromJson(Map<String, dynamic> json) {
    double parseDouble(dynamic v) {
      if (v == null) return 0.0;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString()) ?? 0.0;
    }

    final rawBreakdown = json['fee_breakdown'] as List? ?? [];

    return DisbursementLog(
      id: json['id'] as String,
      requestId: json['request_id'] as String,
      disbursedAt: DateTime.parse(json['disbursed_at'] as String),
      grossAmount: parseDouble(json['gross_amount']),
      netAmount: parseDouble(json['net_amount']),
      totalFees: parseDouble(json['total_fees']),
      feeBreakdown: rawBreakdown
          .map((e) => FeeLineItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      recipientAccount: json['recipient_account']?.toString(),
      transferRef: json['transfer_ref']?.toString(),
      disbursedBy: json['disbursed_by']?.toString() ?? 'system',
    );
  }

  Map<String, dynamic> toJson() => {
        'request_id': requestId,
        'disbursed_at': disbursedAt.toIso8601String(),
        'gross_amount': grossAmount,
        'net_amount': netAmount,
        'total_fees': totalFees,
        'fee_breakdown': feeBreakdown.map((e) => e.toJson()).toList(),
        'recipient_account': recipientAccount,
        'transfer_ref': transferRef,
        'disbursed_by': disbursedBy,
      };
}
