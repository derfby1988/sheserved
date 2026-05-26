import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../../../config/app_config.dart';

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

  static String _stringOrEmpty(dynamic value) {
    if (value == null) return '';
    return value.toString();
  }

  static int _intOrDefault(dynamic value, int fallback) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  factory EmergencyDeadManCheckin.fromJson(Map<String, dynamic> json) {
    return EmergencyDeadManCheckin(
      userId: (json['user_id'] ?? json['userId']) as String,
      isEnabled: json['is_enabled'] == true || json['isEnabled'] == true,
      checkInIntervalMinutes: (json['check_in_interval_minutes'] as int?) ??
          (json['checkInIntervalMinutes'] as int?) ??
          720,
      lastCheckInAt: json['last_check_in_at'] != null
          ? DateTime.tryParse(json['last_check_in_at'].toString())
          : json['lastCheckInAt'] != null
              ? DateTime.tryParse(json['lastCheckInAt'].toString())
          : null,
      lastTriggeredAt: json['last_triggered_at'] != null
          ? DateTime.tryParse(json['last_triggered_at'].toString())
          : json['lastTriggeredAt'] != null
              ? DateTime.tryParse(json['lastTriggeredAt'].toString())
          : null,
      lastReminderAt: json['last_reminder_at'] != null
          ? DateTime.tryParse(json['last_reminder_at'].toString())
          : json['lastReminderAt'] != null
              ? DateTime.tryParse(json['lastReminderAt'].toString())
          : null,
    );
  }
}

class EmergencyDeadManRepository {
  final String _baseUrl;

  EmergencyDeadManRepository({String? baseUrl})
      : _baseUrl = baseUrl ?? AppConfig.localApiUrl;

  Future<EmergencyDeadManCheckin?> fetchCheckin(String userId) async {
    try {
      final response = await http
          .get(Uri.parse('$_baseUrl/api/emergency-health/dead-man/$userId'))
          .timeout(const Duration(seconds: 8));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('Failed to load dead-man check-in (${response.statusCode}): ${response.body}');
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map) return null;
      final checkin = decoded['checkin'];
      if (checkin == null) return null;
      return EmergencyDeadManCheckin.fromJson(Map<String, dynamic>.from(checkin as Map));
    } catch (e) {
      debugPrint('Error fetching dead-man check-in: $e');
      return null;
    }
  }

  Future<void> upsertCheckin({
    required String userId,
    bool? isEnabled,
    int? intervalMinutes,
    DateTime? lastCheckInAt,
  }) async {
    try {
      final payload = {
        'userId': userId,
        'checkin': {
          if (isEnabled != null) 'isEnabled': isEnabled,
          if (intervalMinutes != null) 'checkInIntervalMinutes': intervalMinutes,
          if (lastCheckInAt != null) 'lastCheckInAt': lastCheckInAt.toIso8601String(),
        },
      };

      final response = await http
          .post(
            Uri.parse('$_baseUrl/api/emergency-health/dead-man'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 8));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('Failed to save dead-man check-in (${response.statusCode}): ${response.body}');
      }
    } catch (e) {
      debugPrint('Error upserting dead-man check-in: $e');
      rethrow;
    }
  }

  Future<void> updateCheckInTimestamp({
    required String userId,
    DateTime? checkInAt,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/api/emergency-health/dead-man/check-in'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'userId': userId,
              'checkInAt': (checkInAt ?? DateTime.now()).toIso8601String(),
            }),
          )
          .timeout(const Duration(seconds: 8));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('Failed to update dead-man check-in (${response.statusCode}): ${response.body}');
      }
    } catch (e) {
      debugPrint('Error updating dead-man check-in timestamp: $e');
      rethrow;
    }
  }
}
