/// Model สำหรับ inventory_transfers (โอนย้ายสินค้า)
class InventoryTransfer {
  final String id;
  final String professionId;
  final String? fromBranchId;
  final String? fromWarehouseId;
  final String? toBranchId;
  final String? toWarehouseId;
  final String transferStatus; // pending, in_transit, completed, rejected, cancelled
  final String? requestedBy;
  final String? approvedBy;
  final DateTime? approvedAt;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  const InventoryTransfer({
    required this.id,
    required this.professionId,
    this.fromBranchId,
    this.fromWarehouseId,
    this.toBranchId,
    this.toWarehouseId,
    this.transferStatus = 'pending',
    this.requestedBy,
    this.approvedBy,
    this.approvedAt,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
  });

  factory InventoryTransfer.fromJson(Map<String, dynamic> json) {
    return InventoryTransfer(
      id: json['id'] as String,
      professionId: json['profession_id'] as String,
      fromBranchId: json['from_branch_id'] as String?,
      fromWarehouseId: json['from_warehouse_id'] as String?,
      toBranchId: json['to_branch_id'] as String?,
      toWarehouseId: json['to_warehouse_id'] as String?,
      transferStatus: json['transfer_status'] as String? ?? 'pending',
      requestedBy: json['requested_by'] as String?,
      approvedBy: json['approved_by'] as String?,
      approvedAt: json['approved_at'] != null
          ? DateTime.parse(json['approved_at'] as String)
          : null,
      notes: json['notes'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'profession_id': professionId,
      'from_branch_id': fromBranchId,
      'from_warehouse_id': fromWarehouseId,
      'to_branch_id': toBranchId,
      'to_warehouse_id': toWarehouseId,
      'transfer_status': transferStatus,
      'requested_by': requestedBy,
      'approved_by': approvedBy,
      'approved_at': approvedAt?.toIso8601String(),
      'notes': notes,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  String get statusLabel {
    switch (transferStatus) {
      case 'pending': return 'รออนุมัติ';
      case 'in_transit': return 'ระหว่างโอน';
      case 'completed': return 'สำเร็จ';
      case 'rejected': return 'ถูกปฏิเสธ';
      case 'cancelled': return 'ยกเลิก';
      default: return transferStatus;
    }
  }

  bool get isPending => transferStatus == 'pending';
  bool get isInTransit => transferStatus == 'in_transit';
  bool get isCompleted => transferStatus == 'completed';
}
