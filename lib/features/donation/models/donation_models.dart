import 'fee_models.dart';

// ====================================================
// EscrowStatus — สถานะ Escrow ของคำร้องบริจาค
// ====================================================

enum EscrowStatus {
  /// ยังไม่มี transaction ใดถูก confirm
  notStarted,
  /// มีเงินพักที่ Beneficiary Escrow Account อยู่
  inEscrow,
  /// Beneficiary โอนให้ Reporter สำเร็จแล้ว
  released,
  /// เงินถูกคืนให้ผู้บริจาค หรือโอนให้ Beneficiary ถาวร
  returned;

  static EscrowStatus fromString(String? value) {
    switch (value) {
      case 'in_escrow':
        return EscrowStatus.inEscrow;
      case 'released':
        return EscrowStatus.released;
      case 'returned':
        return EscrowStatus.returned;
      default:
        return EscrowStatus.notStarted;
    }
  }

  String get dbValue {
    switch (this) {
      case EscrowStatus.notStarted:
        return 'not_started';
      case EscrowStatus.inEscrow:
        return 'in_escrow';
      case EscrowStatus.released:
        return 'released';
      case EscrowStatus.returned:
        return 'returned';
    }
  }
}

enum DonationApprovalStatus {
  pending_local,
  active,
  rejected,
  cancelled;

  static DonationApprovalStatus fromString(String? status) {
    return DonationApprovalStatus.values.firstWhere(
      (e) => e.name == status,
      orElse: () => DonationApprovalStatus.pending_local,
    );
  }
}

class DonationCategoryField {
  final String id;
  final String label;
  final String type; // 'text', 'number', 'long_text', 'date'
  final bool isRequired;

  const DonationCategoryField({
    required this.id,
    required this.label,
    required this.type,
    this.isRequired = false,
  });

  factory DonationCategoryField.fromJson(Map<String, dynamic> json) {
    return DonationCategoryField(
      id: json['id'] ?? '',
      label: json['label'] ?? '',
      type: json['type'] ?? 'text',
      isRequired: json['is_required'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'label': label,
      'type': type,
      'is_required': isRequired,
    };
  }
}


/// หมวดหมู่การบริจาค/ขอความช่วยเหลือ
class DonationCategory {
  final String id;
  final String name;
  final String? nameEn;
  final String? iconName;
  final bool isEmergency;
  final int displayOrder;
  final List<String> volunteerProfessionIds;
  final List<DonationCategoryField> customFields;
  // รายชื่อ profession_id ที่ต้องอนุมัติทั้งหมดก่อนคำร้องจะ active ได้
  // สามารถมีหลายกลุ่มอาชีพ และทุกกลุ่มต้องอนุมัติครบ
  final List<String> approverProfessionIds;

  // --- Escrow & Beneficiary ---
  final String? beneficiaryOrgId;
  final String? sheservedAccountId; // บัญชีแพลตฟอร์มรับรายได้
  final int pauseGracePeriodHours;
  final int transferFailureGraceHours;
  final int cancellationGraceHours;

  const DonationCategory({
    required this.id,
    required this.name,
    this.nameEn,
    this.iconName,
    this.isEmergency = false,
    this.displayOrder = 0,
    this.volunteerProfessionIds = const [],
    this.customFields = const [],
    this.approverProfessionIds = const [],
    this.beneficiaryOrgId,
    this.sheservedAccountId,
    this.pauseGracePeriodHours = 72,
    this.transferFailureGraceHours = 48,
    this.cancellationGraceHours = 24,
  });

