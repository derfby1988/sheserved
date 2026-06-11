/// Model สำหรับ emr_records (HIS Core)
class EmrRecord {
  final String id;
  final String professionId;
  final String patientId;
  final String recordNumber;
  final String recordType;
  final String? chiefComplaint;
  final String? historyOfPresentIllness;
  final String? physicalExam;
  final String? assessment;
  final String? plan;
  final String? icd10Code;
  final String? icd10Name;
  final List<dynamic> attachments;
  final String? createdBy;
  final DateTime createdAt;
  final DateTime updatedAt;

  const EmrRecord({
    required this.id,
    required this.professionId,
    required this.patientId,
    required this.recordNumber,
    this.recordType = 'general',
    this.chiefComplaint,
    this.historyOfPresentIllness,
    this.physicalExam,
    this.assessment,
    this.plan,
    this.icd10Code,
    this.icd10Name,
    this.attachments = const [],
    this.createdBy,
    required this.createdAt,
    required this.updatedAt,
  });

  factory EmrRecord.fromJson(Map<String, dynamic> json) {
    return EmrRecord(
      id: json['id'] as String,
      professionId: json['profession_id'] as String,
      patientId: json['patient_id'] as String,
      recordNumber: json['record_number'] as String,
      recordType: json['record_type'] as String? ?? 'general',
      chiefComplaint: json['chief_complaint'] as String?,
      historyOfPresentIllness: json['history_of_present_illness'] as String?,
      physicalExam: json['physical_exam'] as String?,
      assessment: json['assessment'] as String?,
      plan: json['plan'] as String?,
      icd10Code: json['icd10_code'] as String?,
      icd10Name: json['icd10_name'] as String?,
      attachments: json['attachments'] as List<dynamic>? ?? [],
      createdBy: json['created_by'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'profession_id': professionId,
      'patient_id': patientId,
      'record_number': recordNumber,
      'record_type': recordType,
      'chief_complaint': chiefComplaint,
      'history_of_present_illness': historyOfPresentIllness,
      'physical_exam': physicalExam,
      'assessment': assessment,
      'plan': plan,
      'icd10_code': icd10Code,
      'icd10_name': icd10Name,
      'attachments': attachments,
    };
  }
}
