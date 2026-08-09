import 'dart:convert';

enum TriageLevel {
  deceased,
  critical,
  urgent,
  nonUrgent,
  white,
}

extension TriageLevelX on TriageLevel {
  String get label {
    switch (this) {
      case TriageLevel.deceased:
        return 'deceased';
      case TriageLevel.critical:
        return 'critical';
      case TriageLevel.urgent:
        return 'urgent';
      case TriageLevel.nonUrgent:
        return 'non_urgent';
      case TriageLevel.white:
        return 'white';
    }
  }

  String get displayName {
    switch (this) {
      case TriageLevel.deceased:
        return 'เคสดำ';
      case TriageLevel.critical:
        return 'ผู้ป่วยวิกฤต';
      case TriageLevel.urgent:
        return 'ผู้ป่วยรีบด่วน';
      case TriageLevel.nonUrgent:
        return 'ผู้ป่วยไม่รีบด่วน';
      case TriageLevel.white:
        return 'ผู้ป่วยทั่วไป';
    }
  }

  int get sortOrder {
    switch (this) {
      case TriageLevel.deceased:
        return 1;
      case TriageLevel.critical:
        return 2;
      case TriageLevel.urgent:
        return 3;
      case TriageLevel.nonUrgent:
        return 4;
      case TriageLevel.white:
        return 5;
    }
  }

  int get colorValue {
    switch (this) {
      case TriageLevel.deceased:
        return 0xFF000000;
      case TriageLevel.critical:
        return 0xFFFF0000;
      case TriageLevel.urgent:
        return 0xFFFFD600;
      case TriageLevel.nonUrgent:
        return 0xFF00C853;
      case TriageLevel.white:
        return 0xFFFFFFFF;
    }
  }

  String get emoji {
    switch (this) {
      case TriageLevel.deceased:
        return '⚫';
      case TriageLevel.critical:
        return '🔴';
      case TriageLevel.urgent:
        return '🟡';
      case TriageLevel.nonUrgent:
        return '🟢';
      case TriageLevel.white:
        return '⚪';
    }
  }

  static TriageLevel fromString(String? value) {
    switch (value) {
      case 'deceased':
        return TriageLevel.deceased;
      case 'critical':
        return TriageLevel.critical;
      case 'urgent':
        return TriageLevel.urgent;
      case 'non_urgent':
        return TriageLevel.nonUrgent;
      default:
        return TriageLevel.white;
    }
  }
}

enum VictimVerifyStatus { unverified, confirmed, disputed }

extension VictimVerifyStatusX on VictimVerifyStatus {
  String get label {
    switch (this) {
      case VictimVerifyStatus.unverified:
        return 'unverified';
      case VictimVerifyStatus.confirmed:
        return 'confirmed';
      case VictimVerifyStatus.disputed:
        return 'disputed';
    }
  }

  static VictimVerifyStatus fromString(String? value) {
    switch (value) {
      case 'confirmed':
        return VictimVerifyStatus.confirmed;
      case 'disputed':
        return VictimVerifyStatus.disputed;
      default:
        return VictimVerifyStatus.unverified;
    }
  }
}

class IncidentVictim {
  final String id;
  final String? prefix;
  final String? firstName;
  final String? lastName;
  final String displayName;
  final bool isMasked;
  final TriageLevel triageLevel;
  final DateTime? triagedAt;
  final String? triagedByName;
  final String? triageNote;
  final VictimVerifyStatus verifyStatus;
  final bool canEdit;
  final bool hasHealthData;
  final String? healthDataSessionId;
  final String? disputedReason;
  final DateTime? disputedAt;
  final String? reportedByName;
  final DateTime createdAt;

  IncidentVictim({
    required this.id,
    this.prefix,
    this.firstName,
    this.lastName,
    required this.displayName,
    required this.isMasked,
    required this.triageLevel,
    this.triagedAt,
    this.triagedByName,
    this.triageNote,
    required this.verifyStatus,
    required this.canEdit,
    required this.hasHealthData,
    this.healthDataSessionId,
    this.disputedReason,
    this.disputedAt,
    this.reportedByName,
    required this.createdAt,
  });

