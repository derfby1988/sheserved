/// Model สำหรับ gl_entries (Accounting Core)
class GlEntry {
  final String id;
  final String professionId;
  final DateTime entryDate;
  final String accountId;
  final String? orderId;
  final String? paymentTxnId;
  final String? journalEntryId;
  final String? journalEntryLineId;
  final String? documentType;
  final String? sapTransactionCode;
  final String? formNumber;
  final double debitAmount;
  final double creditAmount;
  final String? description;
  final String? referenceNo;
  final String? createdBy;
  final DateTime createdAt;

  const GlEntry({
    required this.id,
    required this.professionId,
    required this.entryDate,
    required this.accountId,
    this.orderId,
    this.paymentTxnId,
    this.journalEntryId,
    this.journalEntryLineId,
    this.documentType,
    this.sapTransactionCode,
    this.formNumber,
    this.debitAmount = 0,
    this.creditAmount = 0,
    this.description,
    this.referenceNo,
    this.createdBy,
    required this.createdAt,
  });

  factory GlEntry.fromJson(Map<String, dynamic> json) {
    return GlEntry(
      id: json['id'] as String,
      professionId: json['profession_id'] as String,
      entryDate: DateTime.parse(json['entry_date'] as String),
      accountId: json['account_id'] as String,
      orderId: json['order_id'] as String?,
      paymentTxnId: json['payment_txn_id'] as String?,
      journalEntryId: json['journal_entry_id'] as String?,
      journalEntryLineId: json['journal_entry_line_id'] as String?,
      documentType: json['document_type'] as String?,
      sapTransactionCode: json['sap_transaction_code'] as String?,
      formNumber: json['form_number'] as String?,
      debitAmount: (json['debit_amount'] as num?)?.toDouble() ?? 0,
      creditAmount: (json['credit_amount'] as num?)?.toDouble() ?? 0,
      description: json['description'] as String?,
      referenceNo: json['reference_no'] as String?,
      createdBy: json['created_by'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'profession_id': professionId,
      'entry_date': entryDate.toIso8601String(),
      'account_id': accountId,
      'order_id': orderId,
      'payment_txn_id': paymentTxnId,
      'journal_entry_id': journalEntryId,
      'journal_entry_line_id': journalEntryLineId,
      'document_type': documentType,
      'sap_transaction_code': sapTransactionCode,
      'form_number': formNumber,
      'debit_amount': debitAmount,
      'credit_amount': creditAmount,
      'description': description,
      'reference_no': referenceNo,
      'created_by': createdBy,
      'created_at': createdAt.toIso8601String(),
    };
  }

  bool get isDebit => debitAmount > 0;
  bool get isCredit => creditAmount > 0;
  double get amount => isDebit ? debitAmount : creditAmount;
}
