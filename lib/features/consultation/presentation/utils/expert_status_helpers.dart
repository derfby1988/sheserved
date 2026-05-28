import 'package:flutter/material.dart';
import '../../../../features/admin/models/profession.dart';

/// Find profession by name or role for accurate icon/color from admin settings
Profession? findProfessionByNameOrRole(
  List<Profession> professions,
  String? name,
  String? role,
) {
  if (professions.isEmpty) return null;
  final searchTerms = <String>{
    (name ?? '').toLowerCase().trim(),
    (role ?? '').toLowerCase().trim(),
  };
  searchTerms.remove('');
  if (searchTerms.isEmpty) return null;

  // Map legacy roles/names to proper Thai names to match the new DB
  final legacyMap = <String, String>{
    'doctor': 'แพทย์ทั่วไป',
    'หมอ': 'แพทย์ทั่วไป',
    'specialist': 'แพทย์เฉพาะทาง',
    'professor': 'อาจารย์แพทย์',
    'pharmacist': 'เภสัชกร',
    'เภสัช': 'เภสัชกร',
    'nurse': 'พยาบาล',
  };

  final mappedTerms = <String>{};
  for (final term in searchTerms) {
    mappedTerms.add(term);
    if (legacyMap.containsKey(term)) {
      mappedTerms.add(legacyMap[term]!);
    }
  }

  for (final prof in professions) {
    final profId = prof.id.toLowerCase().trim();
    final profName = prof.name.toLowerCase().trim();
    final profNameEn = (prof.nameEn ?? '').toLowerCase().trim();
    if (mappedTerms.any((term) =>
        profId == term ||
        profName.contains(term) ||
        term.contains(profName) ||
        (profNameEn.isNotEmpty && (profNameEn.contains(term) || term.contains(profNameEn))))) {
      return prof;
    }
  }
  return null;
}

IconData? parseExpertGroupIcon(dynamic raw) {
  if (raw == null) return null;
  if (raw is int) {
    return IconData(raw, fontFamily: 'MaterialIcons');
  }
  if (raw is String) {
    if (raw.contains('http')) return null; // image url, not an icon
    const iconMap = <String, IconData>{
      'medical_services': Icons.medical_services,
      'psychology': Icons.psychology,
      'local_hospital': Icons.local_hospital,
      'healing': Icons.healing,
      'favorite': Icons.favorite,
      'health_and_safety': Icons.health_and_safety,
      'spa': Icons.spa,
      'vaccines': Icons.vaccines,
      'personal_injury': Icons.personal_injury,
      'sports': Icons.sports,
      'child_care': Icons.child_care,
      'elderly': Icons.elderly,
      'pregnant_woman': Icons.pregnant_woman,
      'restaurant': Icons.restaurant,
      'science': Icons.science,
      'biotech': Icons.biotech,
      'fitness_center': Icons.fitness_center,
      'sanitizer': Icons.sanitizer,
      'masks': Icons.masks,
      'coronavirus': Icons.coronavirus,
      'medication': Icons.medication,
      'medication_liquid': Icons.medication_liquid,
      'monitor_heart': Icons.monitor_heart,
      'emergency': Icons.emergency,
      'psychology_alt': Icons.psychology_alt,
      'sentiment_satisfied': Icons.sentiment_satisfied,
      'sentiment_dissatisfied': Icons.sentiment_dissatisfied,
      'groups': Icons.groups,
      'person': Icons.person,
      'person_outline': Icons.person_outline,
      'face': Icons.face,
      'account_circle': Icons.account_circle,
    };
    return iconMap[raw.toString().trim().toLowerCase()] ?? Icons.person_outline;
  }
  return null;
}

/// Convert hex color string (e.g. '#FF0000' or 'FF0000') to Flutter Color
Color? hexToColor(String? hex) {
  if (hex == null || hex.isEmpty) return null;
  try {
    final clean = hex.replaceAll('#', '');
    if (clean.length == 6) {
      return Color(int.parse('FF$clean', radix: 16));
    } else if (clean.length == 8) {
      return Color(int.parse(clean, radix: 16));
    }
  } catch (_) {}
  return null;
}

/// Map expert role to default Material icon (fallback when package doesn't specify icon)
IconData? getDefaultIconForRole(String? role) {
  final normalized = role?.toLowerCase().trim() ?? '';
  const roleIconMap = <String, IconData>{
    'doctor': Icons.medical_services,
    'physician': Icons.medical_services,
    'แพทย์': Icons.medical_services,
    'หมอ': Icons.medical_services,
    'อาจารย์แพทย์': Icons.medical_services,
    'pharmacist': Icons.medication,
    'pharmacy': Icons.local_pharmacy,
    'เภสัชกร': Icons.medication,
    'nurse': Icons.local_hospital,
    'พยาบาล': Icons.local_hospital,
    'psychologist': Icons.psychology,
    'psychiatrist': Icons.psychology_alt,
    'จิตแพทย์': Icons.psychology,
    'นักจิตวิทยา': Icons.psychology,
    'dentist': Icons.health_and_safety,
    'ทันตแพทย์': Icons.health_and_safety,
    'nutritionist': Icons.restaurant,
    'นักโภชนาการ': Icons.restaurant,
    'physical_therapist': Icons.fitness_center,
    'นักกายภาพ': Icons.fitness_center,
    'expert': Icons.person_outline,
    'specialist': Icons.person_outline,
    'ผู้เชี่ยวชาญ': Icons.person_outline,
  };
  return roleIconMap[normalized];
}

/// Convert role to a known icon name string for parseExpertGroupIcon
String? iconNameFromRole(String? role) {
  final normalized = role?.toLowerCase().trim() ?? '';
  const map = <String, String>{
    'doctor': 'medical_services',
    'physician': 'medical_services',
    'แพทย์': 'medical_services',
    'หมอ': 'medical_services',
    'อาจารย์แพทย์': 'medical_services',
    'pharmacist': 'medication',
    'pharmacy': 'local_pharmacy',
    'เภสัชกร': 'medication',
    'เภสัช': 'medication',
    'nurse': 'local_hospital',
    'พยาบาล': 'local_hospital',
    'psychologist': 'psychology',
    'psychiatrist': 'psychology_alt',
    'จิตแพทย์': 'psychology',
    'นักจิตวิทยา': 'psychology',
    'dentist': 'health_and_safety',
    'ทันตแพทย์': 'health_and_safety',
    'nutritionist': 'restaurant',
    'นักโภชนาการ': 'restaurant',
    'physical_therapist': 'fitness_center',
    'นักกายภาพ': 'fitness_center',
  };
  return map[normalized];
}
