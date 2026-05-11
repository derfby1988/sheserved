import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:sheserved/config/app_config.dart';
import 'package:sheserved/services/service_locator.dart';

class WatermarkConfig {
  final bool isEnabled;
  final String type;
  final String? textContent;
  final String? imageUrl;
  final String position;
  final String animationType;
  final double opacity;
  final bool showIncidentId;
  final bool showUploaderId;

  WatermarkConfig({
    required this.isEnabled,
    required this.type,
    this.textContent,
    this.imageUrl,
    required this.position,
    required this.animationType,
    required this.opacity,
    required this.showIncidentId,
    required this.showUploaderId,
  });

  factory WatermarkConfig.fromJson(Map<String, dynamic> json) {
    return WatermarkConfig(
      isEnabled: json['is_enabled'] ?? false,
      type: json['type'] ?? 'text',
      textContent: json['text_content'],
      imageUrl: json['image_url'],
      position: json['position'] ?? 'bottom-right',
      animationType: json['animation_type'] ?? 'none',
      opacity: json['opacity'] != null
          ? double.tryParse(json['opacity'].toString()) ?? 0.5
          : 0.5,
      showIncidentId: json['show_incident_id'] ?? false,
      showUploaderId: json['show_uploader_id'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'is_enabled': isEnabled,
      'type': type,
      'text_content': textContent,
      'position': position,
      'animation_type': animationType,
      'opacity': opacity,
      'show_incident_id': showIncidentId,
      'show_uploader_id': showUploaderId,
    };
  }
}

class WatermarkRepository {
  final String _baseUrl = AppConfig.localApiUrl;

  Map<String, String> get _headers {
    final userId = ServiceLocator.instance.currentUser?.id;
    return {
      'Content-Type': 'application/json',
      if (userId != null) 'x-user-id': userId,
    };
  }

  Future<WatermarkConfig?> getConfig() async {
    try {
      final response = await http.get(Uri.parse('$_baseUrl/api/admin/watermark'));
      if (response.statusCode == 200) {
        return WatermarkConfig.fromJson(json.decode(response.body));
      }
      return null;
    } catch (e) {
      print('Error fetching watermark config: $e');
      return null;
    }
  }

  /// ผลลัพธ์: null = สำเร็จ, String = ข้อความ Error
  Future<String?> updateConfig(WatermarkConfig config) async {
    try {
      final response = await http.put(
        Uri.parse('$_baseUrl/api/admin/watermark'),
        headers: _headers,
        body: json.encode(config.toJson()),
      );
      if (response.statusCode == 200) return null; // ✅ สำเร็จ
      // คืน error message จาก server
      try {
        final body = json.decode(response.body);
        return body['error'] ?? 'HTTP ${response.statusCode}';
      } catch (_) {
        return 'HTTP ${response.statusCode}: ${response.body}';
      }
    } catch (e) {
      return 'เชื่อมต่อ Server ไม่ได้: $e';
    }
  }

  Future<String?> uploadImage(File imageFile) async {
    try {
      final userId = ServiceLocator.instance.currentUser?.id;
      final uri = Uri.parse('$_baseUrl/api/admin/watermark/upload');
      final request = http.MultipartRequest('POST', uri);
      
      if (userId != null) {
        request.headers['x-user-id'] = userId;
      }
      
      request.files.add(await http.MultipartFile.fromPath('watermark_image', imageFile.path));
      
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['imageUrl'];
      }
      return null;
    } catch (e) {
      print('Error uploading watermark image: $e');
      return null;
    }
  }
}
