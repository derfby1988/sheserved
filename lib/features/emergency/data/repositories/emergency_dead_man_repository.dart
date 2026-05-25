import 'package:supabase_flutter/supabase_flutter.dart';

/// Represents per-user dead man's switch configuration/check-in state.
class EmergencyDeadManCheckin {
  final String userId;
  final bool isEnabled;
  final int checkInIntervalMinutes;
  final DateTime? lastCheckInAt;
  final DateTime? lastTriggeredAt;
  final DateTime? lastReminderAt;

  EmergencyDeadManCheckin({
    required this.userId,
    required this.isEnabled,
    required this.checkInIntervalMinutes,
    this.lastCheckInAt,
    this.lastTriggeredAt,
    this.lastReminderAt,
  });

  factory EmergencyDeadManCheckin.fromJson(Map<String, dynamic> json) {
    return EmergencyDeadManCheckin(
      userId: json['user_id'] as String,
      isEnabled: json['is_enabled'] == true,
      checkInIntervalMinutes: (json['check_in_interval_minutes'] as int?) ?? 720,
      lastCheckInAt: json['last_check_in_at'] != null
          ? DateTime.tryParse(json['last_check_in_at'].toString())
          : null,
      lastTriggeredAt: json['last_triggered_at'] != null
          ? DateTime.tryParse(json['last_triggered_at'].toString())
          : null,
      lastReminderAt: json['last_reminder_at'] != null
          ? DateTime.tryParse(json['last_reminder_at'].toString())
          : null,
    );
  }
}

class EmergencyDeadManRepository {
  final SupabaseClient _client;

  EmergencyDeadManRepository(this._client);

  Future<EmergencyDeadManCheckin?> fetchCheckin(String userId) async {
    final row = await _client
        .from('emergency_health_dead_man_checkins')
        .select()
        .eq('user_id', userId)
        .maybeSingle();
    if (row == null) return null;
    return EmergencyDeadManCheckin.fromJson(row as Map<String, dynamic>);
  }

  Future<void> upsertCheckin({
    required String userId,
    bool? isEnabled,
    int? intervalMinutes,
    DateTime? lastCheckInAt,
  }) async {
    final payload = {
      'user_id': userId,
      'updated_at': DateTime.now().toIso8601String(),
      if (isEnabled != null) 'is_enabled': isEnabled,
      if (intervalMinutes != null) 'check_in_interval_minutes': intervalMinutes,
      if (lastCheckInAt != null) 'last_check_in_at': lastCheckInAt.toIso8601String(),
    };
    await _client
        .from('emergency_health_dead_man_checkins')
        .upsert(payload, onConflict: 'user_id')
        .eq('user_id', userId);
  }

  Future<void> updateCheckInTimestamp({
    required String userId,
    DateTime? checkInAt,
  }) async {
    await _client
        .from('emergency_health_dead_man_checkins')
        .update({
          'last_check_in_at': (checkInAt ?? DateTime.now()).toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('user_id', userId)
        .eq('is_enabled', true);
  }
}
