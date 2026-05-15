class ConsultationEntry {
  final String id;
  final String patientName;
  final String? patientAvatar;
  final String packageName;
  final String? packageId;
  final double price;
  final String bodyArea;
  final String status;
  final DateTime requestedAt;
  final String roomId;
  final String? providerId; // ผู้ให้บริการที่รับงานแล้ว

  ConsultationEntry({
    required this.id,
    required this.patientName,
    this.patientAvatar,
    required this.packageName,
    this.packageId,
    required this.price,
    required this.bodyArea,
    required this.status,
    required this.requestedAt,
    required this.roomId,
    this.providerId,
  });

  factory ConsultationEntry.fromMap(Map<String, dynamic> map) {
    final user = map['users'] as Map<String, dynamic>? ?? {};
    final firstName = user['first_name'] as String? ?? '';
    final lastName = user['last_name'] as String? ?? '';
    final patientName = '$firstName $lastName'.trim().isEmpty
        ? 'ผู้ป่วยไม่ระบุชื่อ'
        : '$firstName $lastName'.trim();

    final bodyAreaMap = map['body_area'] as Map<String, dynamic>? ?? {};
    String bodyArea =
        bodyAreaMap['area'] as String? ??
        bodyAreaMap['label'] as String? ??
        (bodyAreaMap.keys.isNotEmpty ? bodyAreaMap.keys.join(', ') : 'ไม่ระบุ');

    final consultationId = map['id'] as String? ?? 'unknown';
    // ✅ roomId ต้องสร้างจาก consultation_id เสมอ เพื่อให้เป็นแบบ 1:1
    // และเมื่อทำ migration SQL เสร็จ จะเริ่มใช้ map['room_id'] แทนบรรทัดนี้ได้
    final roomId = map['room_id'] as String? ?? 'consult_$consultationId';

    double parseDouble(dynamic value) {
      if (value == null) return 0.0;
      if (value is num) return value.toDouble();
      if (value is String) return double.tryParse(value) ?? 0.0;
      return 0.0;
    }

    return ConsultationEntry(
      id: map['id'] as String? ?? '',
      patientName: patientName,
      patientAvatar: user['profile_image_url'] as String?,
      packageName: map['package_name'] as String? ?? 'ไม่ระบุแพ็คเกจ',
      packageId: map['package_id'] as String?,
      price: parseDouble(map['price']),
      bodyArea: bodyArea,
      status: map['status'] as String? ?? 'pending',
      requestedAt:
          DateTime.tryParse(map['created_at']?.toString() ?? '') ??
          DateTime.now(),
      roomId: roomId,
      providerId: map['provider_id'] as String?,
    );
  }

  bool get isAssigned => providerId != null && providerId!.isNotEmpty;
}

