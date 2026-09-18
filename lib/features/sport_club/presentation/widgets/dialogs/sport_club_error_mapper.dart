/// Maps raw database/RPC error strings to user-friendly Thai messages.
String mapManagementError(Object e) {
  final raw = e.toString();
  if (raw.contains('POSITION_REQUIRED')) {
    return 'ต้องระบุตำแหน่งของผู้ดูแลก๊วนสำหรับรอบนัดนี้';
  }
  if (raw.contains('POSITION_FULL')) {
    return 'ตำแหน่งที่เลือกเต็มแล้ว กรุณาเลือกตำแหน่งอื่น';
  }
  if (raw.contains('POSITION_INVALID')) {
    return 'ตำแหน่งที่เลือกไม่ถูกต้องหรือถูกปิดแล้ว';
  }
  if (raw.contains('SESSION_CAPACITY_BELOW_CONFIRMED')) {
    return 'จำนวนคนสูงสุดต้องไม่น้อยกว่าจำนวนผู้ยืนยันแล้วในรอบนี้';
  }
  if (raw.contains('OWNER_AUTO_JOIN_CAPACITY')) {
    return 'ไม่สามารถเปิดเข้าร่วมทุกรอบได้ เพราะมีรอบที่เต็มแล้ว';
  }
  if (raw.contains('OWNER_AUTO_JOIN_OVERLAP')) {
    return 'ไม่สามารถเปิดเข้าร่วมทุกรอบได้ เพราะมีรอบเวลาทับซ้อนกัน';
  }
  if (raw.contains('OWNER_ONLY')) {
    return 'เฉพาะเจ้าของก๊วนเท่านั้นที่เปลี่ยนการเข้าร่วมอัตโนมัติได้';
  }
  if (raw.contains('SESSION_FULL')) {
    return 'รอบนัดนี้เต็มแล้ว';
  }
  if (raw.contains('BOOKING_NOT_CONFIRMED')) {
    return 'ผู้ใช้นี้ไม่ได้ยืนยันเข้าร่วมรอบนี้แล้ว';
  }
  if (raw.contains('CANNOT_REDUCE_LAYOUT_ACTIVE_BOOKINGS')) {
    return 'ไม่สามารถลดขนาดสนามได้ เนื่องจากมีรอบนัดที่มีการจองตำแหน่งที่ถูกตัดออก';
  }
  if (raw.contains('OWNER_USE_PARTICIPATION_TOGGLE')) {
    return 'เจ้าของก๊วนต้องใช้เมนูการเข้าร่วมของเจ้าของก๊วน';
  }
  if (raw.contains('NOT_GROUP_ADMIN')) {
    return 'คุณไม่มีสิทธิ์จัดการก๊วนนี้';
  }
  if (raw.contains('UNAUTHORIZED')) {
    return 'กรุณาเข้าสู่ระบบใหม่แล้วลองอีกครั้ง';
  }
  return 'ดำเนินการไม่สำเร็จ กรุณาลองใหม่อีกครั้ง';
}

/// Maps booking approval error strings to user-friendly Thai messages.
String mapApprovalError(Object e) {
  final raw = e.toString();
  if (raw.contains('POSITION_FULL')) {
    return 'ตำแหน่งที่ผู้สมัครเลือกเต็มแล้ว ไม่สามารถอนุมัติได้\n'
        '(ระบบคงคำขอไว้เป็น "รออนุมัติ" และแจ้งผู้สมัครให้เลือกตำแหน่งใหม่แล้ว)';
  }
  if (raw.contains('SESSION_FULL')) {
    return 'รอบนัดนี้เต็มแล้ว ไม่สามารถอนุมัติผู้ขอรายนี้ได้\n'
        'กรุณาปฏิเสธคำขอ หรือเพิ่ม capacity ของรอบนัดก่อน';
  }
  return 'อนุมัติไม่สำเร็จ: ${mapManagementError(e)}';
}
