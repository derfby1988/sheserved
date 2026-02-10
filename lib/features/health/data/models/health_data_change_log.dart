class HealthDataChangeLog {
  final String id;
  final int? sequence; // Can be calculated on client side or via DB window function
  final DateTime timestamp;
  final String field;
  final String? oldValue;
  final String newValue;
  final String? editorName;

  const HealthDataChangeLog({
    required this.id,
    this.sequence,
    required this.timestamp,
    required this.field,
    this.oldValue,
    required this.newValue,
    this.editorName,
  });

  factory HealthDataChangeLog.fromJson(Map<String, dynamic> json) {
    return HealthDataChangeLog(
      id: json['id'],
      timestamp: DateTime.parse(json['created_at']),
      field: json['field_type'],
      oldValue: json['old_value'],
      newValue: json['new_value'],
      editorName: json['editor_name'] ?? 'Unknown',
    );
  }
}
