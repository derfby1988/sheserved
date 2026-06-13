/// Model สำหรับ accounts_payable (เจ้าหนี้การค้า)
class AccountsPayable {
  final String id;
  final String professionId;
  final String supplierId;
  final String? poId;
  final String? invoiceNumber;
  final double amount;
  final double paidAmount;
  final double balance;
  final DateTime? dueDate;
  final String status; // open, partial, paid, overdue, written_off
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  const AccountsPayable({
    required this.id,
    required this.professionId,
    required this.supplierId,
    this.poId,
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

  factory AccountsPayable.fromJson(Map<String, dynamic> json) {
    return AccountsPayable(
      id: json['id'] as String,
      professionId: json['profession_id'] as String,
      supplierId: json['supplier_id'] as String,
      poId: json['po_id'] as String?,
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
      'supplier_id': supplierId,
      'po_id': poId,
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
      case 'open': return 'ค้างจ่าย';
      case 'partial': return 'จ่ายบางส่วน';
      case 'paid': return 'จ่ายแล้ว';
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
