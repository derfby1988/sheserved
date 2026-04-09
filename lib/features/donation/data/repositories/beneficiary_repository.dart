import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../services/service_locator.dart';

// =====================================================
// MODELS
// =====================================================

/// หน่วยงานผู้รับมรดก (Beneficiary Organization)
/// ทำหน้าที่เป็น Escrow Account รับเงินบริจาคพักไว้จนกว่าภารกิจจะสมบูรณ์
/// ต้องเป็นนิติบุคคลที่จดทะเบียนถูกกฎหมายและผ่านการ verify ก่อน activate
class BeneficiaryOrganization {
  final String id;
  final String name;
  final String? registrationNo;   // เลขทะเบียนนิติบุคคล
  final String? bankName;
  final String? bankAccount;      // เลขบัญชี (masked เมื่อแสดง UI)
  final String? bankAccountName;
  final String? contactEmail;
  final String? omiseRecipientId; // Omise Recipient ID
  final String? promptpayId;      // PromptPay ID
  final bool isVerified;
  final bool isActive;
  final bool isGlobalDefault;
  final bool hasMou;
  final DateTime createdAt;
  final DateTime updatedAt;

  const BeneficiaryOrganization({
    required this.id,
    required this.name,
    this.registrationNo,
    this.bankName,
    this.bankAccount,
    this.bankAccountName,
    this.contactEmail,
    this.omiseRecipientId,
    this.promptpayId,
    this.isVerified = false,
    this.isActive = false,
    this.isGlobalDefault = false,
    this.hasMou = false,
    required this.createdAt,
    required this.updatedAt,
  });

  factory BeneficiaryOrganization.fromJson(Map<String, dynamic> json) {
    return BeneficiaryOrganization(
      id: json['id'] as String,
      name: json['name'] as String,
      registrationNo: json['registration_no']?.toString(),
      bankName: json['bank_name']?.toString(),
      bankAccount: json['bank_account']?.toString(),
      bankAccountName: json['bank_account_name']?.toString(),
      contactEmail: json['contact_email']?.toString(),
      omiseRecipientId: json['omise_recipient_id']?.toString(),
      promptpayId: json['promptpay_id']?.toString(),
      isVerified: json['is_verified'] as bool? ?? false,
      isActive: json['is_active'] as bool? ?? false,
      isGlobalDefault: json['is_global_default'] as bool? ?? false,
      hasMou: json['has_mou'] as bool? ?? false,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'registration_no': registrationNo,
      'bank_name': bankName,
      'bank_account': bankAccount,
      'bank_account_name': bankAccountName,
      'contact_email': contactEmail,
      'omise_recipient_id': omiseRecipientId,
      'promptpay_id': promptpayId,
      'is_verified': isVerified,
      'is_active': isActive,
      'is_global_default': isGlobalDefault,
      'has_mou': hasMou,
    };
  }

  /// แสดงเลขบัญชีแบบ masked (เช่น 0XX-X-XXXXX-X)
  String get maskedBankAccount {
    if (bankAccount == null || bankAccount!.isEmpty) return '-';
    final digits = bankAccount!.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length < 4) return bankAccount!;
    return '${digits.substring(0, 1)}XX-X-XXXXX-${digits.substring(digits.length - 1)}';
  }

  BeneficiaryOrganization copyWith({
    String? name,
    String? registrationNo,
    String? bankName,
    String? bankAccount,
    String? bankAccountName,
    String? contactEmail,
    String? omiseRecipientId,
    String? promptpayId,
    bool? isVerified,
    bool? isActive,
    bool? isGlobalDefault,
    bool? hasMou,
  }) {
    return BeneficiaryOrganization(
      id: id,
      name: name ?? this.name,
      registrationNo: registrationNo ?? this.registrationNo,
      bankName: bankName ?? this.bankName,
      bankAccount: bankAccount ?? this.bankAccount,
      bankAccountName: bankAccountName ?? this.bankAccountName,
      contactEmail: contactEmail ?? this.contactEmail,
      omiseRecipientId: omiseRecipientId ?? this.omiseRecipientId,
      promptpayId: promptpayId ?? this.promptpayId,
      isVerified: isVerified ?? this.isVerified,
      isActive: isActive ?? this.isActive,
      isGlobalDefault: isGlobalDefault ?? this.isGlobalDefault,
      hasMou: hasMou ?? this.hasMou,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }
}

