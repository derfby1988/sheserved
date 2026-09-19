import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:sheserved/features/community/find_buddies/data/fitness_buddies_repository.dart';
import 'package:sheserved/features/community/find_buddies/presentation/widgets/cost_editors.dart';

const thaiMonths = [
  'ม.ค.',
  'ก.พ.',
  'มี.ค.',
  'เม.ย.',
  'พ.ค.',
  'มิ.ย.',
  'ก.ค.',
  'ส.ค.',
  'ก.ย.',
  'ต.ค.',
  'พ.ย.',
  'ธ.ค.',
];

String formatThaiTime(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}.${d.minute.toString().padLeft(2, '0')}';

String formatThaiBuddhistDateTime(DateTime d) {
  final beShort = ((d.year + 543) % 100).toString();
  return '${d.day} ${thaiMonths[d.month - 1]} $beShort ${formatThaiTime(d)} น.';
}

String formatThaiSessionRange(DateTime start, DateTime end) {
  final beShort = ((start.year + 543) % 100).toString();
  if (start.year == end.year &&
      start.month == end.month &&
      start.day == end.day) {
    return '${start.day} ${thaiMonths[start.month - 1]} $beShort ${formatThaiTime(start)}-${formatThaiTime(end)} น.';
  }
  return '${formatThaiBuddhistDateTime(start)} - ${formatThaiBuddhistDateTime(end)}';
}

/// Maps booking errors to user-friendly Thai messages.
String mapBookingError(Object e) {
  final raw = e.toString();
  if (raw.contains('POSITION_REQUIRED')) {
    return 'ก๊วนนี้กำหนดตำแหน่งผู้เล่น กรุณาเลือกตำแหน่งก่อนจอง';
  }
  if (raw.contains('POSITION_FULL')) {
    return 'ตำแหน่งที่คุณเลือกเต็มแล้ว กรุณาเลือกตำแหน่งอื่น';
  }
  if (raw.contains('POSITION_INVALID')) {
    return 'ตำแหน่งที่เลือกไม่ถูกต้องหรือถูกปิดแล้ว';
  }
  if (raw.contains('GROUP_FULL') || raw.contains('SESSION_FULL')) {
    return 'รอบนัดนี้เต็มแล้ว กรุณาเลือกรอบนัดอื่น';
  }
  if (raw.contains('OVERLAP_BOOKING')) {
    return 'คุณมีรอบนัดซ้อนทับในช่วงเวลานี้ กรุณาเลือกเวลาอื่น';
  }
  if (raw.contains('ALREADY_JOINED')) {
    return 'คุณเข้าร่วมรอบนัดนี้แล้ว';
  }
  if (raw.contains('ALREADY_REQUESTED')) {
    return 'คุณส่งคำขอเข้าร่วมรอบนัดนี้แล้ว กรุณารอการอนุมัติ';
  }
  if (raw.contains('SESSION_ENDED')) {
    return 'รอบนัดนี้สิ้นสุดแล้ว กรุณาเลือกรอบนัดอื่น';
  }
  if (raw.contains('SESSION_ALREADY_STARTED')) {
    return 'รอบนัดนี้เริ่มไปแล้ว เกินเวลาที่เปิดให้เข้าร่วม';
  }
  if (raw.contains('BOOKING_PREVIOUSLY_REJECTED')) {
    return 'คำขอเข้าร่วมรอบนี้ของคุณเคยถูกปฏิเสธแล้ว';
  }
  if (raw.contains('SESSION_NOT_FOUND')) {
    return 'ไม่พบรอบนัดนี้ กรุณารีเฟรชและลองใหม่';
  }
  if (raw.contains('BOOKING_NOT_FOUND')) {
    return 'ไม่พบรอบจองนี้';
  }
  if (raw.contains('BOOKING_RESPONSE_INVALID')) {
    return 'ระบบจองตอบกลับไม่ถูกต้อง กรุณาลองใหม่อีกครั้ง';
  }
  if (raw.contains('PGRST202')) {
    return 'ระบบเข้าร่วมก๊วนยังไม่พร้อมใช้งาน กรุณาลองใหม่ภายหลัง';
  }
  if (raw.contains('PGRST203')) {
    return 'ระบบจองกำลังอัปเดต กรุณาลองใหม่ภายหลัง';
  }
  if (raw.contains('NOT_GROUP_ADMIN')) {
    return 'คุณไม่มีสิทธิ์ดำเนินการรายการนี้';
  }
  if (raw.contains('UNAUTHORIZED')) {
    return 'กรุณาเข้าสู่ระบบใหม่แล้วลองอีกครั้ง';
  }
  if (raw.contains('USER_BLOCKED')) {
    return 'คุณถูกบล็อกจากก๊วนนี้ ไม่สามารถจองรอบได้';
  }
  return 'จองไม่สำเร็จ กรุณาลองใหม่อีกครั้ง';
}

