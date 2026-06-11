/// Model สำหรับ inventory_lots (FEFO tracking)
class InventoryLot {
  final String id;
  final String professionId;
  final String productId;
  final String? branchId;
  final String? warehouseLocationId;
  final String lotNumber;
  final DateTime? expiryDate;
  final DateTime? manufactureDate;
  final int quantityReceived;
  final int quantityRemaining;
  final double unitCost;
  final String? poId;
  final String status; // active, expired, depleted, quarantined, returned
  final String? notes;
  final DateTime createdAt;

  const InventoryLot({
    required this.id,
    required this.professionId,
    required this.productId,
    this.branchId,
    this.warehouseLocationId,
    required this.lotNumber,
    this.expiryDate,
    this.manufactureDate,
    this.quantityReceived = 0,
    this.quantityRemaining = 0,
    this.unitCost = 0,
    this.poId,
    this.status = 'active',
    this.notes,
    required this.createdAt,
  });

  factory InventoryLot.fromJson(Map<String, dynamic> json) {
    return InventoryLot(
      id: json['id'] as String,
      professionId: json['profession_id'] as String,
      productId: json['product_id'] as String,
      branchId: json['branch_id'] as String?,
      warehouseLocationId: json['warehouse_location_id'] as String?,
      lotNumber: json['lot_number'] as String,
      expiryDate: json['expiry_date'] != null ? DateTime.parse(json['expiry_date'] as String) : null,
      manufactureDate: json['manufacture_date'] != null ? DateTime.parse(json['manufacture_date'] as String) : null,
      quantityReceived: json['quantity_received'] as int? ?? 0,
      quantityRemaining: json['quantity_remaining'] as int? ?? 0,
      unitCost: (json['unit_cost'] as num?)?.toDouble() ?? 0,
      poId: json['po_id'] as String?,
      status: json['status'] as String? ?? 'active',
      notes: json['notes'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'profession_id': professionId,
      'product_id': productId,
      'branch_id': branchId,
      'warehouse_location_id': warehouseLocationId,
      'lot_number': lotNumber,
      'expiry_date': expiryDate?.toIso8601String(),
      'manufacture_date': manufactureDate?.toIso8601String(),
      'quantity_received': quantityReceived,
      'quantity_remaining': quantityRemaining,
      'unit_cost': unitCost,
      'po_id': poId,
      'status': status,
      'notes': notes,
      'created_at': createdAt.toIso8601String(),
    };
  }

  bool get isExpired {
    if (expiryDate == null) return false;
    return DateTime.now().isAfter(expiryDate!);
  }

  bool get isNearExpiry {
    if (expiryDate == null) return false;
    final daysUntilExpiry = expiryDate!.difference(DateTime.now()).inDays;
    return daysUntilExpiry <= 30 && daysUntilExpiry > 0;
  }

  String get statusLabel {
    switch (status) {
      case 'active': return 'Active';
      case 'expired': return 'Expired';
      case 'depleted': return 'Depleted';
      case 'quarantined': return 'Quarantined';
      case 'returned': return 'Returned';
      default: return status;
    }
  }
}
