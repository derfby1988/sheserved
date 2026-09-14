import 'package:flutter/foundation.dart';

/// Representation of a skill level definition for sports activities.
@immutable
class SportSkillLevel {
  final String key;
  final String labelTh;
  final String labelEn;
  final String? description;

  const SportSkillLevel({
    required this.key,
    required this.labelTh,
    required this.labelEn,
    this.description,
  });

  factory SportSkillLevel.fromJson(Map<String, dynamic> json) {
    return SportSkillLevel(
      key: json['key']?.toString() ?? '',
      labelTh: json['label_th']?.toString() ?? json['label']?.toString() ?? '',
      labelEn: json['label_en']?.toString() ?? json['label_th']?.toString() ?? '',
      description: json['description']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'key': key,
      'label_th': labelTh,
      'label_en': labelEn,
      if (description != null) 'description': description,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SportSkillLevel && runtimeType == other.runtimeType && key == other.key;

  @override
  int get hashCode => key.hashCode;

  @override
  String toString() => 'SportSkillLevel($key: $labelTh)';
}

/// Fallback generic skill levels for sports without customized scales.
const List<SportSkillLevel> kGenericSkillLevels = [
  SportSkillLevel(
    key: 'all',
    labelTh: 'เปิดรับทุกระดับ',
    labelEn: 'All Levels',
    description: 'ไม่จำกัดระดับฝีมือ เล่นได้ทุกระดับเพื่อสุขภาพและความสนุก',
  ),
  SportSkillLevel(
    key: 'beginner',
    labelTh: 'มือใหม่ / เริ่มเล่น',
    labelEn: 'Beginner',
    description: 'เพิ่งเริ่มเล่น หรือกำลังฝึกฝนทักษะพื้นฐาน',
  ),
  SportSkillLevel(
    key: 'intermediate',
    labelTh: 'ปานกลาง / เล่นประจำ',
    labelEn: 'Intermediate',
    description: 'เล่นเป็นประจำ เข้าใจกติกาและควบคุมเกมได้ต่อเนื่อง',
  ),
  SportSkillLevel(
    key: 'advanced',
    labelTh: 'ระดับสูง / แข่งขัน',
    labelEn: 'Advanced / Competitive',
    description: 'ทักษะระดับสูง สปีดเกมเร็ว หรือเคยแข่งขัน',
  ),
];

/// Badminton Thai skill level scale (BG, P-, P, P+, C, B, A).
const List<SportSkillLevel> kBadmintonSkillLevels = [
  SportSkillLevel(
    key: 'all',
    labelTh: 'เปิดรับทุกระดับ',
    labelEn: 'All Levels',
    description: 'ไม่จำกัดระดับฝีมือ ตีสนุกร่วมกันได้ทุกมือ',
  ),
  SportSkillLevel(
    key: 'bg',
    labelTh: 'มือใหม่ (BG)',
    labelEn: 'Beginner (BG)',
    description: 'เพิ่งเริ่มหัดเล่น กำลังฝึกเสิร์ฟและโต้ลูกพื้นฐาน',
  ),
  SportSkillLevel(
    key: 'p_minus',
    labelTh: 'มือ P-',
    labelEn: 'P- (Pre-P)',
    description: 'เริ่มวิ่งคอร์ตได้บ้าง โต้ลูกพื้นฐานได้',
  ),
  SportSkillLevel(
    key: 'p',
    labelTh: 'มือ P',
    labelEn: 'P (Playable)',
    description: 'ตีเกมได้ วิ่งคอร์ตและจับจังหวะการเล่นคู่ได้',
  ),
  SportSkillLevel(
    key: 'p_plus',
    labelTh: 'มือ P+',
    labelEn: 'P+',
    description: 'เล่นเกมคล่อง มีลูกตบ ลูกตัด หยอดได้สม่ำเสมอ',
  ),
  SportSkillLevel(
    key: 'c',
    labelTh: 'มือ C',
    labelEn: 'C (Club Player)',
    description: 'เล่นประจำ แข็งแรง มีสปีดเกมและความแน่นอน',
  ),
  SportSkillLevel(
    key: 'b',
    labelTh: 'มือ B',
    labelEn: 'B (Competitive)',
    description: 'ระดับนักกีฬาแข่งขัน/มือเดินสาย ทักษะระดับสูง',
  ),
  SportSkillLevel(
    key: 'a',
    labelTh: 'มือ A',
    labelEn: 'A (Professional)',
    description: 'ระดับแชมป์ / อดีตนักกีฬาทีมชาติ / มือโปร',
  ),
];

/// Tennis & Pickleball skill level scale based on NTRP.
const List<SportSkillLevel> kTennisPickleballSkillLevels = [
  SportSkillLevel(
    key: 'all',
    labelTh: 'เปิดรับทุกระดับ',
    labelEn: 'All Levels',
    description: 'ไม่จำกัดระดับฝีมือ ตีสนุกร่วมกันได้',
  ),
  SportSkillLevel(
    key: 'ntrp_2',
    labelTh: 'NTRP 2.0 - 2.5',
    labelEn: 'NTRP 2.0 - 2.5',
    description: 'มือใหม่ กำลังฝึกตีโฟร์แฮนด์/แบ็กแฮนด์และแรลลี่สั้นๆ',
  ),
  SportSkillLevel(
    key: 'ntrp_3',
    labelTh: 'NTRP 3.0 - 3.5',
    labelEn: 'NTRP 3.0 - 3.5',
    description: 'ระดับปานกลาง ตีโต้ได้ต่อเนื่อง คุมทิศทางบอลได้ เล่นเกมแต้มสนุก',
  ),
  SportSkillLevel(
    key: 'ntrp_4',
    labelTh: 'NTRP 4.0 - 4.5',
    labelEn: 'NTRP 4.0 - 4.5',
    description: 'ระดับสูง มีพลัง เสิร์ฟแน่นอน เล่นหน้าเน็ตคล่อง จังหวะเกมเร็ว',
  ),
  SportSkillLevel(
    key: 'ntrp_5',
    labelTh: 'NTRP 5.0+',
    labelEn: 'NTRP 5.0+',
    description: 'ระดับแข่งขัน / อดีตนักกีฬา สภาพร่างกายและแท็กติกสูง',
  ),
];

/// Running Pace skill scale.
const List<SportSkillLevel> kRunningSkillLevels = [
  SportSkillLevel(
    key: 'all',
    labelTh: 'เปิดรับทุกระดับ',
    labelEn: 'All Levels',
    description: 'วิ่งเพซไหนก็ได้ วิ่งชิลๆ รอเพื่อน',
  ),
  SportSkillLevel(
    key: 'fun_run',
    labelTh: 'Fun Run / เดิน-วิ่ง',
    labelEn: 'Easy / Fun Run',
    description: 'วิ่งสลับเดิน เน้นเพื่อสุขภาพ พูดคุยได้สบาย (Pace 8-10+)',
  ),
  SportSkillLevel(
    key: 'pace_7_8',
    labelTh: 'Pace 7 - 8',
    labelEn: 'Pace 7 - 8',
    description: 'วิ่งสบายๆ ต่อเนื่อง ไม่เหนื่อยเกินไป',
  ),
  SportSkillLevel(
    key: 'pace_6',
    labelTh: 'Pace 6',
    labelEn: 'Pace 6 (Moderate)',
    description: 'วิ่งเร็วปานกลาง ฟิตซ้อมระยะมินิมาราธอน (10K)',
  ),
  SportSkillLevel(
    key: 'pace_5',
    labelTh: 'Pace 5',
    labelEn: 'Pace 5 (Tempo)',
    description: 'วิ่งเร็ว ต่อเนื่อง ความฟิตสูง',
  ),
  SportSkillLevel(
    key: 'sub_pace_4',
    labelTh: 'Pace 4 ลงไป (Sub-4)',
    labelEn: 'Sub-4 Pace (Fast)',
    description: 'วิ่งระดับแข่งขัน วิ่งเร็วมาก/อินเทอร์วัล',
  ),
];

/// Resolves the list of skill levels for a specific sport.
List<SportSkillLevel> resolveSkillLevelsForSport({
  Map<String, dynamic>? sportData,
  String? sportNameTh,
  String? sportNameEn,
}) {
  // 1. Check if sportData contains JSONB skill_levels
  final rawLevels = sportData?['skill_levels'];
  if (rawLevels != null) {
    if (rawLevels is Map && rawLevels['levels'] is List) {
      final list = (rawLevels['levels'] as List)
          .whereType<Map<String, dynamic>>()
          .map((m) => SportSkillLevel.fromJson(m))
          .toList();
      if (list.isNotEmpty) return list;
    } else if (rawLevels is List) {
      final list = rawLevels
          .whereType<Map<String, dynamic>>()
          .map((m) => SportSkillLevel.fromJson(m))
          .toList();
      if (list.isNotEmpty) return list;
    }
  }

  // 2. Check by sport name
  final th = (sportNameTh ?? sportData?['name_th']?.toString() ?? '').toLowerCase();
  final en = (sportNameEn ?? sportData?['name_en']?.toString() ?? '').toLowerCase();

  if (th.contains('แบดมินตัน') || en.contains('badminton')) {
    return kBadmintonSkillLevels;
  }
  if (th.contains('เทนนิส') || th.contains('พิกเคิล') || en.contains('tennis') || en.contains('pickleball')) {
    return kTennisPickleballSkillLevels;
  }
  if (th.contains('วิ่ง') || en.contains('running')) {
    return kRunningSkillLevels;
  }

  // 3. Fallback to generic levels
  return kGenericSkillLevels;
}

/// Formats a list of target skill keys into a friendly Thai label.
String formatSkillLevelSummary(List<String>? targetLevels, List<SportSkillLevel> availableLevels) {
  if (targetLevels == null || targetLevels.isEmpty || targetLevels.contains('all')) {
    return 'ทุกระดับ';
  }

  final labels = <String>[];
  for (final key in targetLevels) {
    final match = availableLevels.firstWhere(
      (lvl) => lvl.key == key,
      orElse: () => SportSkillLevel(key: key, labelTh: key, labelEn: key),
    );
    labels.add(match.labelTh);
  }

  if (labels.length == 1) {
    return labels.first;
  }
  if (labels.length == 2) {
    return '${labels.first} - ${labels.last}';
  }
  return '${labels.first} ถึง ${labels.last}';
}
