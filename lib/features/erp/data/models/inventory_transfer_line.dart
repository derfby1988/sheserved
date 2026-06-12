/// Model สำหรับ inventory_transfer_lines (รายการโอนย้าย)
class InventoryTransferLine {
  final String id;
  final String transferId;
  final String inventoryItemId;
  final int quantity;
  final int quantityReceived;
  final DateTime createdAt;

  const InventoryTransferLine({
    required this.id,
    required this.transferId,
    required this.inventoryItemId,
    this.quantity = 1,
    this.quantityReceived = 0,
    required this.createdAt,
  });

  factory InventoryTransferLine.fromJson(Map<String, dynamic> json) {
    return InventoryTransferLine(
      id: json['id'] as String,
      transferId: json['transfer_id'] as String,
      inventoryItemId: json['inventory_item_id'] as String,
      quantity: (json['quantity'] as num?)?.toInt() ?? 1,
      quantityReceived: (json['quantity_received'] as num?)?.toInt() ?? 0,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'transfer_id': transferId,
      'inventory_item_id': inventoryItemId,
      'quantity': quantity,
      'quantity_received': quantityReceived,
      'created_at': createdAt.toIso8601String(),
    };
  }

  int get remaining => quantity - quantityReceived;
  bool get isFullyReceived => quantityReceived >= quantity;
}
