import 'package:flutter/material.dart';

/// Model สำหรับ back_orders
class BackOrder {
  final String id;
  final String professionId;
  final String purchaseOrderId;
  final String purchaseOrderItemId;
  final String supplierId;
  final int quantityBackOrdered;
  final int quantityFulfilled;
  final DateTime? expectedDeliveryDate;
  final String status; // open, partially_fulfilled, fulfilled, cancelled
  final String? notes;
  final bool notifiedRequester;
  final bool notifiedApprover;
  final bool notifiedReceiver;
  final bool notifiedSupplier;
  final DateTime createdAt;
  final DateTime updatedAt;

  // Joined fields
  final String? poNumber;
  final String? supplierName;
  final String? productName;

  const BackOrder({
    required this.id,
    required this.professionId,
    required this.purchaseOrderId,
    required this.purchaseOrderItemId,
    required this.supplierId,
    required this.quantityBackOrdered,
    required this.quantityFulfilled,
    this.expectedDeliveryDate,
    required this.status,
    this.notes,
    this.notifiedRequester = false,
    this.notifiedApprover = false,
    this.notifiedReceiver = false,
    this.notifiedSupplier = false,
    required this.createdAt,
    required this.updatedAt,
    this.poNumber,
    this.supplierName,
    this.productName,
  });

  factory BackOrder.fromJson(Map<String, dynamic> json) {
    String? poNum;
    if (json['purchase_order'] != null) {
      poNum = json['purchase_order']['po_number'] as String?;
    }
    String? supName;
    if (json['supplier'] != null) {
      supName = json['supplier']['supplier_name'] as String?;
    }
    String? prodName;
    if (json['purchase_order_item'] != null &&
        json['purchase_order_item']['product'] != null) {
      prodName = json['purchase_order_item']['product']['name'] as String?;
    }

    return BackOrder(
      id: json['id'] as String,
      professionId: json['profession_id'] as String,
      purchaseOrderId: json['purchase_order_id'] as String,
      purchaseOrderItemId: json['purchase_order_item_id'] as String,
      supplierId: json['supplier_id'] as String,
      quantityBackOrdered: json['quantity_back_ordered'] as int? ?? 0,
      quantityFulfilled: json['quantity_fulfilled'] as int? ?? 0,
      expectedDeliveryDate: json['expected_delivery_date'] != null
          ? DateTime.parse(json['expected_delivery_date'] as String)
          : null,
      status: json['status'] as String? ?? 'open',
      notes: json['notes'] as String?,
      notifiedRequester: json['notified_requester'] as bool? ?? false,
      notifiedApprover: json['notified_approver'] as bool? ?? false,
      notifiedReceiver: json['notified_receiver'] as bool? ?? false,
      notifiedSupplier: json['notified_supplier'] as bool? ?? false,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      poNumber: poNum ?? json['po_number'] as String?,
      supplierName: supName ?? json['supplier_name'] as String?,
      productName: prodName ?? json['product_name'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'profession_id': professionId,
      'purchase_order_id': purchaseOrderId,
      'purchase_order_item_id': purchaseOrderItemId,
      'supplier_id': supplierId,
      'quantity_back_ordered': quantityBackOrdered,
      'quantity_fulfilled': quantityFulfilled,
      'expected_delivery_date':
          expectedDeliveryDate?.toIso8601String().split('T')[0],
      'status': status,
      'notes': notes,
      'notified_requester': notifiedRequester,
      'notified_approver': notifiedApprover,
      'notified_receiver': notifiedReceiver,
      'notified_supplier': notifiedSupplier,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  int get remainingQuantity => quantityBackOrdered - quantityFulfilled;

  String get statusLabel {
    switch (status) {
      case 'open':
        return 'ค้างส่ง';
      case 'partially_fulfilled':
        return 'ส่งบางส่วน';
      case 'fulfilled':
        return 'ส่งครบแล้ว';
      case 'cancelled':
        return 'ยกเลิก';
      default:
        return status;
    }
  }

  Color get statusColor {
    switch (status) {
      case 'open':
        return Colors.red;
      case 'partially_fulfilled':
        return Colors.orange;
      case 'fulfilled':
        return Colors.green;
      case 'cancelled':
        return Colors.grey;
      default:
        return Colors.grey;
    }
  }

  bool get isOpen => status == 'open';
  bool get isPartiallyFulfilled => status == 'partially_fulfilled';
  bool get isFulfilled => status == 'fulfilled';
  bool get isCancelled => status == 'cancelled';
}
