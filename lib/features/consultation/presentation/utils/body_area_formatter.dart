import '../../data/models/consultation_request_model.dart';

/// Resolves a human-readable body-area / symptom text from multiple data sources.
/// Sources are checked in priority order:
///  1. request symptoms
///  2. consultationData symptoms
///  3. entry bodyArea string
///  4. symptomsChart parts labels
///  5. bodyAreaMap explicit keys
String resolveBodyAreaText({
  List<dynamic>? requestSymptoms,
  Map<String, dynamic>? requestBodyArea,
  Map<String, dynamic>? requestSymptomsChart,
  String? entryBodyArea,
  Map<String, dynamic>? entrySymptomsChart,
  List<dynamic>? consultDataSymptoms,
  Map<String, dynamic>? consultDataBodyArea,
  Map<String, dynamic>? consultDataSymptomsChart,
}) {
  final symptomLabels = <String>[];

  void collectFromSymptoms(dynamic rawSymptoms) {
    final symptoms = rawSymptoms as List? ?? const [];
    for (final s in symptoms) {
      if (s is SymptomPoint && s.displayLabel.trim().isNotEmpty) {
        symptomLabels.add(s.displayLabel.trim());
      } else if (s is Map<String, dynamic>) {
        final label = s['display_label']?.toString().trim() ?? '';
        if (label.isNotEmpty) symptomLabels.add(label);
      }
    }
  }

  collectFromSymptoms(requestSymptoms);
  collectFromSymptoms(consultDataSymptoms);

  if (symptomLabels.isNotEmpty) {
    return symptomLabels.toSet().join(', ');
  }

  Map<String, dynamic> bodyAreaMap = {};
  Map<String, dynamic> symptomsChart = {};

  final trimmedEntryBodyArea = (entryBodyArea ?? '').trim();
  if (trimmedEntryBodyArea.isNotEmpty && trimmedEntryBodyArea != 'ไม่ระบุ') {
    return trimmedEntryBodyArea;
  }

  if (entrySymptomsChart != null) {
    symptomsChart = entrySymptomsChart;
  }

  if (requestBodyArea != null) {
    bodyAreaMap = requestBodyArea;
  }
  if (requestSymptomsChart != null) {
    symptomsChart = requestSymptomsChart;
  }

  if (consultDataBodyArea != null) {
    bodyAreaMap = consultDataBodyArea;
  }
  if (consultDataSymptomsChart != null) {
    symptomsChart = consultDataSymptomsChart;
  }

  final parts = symptomsChart['parts'];
  if (parts is List && parts.isNotEmpty) {
    final labels = parts
        .map((p) {
          if (p is Map<String, dynamic>) {
            return p['label']?.toString().trim() ??
                p['name']?.toString().trim() ??
                '';
          }
          return '';
        })
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList();
    if (labels.isNotEmpty) return labels.join(', ');
  }

  final explicit = [
    bodyAreaMap['area']?.toString(),
    bodyAreaMap['label']?.toString(),
    bodyAreaMap['part']?.toString(),
  ]
      .where((s) =>
          s != null &&
          s.trim().isNotEmpty &&
          s.trim().toLowerCase() != 'null')
      .map((s) => s!.trim())
      .toList();
  if (explicit.isNotEmpty) return explicit.first;

  final keys = bodyAreaMap.keys
      .where((k) => k != 'gender' && k != 'age' && k != 'lang' && k != 'sex')
      .map((k) => k.toString().trim())
      .where((k) => k.isNotEmpty)
      .toSet()
      .toList();
  if (keys.isNotEmpty) return keys.join(', ');

  return 'ไม่ระบุบริเวณ';
}