/// Returns a non-sensitive code for booking diagnostics.
///
/// The returned value is safe to include in debug logs because it excludes
/// exception messages, request payloads, and user data.
String bookingErrorCode(Object error) {
  final raw = error.toString();
  const knownCodes = [
    'POSITION_REQUIRED',
    'POSITION_FULL',
    'POSITION_INVALID',
    'GROUP_FULL',
    'SESSION_FULL',
    'OVERLAP_BOOKING',
    'ALREADY_JOINED',
    'ALREADY_REQUESTED',
    'SESSION_ENDED',
    'SESSION_ALREADY_STARTED',
    'BOOKING_PREVIOUSLY_REJECTED',
    'SESSION_NOT_FOUND',
    'BOOKING_NOT_FOUND',
    'BOOKING_RESPONSE_INVALID',
    'NOT_GROUP_ADMIN',
    'UNAUTHORIZED',
    'USER_BLOCKED',
    'PGRST202',
    'PGRST203',
  ];
  for (final code in knownCodes) {
    if (raw.contains(code)) return code;
  }

  final codeMatch = RegExp(r'code:\s*([A-Za-z0-9_]+)').firstMatch(raw);
  final code = codeMatch?.group(1);
  if (code != null && code.toLowerCase() != 'null') {
    return code.toUpperCase();
  }
  return 'UNKNOWN';
}

String sessionCapacitySummary(
  Map<String, dynamic> session, {
  bool detailed = false,
  int? pendingCountOverride,
}) {
  final capacity = (session['capacity'] as num?)?.toInt() ?? 0;
  final confirmed = (session['confirmed_count'] as num?)?.toInt() ?? 0;
  final pending =
      pendingCountOverride ?? (session['pending_count'] as num?)?.toInt() ?? 0;
  final available =
      (session['available_count'] as num?)?.toInt() ??
      (capacity - confirmed).clamp(0, capacity);
  final pendingLabel = pending > 0 ? ' · รออนุมัติ $pending คน' : '';
  final confirmedLabel = detailed ? 'ผู้เข้าร่วม' : 'ยืนยันแล้ว';
  return '$confirmedLabel $confirmed / $capacity คน · เหลือ $available ที่$pendingLabel';
}

/// Phase 9.1: "฿200/รายเดือน · ฿500/ตลอดชีพ" style group-fee summary.
String groupFeeSummary(List<Map<String, dynamic>> fees) {
  return fees
      .map(
        (f) =>
            '${formatBaht(f['amount'] as num?)}/'
            '${billingPeriodLabel(f['billing_period']?.toString())}',
      )
      .join(' · ');
}

/// Phase 9.1: sessions with their public cost line items attached as
/// `cost_items` (reads the public view contract).
Future<List<Map<String, dynamic>>> loadSessionsWithCostItems(
  FitnessBuddiesRepository repo,
  String groupId,
) async {
  final sessions = await repo.listSessions(groupId);
  final ids = sessions
      .map((s) => s['id']?.toString() ?? '')
      .where((id) => id.isNotEmpty)
      .toList();
  if (ids.isEmpty) return sessions;
  try {
    final items = await repo.listPublicSessionCostItems(ids);
    final bySession = <String, List<Map<String, dynamic>>>{};
    for (final item in items) {
      final sid = item['session_id']?.toString() ?? '';
      if (sid.isEmpty) continue;
      bySession.putIfAbsent(sid, () => []).add(item);
    }
    for (final s in sessions) {
      s['cost_items'] =
          bySession[s['id']?.toString()] ?? <Map<String, dynamic>>[];
    }
  } catch (_) {
    for (final s in sessions) {
      s['cost_items'] = <Map<String, dynamic>>[];
    }
  }
  return sessions;
}

