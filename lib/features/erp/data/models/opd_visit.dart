import 'package:flutter/material.dart';

/// Model สำหรับ opd_visits (HIS Core)
class OpdVisit {
  final String id;
  final String professionId;
  final String patientId;
  final String? emrRecordId;
  final String? doctorId;
  final String visitNumber;
  final DateTime visitDate;
  final String? chiefComplaint;
  final String? diagnosis;
  final String? treatment;
  final DateTime? followUpDate;
  final String status; // checked_in, in_consultation, completed, cancelled, no_show
  final int? queueNumber;
  final bool isWalkIn;
  final DateTime createdAt;
  final DateTime updatedAt;

  const OpdVisit({
    required this.id,
    required this.professionId,
    required this.patientId,
    this.emrRecordId,
    this.doctorId,
    required this.visitNumber,
    required this.visitDate,
    this.chiefComplaint,
    this.diagnosis,
    this.treatment,
    this.followUpDate,
    this.status = 'checked_in',
    this.queueNumber,
    this.isWalkIn = true,
    required this.createdAt,
    required this.updatedAt,
  });

  factory OpdVisit.fromJson(Map<String, dynamic> json) {
    return OpdVisit(
      id: json['id'] as String,
      professionId: json['profession_id'] as String,
      patientId: json['patient_id'] as String,
      emrRecordId: json['emr_record_id'] as String?,
      doctorId: json['doctor_id'] as String?,
      visitNumber: json['visit_number'] as String,
      visitDate: DateTime.parse(json['visit_date'] as String),
      chiefComplaint: json['chief_complaint'] as String?,
      diagnosis: json['diagnosis'] as String?,
      treatment: json['treatment'] as String?,
      followUpDate: json['follow_up_date'] != null ? DateTime.parse(json['follow_up_date'] as String) : null,
      status: json['status'] as String? ?? 'checked_in',
      queueNumber: json['queue_number'] as int?,
      isWalkIn: json['is_walk_in'] as bool? ?? true,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'profession_id': professionId,
      'patient_id': patientId,
      'doctor_id': doctorId,
      'visit_number': visitNumber,
      'chief_complaint': chiefComplaint,
      'diagnosis': diagnosis,
      'treatment': treatment,
      'follow_up_date': followUpDate?.toIso8601String(),
      'status': status,
      'is_walk_in': isWalkIn,
    };
  }

  String get statusLabel {
    switch (status) {
      case 'checked_in': return 'รอตรวจ';
      case 'in_consultation': return 'กำลังตรวจ';
      case 'completed': return 'เสร็จสิ้น';
      case 'cancelled': return 'ยกเลิก';
      case 'no_show': return 'ไม่มา';
      default: return status;
    }
  }

  Color get statusColor {
    switch (status) {
      case 'checked_in': return Colors.orange;
      case 'in_consultation': return Colors.blue;
      case 'completed': return Colors.green;
      case 'cancelled': return Colors.grey;
      case 'no_show': return Colors.red;
      default: return Colors.grey;
    }
  }
}
