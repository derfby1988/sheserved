import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../../../../config/app_config.dart';
import '../../../../services/websocket_service.dart';

/// Domain object for emergency health data settings stored per user.
class EmergencyHealthSettings {
  final bool isEnabled;
  final int releaseDelayMinutes;
  final List<String> enabledFields;
  final bool requireActiveResponder;
  final bool requireMedicalProfession;
  final bool requireVerified;
  final bool emergencyFallback;
  final List<String> whitelistedUserIds;
  final DateTime? consentGivenAt;
  final DateTime? updatedAt;

  const EmergencyHealthSettings({
    required this.isEnabled,
    required this.releaseDelayMinutes,
    required this.enabledFields,
    required this.requireActiveResponder,
    required this.requireMedicalProfession,
    required this.requireVerified,
    required this.emergencyFallback,
    required this.whitelistedUserIds,
    this.consentGivenAt,
    this.updatedAt,
  });

  static const defaultFields = [
    'blood_type',
    'allergies',
    'emergency_contact',
  ];

  factory EmergencyHealthSettings.defaults() {
    return const EmergencyHealthSettings(
      isEnabled: false,
      releaseDelayMinutes: 5,
      enabledFields: defaultFields,
      requireActiveResponder: true,
      requireMedicalProfession: false,
      requireVerified: false,
      emergencyFallback: false,
      whitelistedUserIds: [],
      consentGivenAt: null,
      updatedAt: null,
    );
  }

  factory EmergencyHealthSettings.fromJson(Map<String, dynamic> json) {
    final enabledFieldsRaw = json['enabled_fields'] ?? json['enabledFields'];
    final whitelistedRaw = json['whitelisted_user_ids'] ?? json['whitelistedUserIds'];

    List<String> parseList(dynamic raw) {
      if (raw == null) return [];
      if (raw is List) {
        return raw.map((e) => e.toString()).toList();
      }
      if (raw is String) {
        try {
          final decoded = jsonDecode(raw);
          if (decoded is List) {
            return decoded.map((e) => e.toString()).toList();
          }
        } catch (_) {}
      }
      return [];
    }

    return EmergencyHealthSettings(
      isEnabled: json['is_enabled'] == true || json['isEnabled'] == true,
      releaseDelayMinutes: json['release_delay_minutes'] is int
          ? json['release_delay_minutes'] as int
          : json['releaseDelayMinutes'] is int
              ? json['releaseDelayMinutes'] as int
          : 5,
      enabledFields: parseList(enabledFieldsRaw).isNotEmpty
          ? parseList(enabledFieldsRaw)
          : defaultFields,
      requireActiveResponder: json['require_active_responder'] != false && json['requireActiveResponder'] != false,
      requireMedicalProfession: json['require_medical_profession'] == true || json['requireMedicalProfession'] == true,
      requireVerified: json['require_verified'] == true || json['requireVerified'] == true,
      emergencyFallback: json['emergency_fallback'] == true || json['emergencyFallback'] == true,
      whitelistedUserIds: parseList(whitelistedRaw),
      consentGivenAt: json['consent_given_at'] != null
          ? DateTime.tryParse(json['consent_given_at'].toString())
          : json['consentGivenAt'] != null
              ? DateTime.tryParse(json['consentGivenAt'].toString())
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'].toString())
          : json['updatedAt'] != null
              ? DateTime.tryParse(json['updatedAt'].toString())
          : null,
    );
  }

  EmergencyHealthSettings copyWith({
    bool? isEnabled,
    int? releaseDelayMinutes,
    List<String>? enabledFields,
    bool? requireActiveResponder,
    bool? requireMedicalProfession,
    bool? requireVerified,
    bool? emergencyFallback,
    List<String>? whitelistedUserIds,
    DateTime? consentGivenAt,
    DateTime? updatedAt,
  }) {
    return EmergencyHealthSettings(
      isEnabled: isEnabled ?? this.isEnabled,
      releaseDelayMinutes: releaseDelayMinutes ?? this.releaseDelayMinutes,
      enabledFields: enabledFields ?? List.from(this.enabledFields),
      requireActiveResponder:
          requireActiveResponder ?? this.requireActiveResponder,
      requireMedicalProfession:
          requireMedicalProfession ?? this.requireMedicalProfession,
      requireVerified: requireVerified ?? this.requireVerified,
      emergencyFallback: emergencyFallback ?? this.emergencyFallback,
      whitelistedUserIds: whitelistedUserIds ?? List.from(this.whitelistedUserIds),
      consentGivenAt: consentGivenAt ?? this.consentGivenAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'is_enabled': isEnabled,
      'release_delay_minutes': releaseDelayMinutes,
      'enabled_fields': enabledFields,
      'require_active_responder': requireActiveResponder,
      'require_medical_profession': requireMedicalProfession,
      'require_verified': requireVerified,
      'emergency_fallback': emergencyFallback,
      'whitelisted_user_ids': whitelistedUserIds,
      'consent_given_at': consentGivenAt?.toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    };
  }
}

class EmergencyHealthSettingsRepository {
  final String _baseUrl;

  EmergencyHealthSettingsRepository({String? baseUrl})
      : _baseUrl = baseUrl ?? AppConfig.localApiUrl;

  Future<EmergencyHealthSettings?> fetchSettings(String userId) async {
    try {
      final response = await http
          .get(Uri.parse('$_baseUrl/api/emergency-health/settings/$userId'))
          .timeout(const Duration(seconds: 8));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('Failed to load emergency health settings (${response.statusCode}): ${response.body}');
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map) return null;
      final settings = decoded['settings'];
      if (settings == null) return null;
      return EmergencyHealthSettings.fromJson(Map<String, dynamic>.from(settings as Map));
    } catch (e) {
      debugPrint('[EmergencyHealthSettingsRepository] load failed, using defaults: $e');
      return null;
    }
  }

  Future<EmergencyHealthSettings> upsertSettings(
      String userId, EmergencyHealthSettings settings) async {
    final payload = {
      'userId': userId,
      'settings': {
        'isEnabled': settings.isEnabled,
        'releaseDelayMinutes': settings.releaseDelayMinutes,
        'enabledFields': settings.enabledFields,
        'requireActiveResponder': settings.requireActiveResponder,
        'requireMedicalProfession': settings.requireMedicalProfession,
        'requireVerified': settings.requireVerified,
        'emergencyFallback': settings.emergencyFallback,
        'whitelistedUserIds': settings.whitelistedUserIds,
        'consentGivenAt': settings.consentGivenAt?.toIso8601String(),
      },
    };

    final response = await http
        .post(
          Uri.parse('$_baseUrl/api/emergency-health/settings'),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode(payload),
        )
        .timeout(const Duration(seconds: 8));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Failed to save emergency health settings (${response.statusCode}): ${response.body}');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is Map && decoded['settings'] is Map) {
      return EmergencyHealthSettings.fromJson(Map<String, dynamic>.from(decoded['settings'] as Map));
    }

    return settings;
  }

  /// [Phase 3a] Revoke all active emergency health sessions and tokens
  /// when the master toggle is turned off during an incident.
  Future<void> revokeActiveSessionsIfDisabled(String userId, bool newIsEnabled) async {
    if (newIsEnabled) return;
    try {
      final ws = WebSocketService();
      await ws.revokeEmergencyHealthSessions(patientId: userId);
    } catch (e) {
      debugPrint('[EmergencyHealthSettingsRepository] revoke sessions error: $e');
    }
  }
}