/// Audit Log ของการเปลี่ยนแปลงข้อมูล BeneficiaryOrganization
class BeneficiaryAuditLog {
  final String id;
  final String orgId;
  final String changedBy;   // userId ของ Super Admin (จาก ServiceLocator)
  final String action;      // 'INSERT' | 'UPDATE' | 'DEACTIVATE' | 'VERIFY'
  final Map<String, dynamic>? oldData;
  final Map<String, dynamic>? newData;
  final DateTime changedAt;

  const BeneficiaryAuditLog({
    required this.id,
    required this.orgId,
    required this.changedBy,
    required this.action,
    this.oldData,
    this.newData,
    required this.changedAt,
  });

  factory BeneficiaryAuditLog.fromJson(Map<String, dynamic> json) {
    return BeneficiaryAuditLog(
      id: json['id'] as String,
      orgId: json['org_id'] as String,
      changedBy: json['changed_by'] as String,
      action: json['action'] as String,
      oldData: json['old_data'] as Map<String, dynamic>?,
      newData: json['new_data'] as Map<String, dynamic>?,
      changedAt: DateTime.parse(json['changed_at'] as String),
    );
  }
}

/// Log การโอนเงินให้ Beneficiary แบบถาวร (กรณีพิเศษ)
class BeneficiaryTransferLog {
  final String id;
  final String requestId;
  final String beneficiaryId;
  final double amount;
  final String reason; // 'pause_deadline' | 'transfer_failed' | 'cancellation'
  final String? transferRef;
  final DateTime transferredAt;
  final String? note;

  const BeneficiaryTransferLog({
    required this.id,
    required this.requestId,
    required this.beneficiaryId,
    required this.amount,
    required this.reason,
    this.transferRef,
    required this.transferredAt,
    this.note,
  });

  factory BeneficiaryTransferLog.fromJson(Map<String, dynamic> json) {
    double parseDouble(dynamic v) {
      if (v == null) return 0.0;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString()) ?? 0.0;
    }

    return BeneficiaryTransferLog(
      id: json['id'] as String,
      requestId: json['request_id'] as String,
      beneficiaryId: json['beneficiary_id'] as String,
      amount: parseDouble(json['amount']),
      reason: json['reason'] as String,
      transferRef: json['transfer_ref']?.toString(),
      transferredAt: DateTime.parse(json['transferred_at'] as String),
      note: json['note']?.toString(),
    );
  }
}

// =====================================================
// REPOSITORY
// =====================================================

/// Repository สำหรับจัดการข้อมูล Beneficiary Organizations
///
/// ## Auth Guidelines (ตาม /auth_data_guidelines.md)
/// ❌ ห้ามใช้ `Supabase.instance.client.auth.currentUser` หรือ `_client.auth.currentUser`
/// ✅ ดึง userId เสมอจาก `ServiceLocator.instance.currentUser?.id`
/// ✅ ส่ง changedBy (userId) เข้าไปใน audit log ทุกครั้งที่มีการแก้ไข
///
/// ## สิทธิ์
/// เฉพาะ Super Admin เท่านั้นที่แก้ไขได้ (ตรวจสอบฝั่ง App ก่อนเรียก method เหล่านี้)
/// ทุกครั้งที่มีการ INSERT/UPDATE/DEACTIVATE ต้องบันทึก audit log
class BeneficiaryRepository {
  final SupabaseClient _client;

  BeneficiaryRepository(this._client);

  // =====================================================
  // READ
  // =====================================================

  /// ดึง Beneficiary Organizations ทั้งหมด
  Future<List<BeneficiaryOrganization>> getAll({bool activeOnly = false}) async {
    var query = _client.from('beneficiary_organizations').select();
    if (activeOnly) {
      query = query.eq('is_active', true);
    }
    final response = await query.order('is_global_default', ascending: false)
        .order('name');
    return (response as List)
        .map((json) => BeneficiaryOrganization.fromJson(json))
        .toList();
  }

