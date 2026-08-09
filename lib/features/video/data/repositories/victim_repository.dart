import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import '../../../../config/app_config.dart';
import '../../models/triage_models.dart';
import '../../../../services/auth_service.dart';

class VictimRepository {
  static const String _baseUrl = AppConfig.localApiUrl;

  Map<String, String> get _headers {
    final headers = {'Content-Type': 'application/json'};
    final userId = AuthService.instance.currentUser?.id;
    if (userId != null && userId.isNotEmpty) {
      headers['x-user-id'] = userId;
    }
    return headers;
  }

  Future<VictimListResponse> getVictims(String incidentId) async {
    final url = '$_baseUrl/api/incidents/$incidentId/victims';
    final response = await http.get(Uri.parse(url), headers: _headers).timeout(
      const Duration(seconds: 10),
    );
    if (response.statusCode == 200) {
      return VictimListResponse.fromJson(jsonDecode(response.body));
    }
    throw Exception('Failed to fetch victims: ${response.statusCode}');
  }

  Future<TriageSummary> getTriageSummary(String incidentId) async {
    final url = '$_baseUrl/api/incidents/$incidentId/triage-summary';
    final response = await http.get(Uri.parse(url), headers: _headers).timeout(
      const Duration(seconds: 10),
    );
    if (response.statusCode == 200) {
      final json = jsonDecode(response.body);
      return TriageSummary.fromJson(json['summary'] as Map<String, dynamic>);
    }
    throw Exception('Failed to fetch triage summary: ${response.statusCode}');
  }

  Future<IncidentVictim> addVictim({
    required String incidentId,
    required String prefix,
    String? firstName,
    String? lastName,
    required bool consent,
  }) async {
    final url = '$_baseUrl/api/incidents/$incidentId/victims';
    final response = await http.post(
      Uri.parse(url),
      headers: _headers,
      body: jsonEncode({
        'prefix': prefix,
        'firstName': firstName,
        'lastName': lastName,
        'consent': consent,
      }),
    ).timeout(const Duration(seconds: 10));

    if (response.statusCode == 201) {
      final json = jsonDecode(response.body);
      return IncidentVictim.fromJson(json['victim'] as Map<String, dynamic>);
    }
    final err = jsonDecode(response.body);
    throw Exception(err['error'] ?? 'Failed to add victim');
  }

  Future<IncidentVictim> editVictimName({
    required String victimId,
    required String prefix,
    String? firstName,
    String? lastName,
  }) async {
    final url = '$_baseUrl/api/victims/$victimId';
    final response = await http.patch(
      Uri.parse(url),
      headers: _headers,
      body: jsonEncode({
        'prefix': prefix,
        'firstName': firstName,
        'lastName': lastName,
      }),
    ).timeout(const Duration(seconds: 10));

    if (response.statusCode == 200) {
      final json = jsonDecode(response.body);
      return IncidentVictim.fromJson(json['victim'] as Map<String, dynamic>);
    }
    final err = jsonDecode(response.body);
    throw Exception(err['error'] ?? 'Failed to edit victim');
  }

  Future<IncidentVictim> assignTriage({
    required String victimId,
    required TriageLevel level,
    String? note,
  }) async {
    final url = '$_baseUrl/api/victims/$victimId/triage';
    final response = await http.patch(
      Uri.parse(url),
      headers: _headers,
      body: jsonEncode({
        'triageLevel': level.label,
        'note': note,
      }),
    ).timeout(const Duration(seconds: 10));

    if (response.statusCode == 200) {
      final json = jsonDecode(response.body);
      return IncidentVictim.fromJson(json['victim'] as Map<String, dynamic>);
    }
    final err = jsonDecode(response.body);
    throw Exception(err['error'] ?? 'Failed to assign triage');
  }

  Future<void> disputeVictim({
    required String victimId,
    required String reason,
  }) async {
    final url = '$_baseUrl/api/victims/$victimId/dispute';
    final response = await http.post(
      Uri.parse(url),
      headers: _headers,
      body: jsonEncode({'reason': reason}),
    ).timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      final err = jsonDecode(response.body);
      throw Exception(err['error'] ?? 'Failed to dispute victim');
    }
  }

  Future<void> deleteVictim({
    required String victimId,
    required String reason,
  }) async {
    final url = '$_baseUrl/api/victims/$victimId';
    final response = await http.delete(
      Uri.parse(url),
      headers: _headers,
      body: jsonEncode({'reason': reason}),
    ).timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      final err = jsonDecode(response.body);
      throw Exception(err['error'] ?? 'Failed to delete victim');
    }
  }

  Future<List<TriageHistoryEntry>> getHistory(String victimId) async {
    final url = '$_baseUrl/api/victims/$victimId/history';
    final response = await http.get(Uri.parse(url), headers: _headers).timeout(
      const Duration(seconds: 10),
    );
    if (response.statusCode == 200) {
      final json = jsonDecode(response.body);
      final list = json['history'] as List<dynamic>? ?? [];
      return list
          .map((e) => TriageHistoryEntry.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    throw Exception('Failed to fetch history: ${response.statusCode}');
  }

  Future<Map<String, dynamic>> unlockHealthData(String victimId) async {
    final url = '$_baseUrl/api/victims/$victimId/health-data/unlock';
    final response = await http.post(
      Uri.parse(url),
      headers: _headers,
    ).timeout(const Duration(seconds: 10));

    final json = jsonDecode(response.body);
    if (response.statusCode == 200) {
      return json;
    }
    throw Exception(json['reason'] ?? 'Failed to unlock health data');
  }
}
