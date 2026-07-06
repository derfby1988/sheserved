import 'package:flutter/material.dart';

/// Model สำหรับ goods_receipts (GR)
class GoodsReceipt {
  final String id;
  final String professionId;
  final String? branchId;
  final String purchaseOrderId;
  final String grNumber;
  final DateTime receiptDate;
  final String? supplierDeliveryNote;
  final String receivedBy;
  final String status; // pending, completed, rejected
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  // Joined fields
  final String? poNumber;
  final String? branchName;
  final String? receivedByName;

  const GoodsReceipt({
    required this.id,
    required this.professionId,
    this.branchId,
    required this.purchaseOrderId,
    required this.grNumber,
    required this.receiptDate,
    this.supplierDeliveryNote,
    required this.receivedBy,
    required this.status,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
    this.poNumber,
    this.branchName,
    this.receivedByName,
  });

  factory GoodsReceipt.fromJson(Map<String, dynamic> json) {
    String? poNum;
    if (json['purchase_order'] != null) {
      poNum = json['purchase_order']['po_number'] as String?;
    }
    String? bName;
    if (json['branch'] != null) {
      bName = json['branch']['name'] as String?;
    }
    String? recvName;
    if (json['receiver'] != null) {
      recvName = json['receiver']['display_name'] as String?;
    }

    return GoodsReceipt(
      id: json['id'] as String,
      professionId: json['profession_id'] as String,
      branchId: json['branch_id'] as String?,
      purchaseOrderId: json['purchase_order_id'] as String,
      grNumber: json['gr_number'] as String,
      receiptDate: DateTime.parse(json['receipt_date'] as String),
      supplierDeliveryNote: json['supplier_delivery_note'] as String?,
      receivedBy: json['received_by'] as String,
      status: json['status'] as String? ?? 'completed',
      notes: json['notes'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      poNumber: poNum ?? json['po_number'] as String?,
      branchName: bName ?? json['branch_name'] as String?,
      receivedByName: recvName ?? json['received_by_name'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'profession_id': professionId,
      'branch_id': branchId,
      'purchase_order_id': purchaseOrderId,
      'gr_number': grNumber,
      'receipt_date': receiptDate.toIso8601String(),
      'supplier_delivery_note': supplierDeliveryNote,
      'received_by': receivedBy,
      'status': status,
      'notes': notes,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  String get statusLabel {
    switch (status) {
      case 'pending':
        return 'รอดำเนินการ';
      case 'completed':
        return 'รับเรียบร้อย';
      case 'rejected':
        return 'ปฏิเสธ';
      default:
        return status;
    }
  }

  Color get statusColor {
    switch (status) {
      case 'pending':
        return Colors.orange;
      case 'completed':
        return Colors.green;
      case 'rejected':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  bool get isCompleted => status == 'completed';
  bool get isPending => status == 'pending';
  bool get isRejected => status == 'rejected';
}
