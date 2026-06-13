/// Model สำหรับ accounts_receivable (ลูกหนี้การค้า)
class AccountsReceivable {
  final String id;
  final String professionId;
  final String customerId;
  final String orderId;
  final String? invoiceNumber;
  final double amount;
  final double paidAmount;
  final double balance;
  final DateTime? dueDate;
  final String status; // open, partial, paid, overdue, written_off
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  const AccountsReceivable({
    required this.id,
    required this.professionId,
    required this.customerId,
    required this.orderId,
    this.invoiceNumber,
    this.amount = 0,
    this.paidAmount = 0,
    this.balance = 0,
    this.dueDate,
    this.status = 'open',
    this.notes,
    required this.createdAt,
    required this.updatedAt,
  });

  factory AccountsReceivable.fromJson(Map<String, dynamic> json) {
    return AccountsReceivable(
      id: json['id'] as String,
      professionId: json['profession_id'] as String,
      customerId: json['customer_id'] as String,
      orderId: json['order_id'] as String,
      invoiceNumber: json['invoice_number'] as String?,
      amount: (json['amount'] as num?)?.toDouble() ?? 0,
      paidAmount: (json['paid_amount'] as num?)?.toDouble() ?? 0,
      balance: (json['balance'] as num?)?.toDouble() ?? 0,
      dueDate: json['due_date'] != null
          ? DateTime.parse(json['due_date'] as String)
          : null,
      status: json['status'] as String? ?? 'open',
      notes: json['notes'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'profession_id': professionId,
      'customer_id': customerId,
      'order_id': orderId,
      'invoice_number': invoiceNumber,
      'amount': amount,
      'paid_amount': paidAmount,
      'balance': balance,
      'due_date': dueDate?.toIso8601String(),
      'status': status,
      'notes': notes,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  String get statusLabel {
    switch (status) {
      case 'open': return 'ค้างชำระ';
      case 'partial': return 'ชำระบางส่วน';
      case 'paid': return 'ชำระแล้ว';
      case 'overdue': return 'เลยกำหนด';
      case 'written_off': return 'ตัดหนี้สูญ';
      default: return status;
    }
  }

  bool get isOverdue {
    if (dueDate == null) return false;
    return status != 'paid' && status != 'written_off' && DateTime.now().isAfter(dueDate!);
  }
}
