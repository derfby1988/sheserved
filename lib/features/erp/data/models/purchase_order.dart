import 'package:flutter/material.dart';

/// Model สำหรับ purchase_orders (PO)
class PurchaseOrder {
  final String id;
  final String professionId;
  final String? branchId;
  final String supplierId;
  final String? prId;
  final String poNumber;
  final String status; // draft, sent, partially_received, fully_received, cancelled
  final double totalAmount;
  final double taxAmount;
  final double grandTotal;
  final String? notes;
  final DateTime? expectedDeliveryDate;
  final DateTime createdAt;
  final DateTime updatedAt;

  // Joined fields
  final String? supplierName;
  final String? branchName;
  final String? prNumber;

  const PurchaseOrder({
    required this.id,
    required this.professionId,
    this.branchId,
    required this.supplierId,
    this.prId,
    required this.poNumber,
    required this.status,
    required this.totalAmount,
    required this.taxAmount,
    required this.grandTotal,
    this.notes,
    this.expectedDeliveryDate,
    required this.createdAt,
    required this.updatedAt,
    this.supplierName,
    this.branchName,
    this.prNumber,
  });

  factory PurchaseOrder.fromJson(Map<String, dynamic> json) {
    String? supName;
    if (json['supplier'] != null) {
      supName = json['supplier']['supplier_name'] as String?;
    }
    String? bName;
    if (json['branch'] != null) {
      bName = json['branch']['name'] as String?;
    }
    String? prNum;
    if (json['purchase_requisitions'] != null) {
      prNum = json['purchase_requisitions']['pr_number'] as String?;
    }

    return PurchaseOrder(
      id: json['id'] as String,
      professionId: json['profession_id'] as String,
      branchId: json['branch_id'] as String?,
      supplierId: json['supplier_id'] as String,
      prId: json['pr_id'] as String?,
      poNumber: json['po_number'] as String,
      status: json['status'] as String? ?? 'draft',
      totalAmount: (json['total_amount'] as num?)?.toDouble() ?? 0.0,
      taxAmount: (json['tax_amount'] as num?)?.toDouble() ?? 0.0,
      grandTotal: (json['grand_total'] as num?)?.toDouble() ?? 0.0,
      notes: json['notes'] as String?,
      expectedDeliveryDate: json['expected_delivery_date'] != null
          ? DateTime.parse(json['expected_delivery_date'] as String)
          : null,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      supplierName: supName ?? json['supplier_name'] as String?,
      branchName: bName ?? json['branch_name'] as String?,
      prNumber: prNum ?? json['pr_number'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'profession_id': professionId,
      'branch_id': branchId,
      'supplier_id': supplierId,
      'pr_id': prId,
      'po_number': poNumber,
      'status': status,
      'total_amount': totalAmount,
      'tax_amount': taxAmount,
      'grand_total': grandTotal,
      'notes': notes,
      'expected_delivery_date': expectedDeliveryDate?.toIso8601String().split('T')[0],
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  String get statusLabel {
    switch (status) {
      case 'draft':
        return 'แบบร่าง';
      case 'sent':
        return 'ส่งคู่ค้าแล้ว';
      case 'partially_received':
        return 'รับบางส่วน';
      case 'fully_received':
        return 'รับครบถ้วน';
      case 'cancelled':
        return 'ยกเลิก';
      default:
        return status;
    }
  }

  Color get statusColor {
    switch (status) {
      case 'draft':
        return Colors.grey;
      case 'sent':
        return Colors.blue;
      case 'partially_received':
        return Colors.orange;
      case 'fully_received':
        return Colors.green;
      case 'cancelled':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  bool get isDraft => status == 'draft';
  bool get isSent => status == 'sent';
  bool get isPartiallyReceived => status == 'partially_received';
  bool get isFullyReceived => status == 'fully_received';
  bool get isCancelled => status == 'cancelled';
}
