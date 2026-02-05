import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Database Service สำหรับเชื่อมต่อกับ Local PostgreSQL ผ่าน REST API
/// ใช้ WebSocket Server เป็น API Gateway
class DatabaseService {
  static DatabaseService? _instance;
  final String _baseUrl;

  DatabaseService._(this._baseUrl);

  /// Singleton instance
  factory DatabaseService({String? baseUrl}) {
    _instance ??= DatabaseService._(
      baseUrl ?? 'http://localhost:3000',
    );
    return _instance!;
  }

  /// Reset instance (for testing)
  static void reset() {
    _instance = null;
  }

  // ============ HTTP HELPERS ============

  Future<Map<String, String>> get _headers async {
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
  }

  Future<dynamic> _get(String endpoint) async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl$endpoint'),
        headers: await _headers,
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception('GET $endpoint failed: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('DatabaseService GET error: $e');
      rethrow;
    }
  }

  Future<dynamic> _post(String endpoint, Map<String, dynamic> data) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl$endpoint'),
        headers: await _headers,
        body: json.encode(data),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        return json.decode(response.body);
      } else {
        throw Exception('POST $endpoint failed: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('DatabaseService POST error: $e');
      rethrow;
    }
  }

  Future<dynamic> _put(String endpoint, Map<String, dynamic> data) async {
    try {
      final response = await http.put(
        Uri.parse('$_baseUrl$endpoint'),
        headers: await _headers,
        body: json.encode(data),
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception('PUT $endpoint failed: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('DatabaseService PUT error: $e');
      rethrow;
    }
  }

  Future<void> _delete(String endpoint) async {
    try {
      final response = await http.delete(
        Uri.parse('$_baseUrl$endpoint'),
        headers: await _headers,
      );

      if (response.statusCode != 200 && response.statusCode != 204) {
        throw Exception('DELETE $endpoint failed: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('DatabaseService DELETE error: $e');
      rethrow;
    }
  }

  // ============ HEALTH CHECK ============

  /// Check if server is running
  Future<bool> healthCheck() async {
    try {
      final result = await _get('/health');
      return result['status'] == 'ok';
    } catch (e) {
      return false;
    }
  }

  // ============ LOCATIONS API ============

  /// Get user's recent locations
  Future<List<Map<String, dynamic>>> getUserLocations(String userId, {int limit = 100}) async {
    final result = await _get('/api/locations/$userId?limit=$limit');
    return List<Map<String, dynamic>>.from(result);
  }

  // ============ PROFESSIONS API ============
  // Note: ต้องเพิ่ม endpoints ใน WebSocket Server

  /// Get all professions
  Future<List<Map<String, dynamic>>> getProfessions() async {
    return await _get('/api/professions');
  }

  /// Get profession by ID
  Future<Map<String, dynamic>> getProfessionById(String id) async {
    return await _get('/api/professions/$id');
  }

  // ============ REGISTRATION FIELDS API ============

  /// Get registration fields for a profession
  Future<List<Map<String, dynamic>>> getRegistrationFields(String professionId) async {
    return await _get('/api/professions/$professionId/fields');
  }

  // ============ USERS API ============

  /// Create user
  Future<Map<String, dynamic>> createUser(Map<String, dynamic> userData) async {
    return await _post('/api/users', userData);
  }

  /// Get user by ID
  Future<Map<String, dynamic>> getUserById(String userId) async {
    return await _get('/api/users/$userId');
  }

  /// Update user
  Future<Map<String, dynamic>> updateUser(String userId, Map<String, dynamic> userData) async {
    return await _put('/api/users/$userId', userData);
  }

  // ============ REGISTRATION APPLICATIONS API ============

  /// Submit registration application
  Future<Map<String, dynamic>> submitApplication(Map<String, dynamic> applicationData) async {
    return await _post('/api/applications', applicationData);
  }

  /// Get pending applications (admin only)
  Future<List<Map<String, dynamic>>> getPendingApplications() async {
    return await _get('/api/applications?status=pending');
  }

  /// Approve application (admin only)
  Future<void> approveApplication(String applicationId, {String? note}) async {
    await _post('/api/applications/$applicationId/approve', {'note': note});
  }

  /// Reject application (admin only)
  Future<void> rejectApplication(String applicationId, {required String note}) async {
    await _post('/api/applications/$applicationId/reject', {'note': note});
  }
}