  /// ดึง Beneficiary Organization ตาม ID
  Future<BeneficiaryOrganization?> getById(String id) async {
    final response = await _client
        .from('beneficiary_organizations')
        .select()
        .eq('id', id)
        .maybeSingle();
    if (response == null) return null;
    return BeneficiaryOrganization.fromJson(response);
  }

  /// ดึง Global Default Beneficiary (ใช้เป็น Fallback ถ้า category ไม่มี beneficiary)
  Future<BeneficiaryOrganization?> getGlobalDefault() async {
    final response = await _client
        .from('beneficiary_organizations')
        .select()
        .eq('is_global_default', true)
        .eq('is_active', true)
        .eq('is_verified', true)
        .maybeSingle();
    if (response == null) return null;
    return BeneficiaryOrganization.fromJson(response);
  }

  /// ดึง Beneficiary ที่ใช้งานได้สำหรับ Category นี้
  /// ถ้า Category ไม่มี → คืน Global Default
  /// ถ้าไม่มีทั้งคู่ → คืน null (ระบบต้อง block + แจ้ง Admin)
  Future<BeneficiaryOrganization?> getEffectiveForCategory(String categoryId) async {
    try {
      final result = await _client.rpc(
        'get_effective_beneficiary',
        params: {'p_category_id': categoryId},
      );
      if (result == null) return null;
      return await getById(result as String);
    } catch (e) {
      debugPrint('[BeneficiaryRepository] getEffectiveForCategory error: $e');
      return null;
    }
  }

  /// ดึง Audit Logs ของ Beneficiary Organization นี้
  Future<List<BeneficiaryAuditLog>> getAuditLogs(String orgId) async {
    final response = await _client
        .from('beneficiary_audit_logs')
        .select()
        .eq('org_id', orgId)
        .order('changed_at', ascending: false);
    return (response as List)
        .map((json) => BeneficiaryAuditLog.fromJson(json))
        .toList();
  }

  /// ดึง Transfer Logs สำหรับ request นี้ (กรณีโอนให้ Beneficiary ถาวร)
  Future<List<BeneficiaryTransferLog>> getTransferLogs(String requestId) async {
    final response = await _client
        .from('beneficiary_transfer_logs')
        .select()
        .eq('request_id', requestId)
        .order('transferred_at', ascending: false);
    return (response as List)
        .map((json) => BeneficiaryTransferLog.fromJson(json))
        .toList();
  }

  // =====================================================
  // WRITE (Super Admin only — ตรวจสิทธิ์ก่อนเรียก)
  // =====================================================

  /// สร้าง Beneficiary Organization ใหม่
  /// [data] = Map ของ field ที่ต้องการบันทึก
  /// ⚠️ ต้องผ่านการ verify ก่อน activate เสมอ
  Future<String> create(Map<String, dynamic> data) async {
    // ✅ Auth Guideline: ดึง userId จาก ServiceLocator เท่านั้น
    final adminUserId = ServiceLocator.instance.currentUser?.id;
    if (adminUserId == null) {
      throw Exception('ไม่พบข้อมูลผู้ใช้ กรุณาเข้าสู่ระบบก่อน');
    }

    // บังคับ is_active = false เมื่อสร้างใหม่ (ต้อง verify ก่อน)
    final insertData = Map<String, dynamic>.from(data);
    insertData['is_active'] = false;
    insertData['is_verified'] = false;

    final response = await _client
        .from('beneficiary_organizations')
        .insert(insertData)
        .select('id')
        .single();
    final newId = response['id'] as String;

    // บันทึก Audit Log ทันที
    await _writeAuditLog(
      orgId: newId,
      changedBy: adminUserId,
      action: 'INSERT',
      oldData: null,
      newData: insertData,
    );

    debugPrint('[BeneficiaryRepository] Created org: $newId');
    return newId;
  }