  factory DonationCategory.fromJson(Map<String, dynamic> json) {
    List<DonationCategoryField> fields = [];
    if (json['custom_fields'] != null) {
      final list = json['custom_fields'] as List;
      fields = list.map((e) => DonationCategoryField.fromJson(e)).toList();
    }

    List<String> volunteerIds = [];
    if (json['volunteer_profession_ids'] != null) {
      if (json['volunteer_profession_ids'] is List) {
        volunteerIds = List<String>.from(json['volunteer_profession_ids']);
      }
    }

    List<String> approverIds = [];
    if (json['approver_profession_ids'] != null) {
      if (json['approver_profession_ids'] is List) {
        approverIds = List<String>.from(json['approver_profession_ids']);
      }
    }

    return DonationCategory(
      id: json['id'],
      name: json['name'] ?? '',
      nameEn: json['name_en'],
      iconName: json['icon_name'],
      isEmergency: json['is_emergency'] ?? false,
      displayOrder: (json['display_order'] is num)
          ? (json['display_order'] as num).toInt()
          : int.tryParse(json['display_order']?.toString() ?? '0') ?? 0,
      volunteerProfessionIds: volunteerIds,
      customFields: fields,
      approverProfessionIds: approverIds,
      beneficiaryOrgId: json['beneficiary_org_id'],
      sheservedAccountId: json['sheserved_account_id'],
      pauseGracePeriodHours: json['pause_grace_period_hours'] != null 
          ? int.tryParse(json['pause_grace_period_hours'].toString()) ?? 72 : 72,
      transferFailureGraceHours: json['transfer_failure_grace_hours'] != null 
          ? int.tryParse(json['transfer_failure_grace_hours'].toString()) ?? 48 : 48,
      cancellationGraceHours: json['cancellation_grace_hours'] != null 
          ? int.tryParse(json['cancellation_grace_hours'].toString()) ?? 24 : 24,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'name_en': nameEn,
      'icon_name': iconName,
      'is_emergency': isEmergency,
      'display_order': displayOrder,
      'volunteer_profession_ids': volunteerProfessionIds,
      'custom_fields': customFields.map((e) => e.toJson()).toList(),
      'approver_profession_ids': approverProfessionIds,
      'beneficiary_org_id': beneficiaryOrgId,
      'sheserved_account_id': sheservedAccountId,
      'pause_grace_period_hours': pauseGracePeriodHours,
      'transfer_failure_grace_hours': transferFailureGraceHours,
      'cancellation_grace_hours': cancellationGraceHours,
    };
  }
}

/// คำร้องขอรับบริจาค/ความช่วยเหลือ
class DonationRequest {
  final String id;
  final String? userId;
  final String categoryId;
  final String? videoId;
  final String title;
  final String? description;
  final double? targetAmount;
  final double currentAmount;
  final String? imageUrl;
  final bool isTrending;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final DonationApprovalStatus approvalStatus;
  final String? storageApprovedBy;
  final DateTime? neededDate;
  final String? usageLocation;
  final String? requesterAddress;
  final String? localLeaderId;
  final String? communityId;
  final DateTime? localVerifiedAt;
  final double? latitude;
  final double? longitude;
  final Map<String, dynamic> customData;

  // --- Escrow & Fee Fields (Escrow-via-Beneficiary Architecture) ---

  /// สถานะ Escrow ของคำร้องนี้
  final EscrowStatus escrowStatus;

  /// ยอดที่ Reporter ต้องการได้รับจริง (Net Goal)
  final double? goalAmountNet;

  /// ยอดที่ระบบเปิดรับบริจาค = Net + Σfees (Gross Target)
  final double? goalAmountGross;

  /// Snapshot ของ fee items ณ เวลาสร้างคำร้อง (ป้องกัน Admin เปลี่ยน fee กระทบคำร้องเก่า)
  final List<FeeLineItem> feeSnapshot;

  // --- Pause / Closure Fields ---

  /// คำร้องถูกระงับชั่วคราว (Consensus ไม่ผ่าน)
  final bool isPaused;

  /// เหตุผลที่ระงับ
  final String? pauseReason;

  /// Deadline ก่อนที่ระบบโอนเงินให้ Beneficiary อัตโนมัติ
  final DateTime? pauseDeadline;

  /// เวลาที่คำร้องถูกปิด
  final DateTime? closedAt;

  /// เหตุผลที่ปิด: 'incident_resolved' | 'manual_close' | 'expired' | 'transferred_to_beneficiary'
  final String? closedReason;

  const DonationRequest({
    required this.id,
    this.userId,
    required this.categoryId,
    this.videoId,
    required this.title,
    this.description,
    this.targetAmount,
    this.currentAmount = 0,
    this.imageUrl,
    this.isTrending = false,
    required this.createdAt,
    this.updatedAt,
    this.approvalStatus = DonationApprovalStatus.pending_local,
    this.storageApprovedBy,
    this.neededDate,
    this.usageLocation,
    this.requesterAddress,
    this.localLeaderId,
    this.communityId,
    this.localVerifiedAt,
    this.latitude,
    this.longitude,
    this.customData = const {},
    this.escrowStatus = EscrowStatus.notStarted,
    this.goalAmountNet,
    this.goalAmountGross,
    this.feeSnapshot = const [],
    this.isPaused = false,
    this.pauseReason,
    this.pauseDeadline,
    this.closedAt,
    this.closedReason,
  });