DateTime roundUpToNearest(DateTime dt, {int roundMinutes = 30}) {
  final roundedDown = DateTime(
    dt.year,
    dt.month,
    dt.day,
    dt.hour,
    dt.minute - (dt.minute % roundMinutes),
  );
  return roundedDown.add(Duration(minutes: roundMinutes));
}

DateTime dateTimeAt(DateTime date, TimeOfDay time) {
  return DateTime(date.year, date.month, date.day, time.hour, time.minute);
}

DateTime endDateTimeAt(DateTime date, TimeOfDay startTime, TimeOfDay endTime) {
  final start = dateTimeAt(date, startTime);
  var end = dateTimeAt(date, endTime);
  if (!end.isAfter(start)) end = end.add(const Duration(days: 1));
  return end;
}

TextStyle emojiTextStyle(BuildContext context, {double fontSize = 16}) {
  final platform = Theme.of(context).platform;
  final emojiFontFamily =
      platform == TargetPlatform.iOS || platform == TargetPlatform.macOS
      ? 'Apple Color Emoji'
      : platform == TargetPlatform.android
      ? 'Noto Color Emoji'
      : platform == TargetPlatform.windows
      ? 'Segoe UI Emoji'
      : null;
  return TextStyle(
    fontSize: fontSize,
    fontFamily: emojiFontFamily,
    fontFamilyFallback: const [
      'Apple Color Emoji',
      'Noto Color Emoji',
      'Segoe UI Emoji',
    ],
  );
}

/// ระยะทางระหว่างพิกัดสองจุด (กิโลเมตร)
double distanceKm(double lat1, double lng1, double lat2, double lng2) {
  return const Distance().as(
    LengthUnit.Kilometer,
    LatLng(lat1, lng1),
    LatLng(lat2, lng2),
  );
}

/// กรองก๊วนตามรัศมีจากตำแหน่งผู้ใช้
List<Map<String, dynamic>> applyLocationFilter(
  List<Map<String, dynamic>> groups, {
  required bool locationEnabled,
  double? userLat,
  double? userLng,
  double? radiusKm,
}) {
  if (!locationEnabled ||
      userLat == null ||
      userLng == null ||
      radiusKm == null) {
    return groups;
  }
  return groups.where((g) {
    final lat = g['lat'];
    final lng = g['lng'];
    if (lat == null || lng == null) return false;
    return distanceKm(
          userLat,
          userLng,
          (lat as num).toDouble(),
          (lng as num).toDouble(),
        ) <=
        radiusKm;
  }).toList();
}

/// ระยะทางจากผู้ใช้ถึงก๊วน (กม.) หรือ null เมื่อไม่มีพิกัด
double? groupDistanceKm(
  Map<String, dynamic> group, {
  double? userLat,
  double? userLng,
}) {
  if (userLat == null || userLng == null) return null;
  final lat = group['lat'];
  final lng = group['lng'];
  if (lat == null || lng == null) return null;
  return distanceKm(
    userLat,
    userLng,
    (lat as num).toDouble(),
    (lng as num).toDouble(),
  );
}

/// เรียงก๊วนตามระยะทางจากใกล้ไปไกลเมื่อเปิดตัวกรองรัศมี
void sortGroupsByDistance(
  List<Map<String, dynamic>> groups, {
  required bool locationEnabled,
  double? userLat,
  double? userLng,
}) {
  if (!locationEnabled || userLat == null || userLng == null) return;
  groups.sort((a, b) {
    final distanceA = groupDistanceKm(a, userLat: userLat, userLng: userLng);
    final distanceB = groupDistanceKm(b, userLat: userLat, userLng: userLng);
    if (distanceA == null && distanceB == null) return 0;
    if (distanceA == null) return 1;
    if (distanceB == null) return -1;
    return distanceA.compareTo(distanceB);
  });
}