  /// อัปเดตข้อมูล Beneficiary Organization
  Future<void> update(String id, Map<String, dynamic> data) async {
    // ✅ Auth Guideline: ดึง userId จาก ServiceLocator เท่านั้น
    final adminUserId = ServiceLocator.instance.currentUser?.id;
    if (adminUserId == null) {
      throw Exception('ไม่พบข้อมูลผู้ใช้ กรุณาเข้าสู่ระบบก่อน');
    }

    // ดึงค่าเดิมสำหรับ Audit Log
    final oldResponse = await _client
        .from('beneficiary_organizations')
        .select()
        .eq('id', id)
        .maybeSingle();

    final updateData = Map<String, dynamic>.from(data);
    updateData['updated_at'] = DateTime.now().toIso8601String();

    await _client
        .from('beneficiary_organizations')
        .update(updateData)
        .eq('id', id);

    // บันทึก Audit Log
    await _writeAuditLog(
      orgId: id,
      changedBy: adminUserId,
      action: 'UPDATE',
      oldData: oldResponse,
      newData: updateData,
    );

    debugPrint('[BeneficiaryRepository] Updated org: $id');
  }

  /// Verify บัญชีธนาคาร (ตรวจสอบเอกสารและบัญชีธนาคารเรียบร้อยแล้ว)
  /// หลัง verify แล้วจึงสามารถ activate ได้
  Future<void> verify(String id) async {
    // ✅ Auth Guideline: ดึง userId จาก ServiceLocator เท่านั้น
    final adminUserId = ServiceLocator.instance.currentUser?.id;
    if (adminUserId == null) {
      throw Exception('ไม่พบข้อมูลผู้ใช้ กรุณาเข้าสู่ระบบก่อน');
    }

    await _client
        .from('beneficiary_organizations')
        .update({
          'is_verified': true,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', id);

    await _writeAuditLog(
      orgId: id,
      changedBy: adminUserId,
      action: 'VERIFY',
      oldData: null,
      newData: {'is_verified': true},
    );

    debugPrint('[BeneficiaryRepository] Verified org: $id');
  }

  /// Activate/Deactivate Beneficiary Organization
  /// ⚠️ Activate ได้เฉพาะเมื่อ is_verified = true (enforce ที่ DB Constraint)
  Future<void> setActive(String id, {required bool isActive}) async {
    // ✅ Auth Guideline: ดึง userId จาก ServiceLocator เท่านั้น
    final adminUserId = ServiceLocator.instance.currentUser?.id;
    if (adminUserId == null) {
      throw Exception('ไม่พบข้อมูลผู้ใช้ กรุณาเข้าสู่ระบบก่อน');
    }

    await _client
        .from('beneficiary_organizations')
        .update({
          'is_active': isActive,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', id);

    await _writeAuditLog(
      orgId: id,
      changedBy: adminUserId,
      action: isActive ? 'UPDATE' : 'DEACTIVATE',
      oldData: null,
      newData: {'is_active': isActive},
    );

    debugPrint('[BeneficiaryRepository] Set org $id active=$isActive');
  }

  /// บันทึก Transfer Log เมื่อโอนเงินให้ Beneficiary ถาวร (กรณีพิเศษ)
  Future<void> recordTransfer({
    required String requestId,
    required String beneficiaryId,
    required double amount,
    required String reason,
    String? transferRef,
    String? note,
  }) async {
    await _client.from('beneficiary_transfer_logs').insert({
      'request_id': requestId,
      'beneficiary_id': beneficiaryId,
      'amount': amount,
      'reason': reason,
      'transfer_ref': transferRef,
      'transferred_at': DateTime.now().toIso8601String(),
      'note': note,
    });

    debugPrint('[BeneficiaryRepository] Recorded transfer: ฿$amount → $beneficiaryId (reason: $reason)');
  }

  // =====================================================
  // PRIVATE HELPERS
  // =====================================================

  /// เขียน Audit Log ทุกครั้งที่มีการแก้ไขข้อมูล Beneficiary
  /// changedBy ต้องมาจาก ServiceLocator.instance.currentUser?.id เสมอ
  Future<void> _writeAuditLog({
    required String orgId,
    required String changedBy,
    required String action,
    Map<String, dynamic>? oldData,
    Map<String, dynamic>? newData,
  }) async {
    try {
      await _client.from('beneficiary_audit_logs').insert({
        'org_id': orgId,
        'changed_by': changedBy,
        'action': action,
        'old_data': oldData,
        'new_data': newData,
        'changed_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      // Audit log failure ไม่ควร block การทำงานหลัก
      // แต่ต้อง log ไว้เสมอ
      debugPrint('[BeneficiaryRepository] ⚠️ Audit log write failed: $e');
    }
  }
}
