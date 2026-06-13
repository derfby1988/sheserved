import 'package:flutter/material.dart';

/// Model สำหรับ purchase_requisitions (PR)
class PurchaseRequisition {
  final String id;
  final String professionId;
  final String? branchId;
  final String requesterId;
  final String prNumber;
  final String status; // draft, pending_approval, approved, rejected, converted
  final double totalAmount;
  final String? notes;
  final String? approvedBy;
  final DateTime? approvedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  // Joined fields
  final String? requesterName;
  final String? approvedByName;
  final String? branchName;

  const PurchaseRequisition({
    required this.id,
    required this.professionId,
    this.branchId,
    required this.requesterId,
    required this.prNumber,
    required this.status,
    required this.totalAmount,
    this.notes,
    this.approvedBy,
    this.approvedAt,
    required this.createdAt,
    required this.updatedAt,
    this.requesterName,
    this.approvedByName,
    this.branchName,
  });

  factory PurchaseRequisition.fromJson(Map<String, dynamic> json) {
    // Handling nested joins from Supabase
    String? reqName;
    if (json['requester'] != null) {
      reqName = json['requester']['display_name'] as String?;
    }
    String? appName;
    if (json['approver'] != null) {
      appName = json['approver']['display_name'] as String?;
    }
    String? bName;
    if (json['branch'] != null) {
      bName = json['branch']['name'] as String?;
    }

    return PurchaseRequisition(
      id: json['id'] as String,
      professionId: json['profession_id'] as String,
      branchId: json['branch_id'] as String?,
      requesterId: json['requester_id'] as String,
      prNumber: json['pr_number'] as String,
      status: json['status'] as String? ?? 'draft',
      totalAmount: (json['total_amount'] as num?)?.toDouble() ?? 0.0,
      notes: json['notes'] as String?,
      approvedBy: json['approved_by'] as String?,
      approvedAt: json['approved_at'] != null
          ? DateTime.parse(json['approved_at'] as String)
          : null,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      requesterName: reqName ?? json['requester_name'] as String?,
      approvedByName: appName ?? json['approved_by_name'] as String?,
      branchName: bName ?? json['branch_name'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'profession_id': professionId,
      'branch_id': branchId,
      'requester_id': requesterId,
      'pr_number': prNumber,
      'status': status,
      'total_amount': totalAmount,
      'notes': notes,
      'approved_by': approvedBy,
      'approved_at': approvedAt?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  String get statusLabel {
    switch (status) {
      case 'draft':
        return 'แบบร่าง';
      case 'pending_approval':
        return 'รออนุมัติ';
      case 'approved':
        return 'อนุมัติแล้ว';
      case 'rejected':
        return 'ปฏิเสธ';
      case 'converted':
        return 'แปลงเป็น PO';
      default:
        return status;
    }
  }

  Color get statusColor {
    switch (status) {
      case 'draft':
        return Colors.grey;
      case 'pending_approval':
        return Colors.orange;
      case 'approved':
        return Colors.green;
      case 'rejected':
        return Colors.red;
      case 'converted':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  bool get isDraft => status == 'draft';
  bool get isPendingApproval => status == 'pending_approval';
  bool get isApproved => status == 'approved';
  bool get isRejected => status == 'rejected';
  bool get isConverted => status == 'converted';
}