  factory DonationRequest.fromJson(Map<String, dynamic> json) {
    double parseDouble(dynamic value) {
      if (value == null) return 0.0;
      if (value is num) return value.toDouble();
      if (value is String) return double.tryParse(value) ?? 0.0;
      return 0.0;
    }

    return DonationRequest(
      id: json['id'],
      userId: json['user_id'],
      categoryId: json['category_id'] ?? '',
      videoId: json['video_id'],
      title: json['title'] ?? '',
      description: json['description'],
      targetAmount: json['target_amount'] != null ? parseDouble(json['target_amount']) : null,
      currentAmount: parseDouble(json['current_amount']),
      imageUrl: json['image_url'],
      isTrending: json['is_trending'] ?? false,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : DateTime.now(),
      updatedAt: json['updated_at'] != null ? DateTime.parse(json['updated_at']) : null,
      approvalStatus: DonationApprovalStatus.fromString(json['approval_status'] ?? 'pending_local'),
      storageApprovedBy: json['storage_approved_by'],
      neededDate: json['needed_date'] != null ? DateTime.parse(json['needed_date']) : null,
      usageLocation: json['usage_location'],
      requesterAddress: json['requester_address'],
      localLeaderId: json['local_leader_id'],
      communityId: json['community_id'],
      localVerifiedAt: json['local_verified_at'] != null ? DateTime.parse(json['local_verified_at']) : null,
      latitude: json['latitude'] != null ? parseDouble(json['latitude']) : null,
      longitude: json['longitude'] != null ? parseDouble(json['longitude']) : null,
      customData: json['custom_data'] as Map<String, dynamic>? ?? {},
      escrowStatus: EscrowStatus.fromString(json['escrow_status']?.toString()),
      goalAmountNet: json['goal_amount_net'] != null ? parseDouble(json['goal_amount_net']) : null,
      goalAmountGross: json['goal_amount_gross'] != null ? parseDouble(json['goal_amount_gross']) : null,
      feeSnapshot: FeeBreakdown.parseFeeSnapshot(
        json['fee_snapshot'] as List<dynamic>?,
      ),
      isPaused: json['is_paused'] as bool? ?? false,
      pauseReason: json['pause_reason']?.toString(),
      pauseDeadline: json['pause_deadline'] != null
          ? DateTime.parse(json['pause_deadline'] as String)
          : null,
      closedAt:
          json['closed_at'] != null ? DateTime.parse(json['closed_at'] as String) : null,
      closedReason: json['closed_reason']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'category_id': categoryId,
      'video_id': videoId,
      'title': title,
      'description': description,
      'target_amount': targetAmount,
      'current_amount': currentAmount,
      'image_url': imageUrl,
      'is_trending': isTrending,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
      'approval_status': approvalStatus.name,
      'storage_approved_by': storageApprovedBy,
      'needed_date': neededDate?.toIso8601String(),
      'usage_location': usageLocation,
      'requester_address': requesterAddress,
      'local_leader_id': localLeaderId,
      'community_id': communityId,
      'local_verified_at': localVerifiedAt?.toIso8601String(),
      'latitude': latitude,
      'longitude': longitude,
      'custom_data': customData,
      'escrow_status': escrowStatus.dbValue,
      'goal_amount_net': goalAmountNet,
      'goal_amount_gross': goalAmountGross,
      'fee_snapshot': feeSnapshot.map((e) => e.toJson()).toList(),
      'is_paused': isPaused,
      'pause_reason': pauseReason,
      'pause_deadline': pauseDeadline?.toIso8601String(),
      'closed_at': closedAt?.toIso8601String(),
      'closed_reason': closedReason,
    };
  }

  double get progress {
    if (targetAmount != null && targetAmount! > 0) {
      return currentAmount / targetAmount!;
    }
    return 0.0;
  }

  double get remainingAmount {
    if (targetAmount == null) return 0;
    return (targetAmount! - currentAmount).clamp(0, double.infinity);
  }

  /// % ของ current_amount ที่สะท้อนยอด Net (หลังหักค่าธรรมเนียม)
  /// สำหรับแสดง Progress Bar ฝั่ง Viewer ตาม VIDEO_SYSTEM_PLAN.md
  /// progress_net = currentAmount × (netRatio) / goalAmountGross
  double get netProgress {
    final gross = goalAmountGross ?? targetAmount;
    if (gross == null || gross <= 0) return progress;
    if (feeSnapshot.isEmpty) return progress;
    // คำนวณ net ratio จาก fee snapshot
    final totalFeeRate = feeSnapshot
        .where((f) => f.feeType == FeeType.percentOfGross)
        .fold<double>(0.0, (sum, f) => sum + (f.rate ?? 0));
    final netRatio = (100 - totalFeeRate) / 100;
    return (currentAmount * netRatio) / gross;
  }

