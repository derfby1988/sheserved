/// Model สำหรับ shifts (ตารางเวร/กะงาน)
class Shift {
  final String id;
  final String professionId;
  final String employeeId;
  final DateTime shiftDate;
  final DateTime startTime;
  final DateTime? endTime;
  final String shiftType; // regular, overtime, holiday, on_call
  final String status; // scheduled, checked_in, checked_out, absent, approved
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Shift({
    required this.id,
    required this.professionId,
    required this.employeeId,
    required this.shiftDate,
    required this.startTime,
    this.endTime,
    this.shiftType = 'regular',
    this.status = 'scheduled',
    this.notes,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Shift.fromJson(Map<String, dynamic> json) {
    return Shift(
      id: json['id'] as String,
      professionId: json['profession_id'] as String,
      employeeId: json['employee_id'] as String,
      shiftDate: DateTime.parse(json['shift_date'] as String),
      startTime: DateTime.parse(json['start_time'] as String),
      endTime: json['end_time'] != null
          ? DateTime.parse(json['end_time'] as String)
          : null,
      shiftType: json['shift_type'] as String? ?? 'regular',
      status: json['status'] as String? ?? 'scheduled',
      notes: json['notes'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'profession_id': professionId,
      'employee_id': employeeId,
      'shift_date': shiftDate.toIso8601String(),
      'start_time': startTime.toIso8601String(),
      'end_time': endTime?.toIso8601String(),
      'shift_type': shiftType,
      'status': status,
      'notes': notes,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  String get shiftTypeLabel {
    switch (shiftType) {
      case 'regular': return 'ปกติ';
      case 'overtime': return 'ล่วงเวลา';
      case 'holiday': return 'วันหยุด';
      case 'on_call': return 'เวร';
      default: return shiftType;
    }
  }

  String get statusLabel {
    switch (status) {
      case 'scheduled': return 'กำหนดแล้ว';
      case 'checked_in': return 'เข้างาน';
      case 'checked_out': return 'ออกงาน';
      case 'absent': return 'ขาด';
      case 'approved': return 'อนุมัติ';
      default: return status;
    }
  }

  /// คำนวณชั่วโมงทำงาน (ถ้ามี end_time)
  double? get hoursWorked {
    if (endTime == null) return null;
    return endTime!.difference(startTime).inMinutes / 60.0;
  }
}