  factory IncidentVictim.fromJson(Map<String, dynamic> json) {
    return IncidentVictim(
      id: json['id'] as String,
      prefix: json['prefix'] as String?,
      firstName: json['firstName'] as String?,
      lastName: json['lastName'] as String?,
      displayName: json['displayName'] as String? ?? '',
      isMasked: json['isMasked'] as bool? ?? false,
      triageLevel: TriageLevelX.fromString(json['triageLevel'] as String?),
      triagedAt: json['triagedAt'] != null
          ? DateTime.parse(json['triagedAt'] as String)
          : null,
      triagedByName: json['triagedByName'] as String?,
      triageNote: json['triageNote'] as String?,
      verifyStatus: VictimVerifyStatusX.fromString(json['verifyStatus'] as String?),
      canEdit: json['canEdit'] as bool? ?? false,
      hasHealthData: json['hasHealthData'] as bool? ?? false,
      healthDataSessionId: json['healthDataSessionId'] as String?,
      disputedReason: json['disputedReason'] as String?,
      disputedAt: json['disputedAt'] != null
          ? DateTime.parse(json['disputedAt'] as String)
          : null,
      reportedByName: json['reportedByName'] as String?,
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'prefix': prefix,
        'firstName': firstName,
        'lastName': lastName,
        'displayName': displayName,
        'isMasked': isMasked,
        'triageLevel': triageLevel.label,
        'triagedAt': triagedAt?.toIso8601String(),
        'triagedByName': triagedByName,
        'triageNote': triageNote,
        'verifyStatus': verifyStatus.label,
        'canEdit': canEdit,
        'hasHealthData': hasHealthData,
        'healthDataSessionId': healthDataSessionId,
        'disputedReason': disputedReason,
        'disputedAt': disputedAt?.toIso8601String(),
        'reportedByName': reportedByName,
        'createdAt': createdAt.toIso8601String(),
      };
}

class TriageSummary {
  final int deceased;
  final int critical;
  final int urgent;
  final int nonUrgent;
  final int white;
  final int total;

  TriageSummary({
    this.deceased = 0,
    this.critical = 0,
    this.urgent = 0,
    this.nonUrgent = 0,
    this.white = 0,
    this.total = 0,
  });

  factory TriageSummary.fromJson(Map<String, dynamic> json) {
    return TriageSummary(
      deceased: json['deceased'] as int? ?? 0,
      critical: json['critical'] as int? ?? 0,
      urgent: json['urgent'] as int? ?? 0,
      nonUrgent: json['non_urgent'] as int? ?? 0,
      white: json['white'] as int? ?? 0,
      total: json['total'] as int? ?? 0,
    );
  }

  String get badgeText {
    final parts = <String>[];
    if (deceased > 0) parts.add('⚫$deceased');
    if (critical > 0) parts.add('🔴$critical');
    if (urgent > 0) parts.add('🟡$urgent');
    if (nonUrgent > 0) parts.add('🟢$nonUrgent');
    if (white > 0) parts.add('⚪$white');
    return parts.join(' ');
  }
}

class VictimListResponse {
  final bool success;
  final TriageSummary summary;
  final ViewerPermissions viewerPermissions;
  final List<IncidentVictim> victims;

  VictimListResponse({
    required this.success,
    required this.summary,
    required this.viewerPermissions,
    required this.victims,
  });

  factory VictimListResponse.fromJson(Map<String, dynamic> json) {
    return VictimListResponse(
      success: json['success'] as bool? ?? true,
      summary: TriageSummary.fromJson(json['summary'] as Map<String, dynamic>? ?? {}),
      viewerPermissions: ViewerPermissions.fromJson(
          json['viewerPermissions'] as Map<String, dynamic>? ?? {}),
      victims: (json['victims'] as List<dynamic>? ?? [])
          .map((v) => IncidentVictim.fromJson(v as Map<String, dynamic>))
          .toList(),
    );
  }
}

class ViewerPermissions {
  final bool canTriage;
  final bool canDelete;
  final bool canViewFull;
  final bool canDispute;
  final bool canTriageBlack;

  ViewerPermissions({
    this.canTriage = false,
    this.canDelete = false,
    this.canViewFull = false,
    this.canDispute = false,
    this.canTriageBlack = false,
  });

  factory ViewerPermissions.fromJson(Map<String, dynamic> json) {
    return ViewerPermissions(
      canTriage: json['canTriage'] as bool? ?? false,
      canDelete: json['canDelete'] as bool? ?? false,
      canViewFull: json['canViewFull'] as bool? ?? false,
      canDispute: json['canDispute'] as bool? ?? false,
      canTriageBlack: json['canTriageBlack'] as bool? ?? false,
    );
  }
}

class TriageHistoryEntry {
  final String id;
  final String victimId;
  final String incidentId;
  final TriageLevel fromLevel;
  final TriageLevel toLevel;
  final String changedBy;
  final String? changedByName;
  final String? changedByProfessionCategory;
  final String? note;
  final DateTime createdAt;

  TriageHistoryEntry({
    required this.id,
    required this.victimId,
    required this.incidentId,
    required this.fromLevel,
    required this.toLevel,
    required this.changedBy,
    this.changedByName,
    this.changedByProfessionCategory,
    this.note,
    required this.createdAt,
  });

  factory TriageHistoryEntry.fromJson(Map<String, dynamic> json) {
    return TriageHistoryEntry(
      id: json['id'] as String,
      victimId: json['victim_id'] as String,
      incidentId: json['incident_id'] as String,
      fromLevel: TriageLevelX.fromString(json['from_level'] as String?),
      toLevel: TriageLevelX.fromString(json['to_level'] as String),
      changedBy: json['changed_by'] as String,
      changedByName: json['changed_by_name'] as String?,
      changedByProfessionCategory: json['changed_by_profession_category'] as String?,
      note: json['note'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}