  bool get isClosed => closedAt != null;
  bool get isEscrowActive => escrowStatus == EscrowStatus.inEscrow;
}

/// สถิติภาพรวมของการขอรับบริจาค
class DonationStats {
  final double requested;
  final double received;
  final double remaining;

  const DonationStats({
    required this.requested,
    required this.received,
    required this.remaining,
  });
}

// =============================================================
// PAYMENT TRANSACTION MODELS
// =============================================================

/// ช่องทางการชำระเงิน
/// mock   → ใช้ใน Development: auto-confirm ทันที ไม่เสียเงินจริง
/// promptpay  → Production: แสดง QR Code แล้วรอ Webhook ยืนยัน
/// omiseCard  → Production: เชื่อม Omise SDK
enum PaymentMethod {
  mock,
  promptpay,
  omiseCard;

  String get dbValue {
    switch (this) {
      case PaymentMethod.mock:
        return 'mock';
      case PaymentMethod.promptpay:
        return 'promptpay';
      case PaymentMethod.omiseCard:
        return 'omise_card';
    }
  }

  static PaymentMethod fromString(String? value) {
    switch (value) {
      case 'promptpay':
        return PaymentMethod.promptpay;
      case 'omise_card':
        return PaymentMethod.omiseCard;
      default:
        return PaymentMethod.mock;
    }
  }
}

/// สถานะของ Transaction การชำระเงิน
enum DonationTransactionStatus {
  /// รอการชำระ / รอ Webhook ยืนยัน
  pending,
  /// ชำระสำเร็จ — `donation_requests.current_amount` ถูกอัปเดตแล้ว
  confirmed,
  /// ชำระล้มเหลว / ยกเลิก
  failed;

  static DonationTransactionStatus fromString(String? value) {
    switch (value) {
      case 'confirmed':
        return DonationTransactionStatus.confirmed;
      case 'failed':
        return DonationTransactionStatus.failed;
      default:
        return DonationTransactionStatus.pending;
    }
  }
}

/// บันทึก Transaction การชำระเงินบริจาคแต่ละครั้ง
/// สร้างขึ้นเมื่อผู้ใช้กดบริจาค และอัปเดตเมื่อชำระสำเร็จ/ล้มเหลว
class DonationTransaction {
  final String id;
  final String requestId;
  final String donorUserId;
  final double amount;
  final PaymentMethod paymentMethod;

  /// Reference จาก Payment Gateway (null ขณะ pending ใน mock mode)
  final String? paymentReference;
  final DonationTransactionStatus status;
  final DateTime? confirmedAt;
  final DateTime createdAt;

  const DonationTransaction({
    required this.id,
    required this.requestId,
    required this.donorUserId,
    required this.amount,
    required this.paymentMethod,
    this.paymentReference,
    required this.status,
    this.confirmedAt,
    required this.createdAt,
  });

  factory DonationTransaction.fromJson(Map<String, dynamic> json) {
    double parseDouble(dynamic v) {
      if (v == null) return 0.0;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString()) ?? 0.0;
    }

    return DonationTransaction(
      id: json['id'] as String,
      requestId: json['request_id'] as String,
      donorUserId: json['donor_user_id'] as String,
      amount: parseDouble(json['amount']),
      paymentMethod: PaymentMethod.fromString(json['payment_method']?.toString()),
      paymentReference: json['payment_reference']?.toString(),
      status: DonationTransactionStatus.fromString(json['status']?.toString()),
      confirmedAt: json['confirmed_at'] != null
          ? DateTime.parse(json['confirmed_at'] as String)
          : null,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'request_id': requestId,
      'donor_user_id': donorUserId,
      'amount': amount,
      'payment_method': paymentMethod.dbValue,
      'payment_reference': paymentReference,
      'status': status.name,
      'confirmed_at': confirmedAt?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
    };
  }

  bool get isPending => status == DonationTransactionStatus.pending;
  bool get isConfirmed => status == DonationTransactionStatus.confirmed;
  bool get isFailed => status == DonationTransactionStatus.failed;
}
