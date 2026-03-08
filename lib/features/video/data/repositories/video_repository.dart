import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;
import 'dart:io';
import 'dart:convert';
import '../../../../config/app_config.dart';
import '../../models/video_models.dart';

/// Repository สำหรับจัดการข้อมูลวิดีโอ
class VideoRepository {
  final SupabaseClient _client;
  DateTime? _lastUploadTimestamp;

  /// จำนวนภาพถ่ายสูงสุดต่อการแจ้งเหตุ 1 ครั้ง
  static const int maxEmergencyPhotos = 5;

  VideoRepository(this._client);

  /// ตรวจสอบ Cooldown การอัปโหลด
  bool get canUpload {
    if (_lastUploadTimestamp == null) return true;
    final cooldown = Duration(seconds: 1); // Mock constant or SyncConfig
    return DateTime.now().difference(_lastUploadTimestamp!) >= cooldown;
  }

  void markUploadStarted() {
    _lastUploadTimestamp = DateTime.now();
  }

  /// ดึงวิดีโอทั้งหมด (เรียงตามวันที่สร้าง)
  Future<List<Video>> getVideos({String? type}) async {
    var query = _client.from('videos').select();
    if (type != null) {
      query = query.eq('type', type);
    }
    final response = await query
        .eq('status', 'ready')
        .order('created_at', ascending: false);
    return (response as List).map((json) => Video.fromJson(json)).toList();
  }

  /// ดึงวิดีโอฉุกเฉินที่กำลัง Live อยู่
  Future<List<Video>> getEmergencyVideos() async {
    final response = await _client
        .from('videos')
        .select()
        .eq('type', 'emergency')
        .order('created_at', ascending: false)
        .limit(20);
    return (response as List).map((json) => Video.fromJson(json)).toList();
  }

  /// ดึงวิดีโอตาม ID
  Future<Video?> getVideoById(String id) async {
    final response = await _client
        .from('videos')
        .select()
        .eq('id', id)
        .maybeSingle();
    if (response == null) return null;
    return Video.fromJson(response);
  }

  /// ดึง GPS Tracks ของวิดีโอ
  Future<List<VideoGpsTrack>> getGpsTracks(String videoId) async {
    final response = await _client
        .from('video_gps_tracks')
        .select()
        .eq('video_id', videoId)
        .order('timestamp_offset');
    return (response as List)
        .map((json) => VideoGpsTrack.fromJson(json))
        .toList();
  }

  /// เพิ่ม Interaction (like, gift, view)
  Future<void> addInteraction(VideoInteraction interaction) async {
    await _client.from('video_interactions').insert(interaction.toJson());
  }

  /// ดึงจำนวน Interaction สรุป
  Future<Map<String, dynamic>> getInteractionSummary(String videoId) async {
    final likes = await _client
        .from('video_interactions')
        .select()
        .eq('video_id', videoId)
        .eq('type', 'like');

    final gifts = await _client
        .from('video_interactions')
        .select('value')
        .eq('video_id', videoId)
        .eq('type', 'gift');

    double totalDonation = 0;
    for (final g in (gifts as List)) {
      totalDonation += (g['value'] as num? ?? 0).toDouble();
    }

    return {
      'likes': (likes as List).length,
      'donations': totalDonation,
    };
  }

  /// Stream สำหรับ Real-time updates ของวิดีโอ
  Stream<List<Video>> watchEmergencyVideos() {
    return _client
        .from('videos')
        .stream(primaryKey: ['id'])
        .eq('type', 'emergency')
        .order('created_at')
        .map((data) => data.map((json) => Video.fromJson(json)).toList());
  }

  /// อัปโหลดวิดีโอแจ้งเหตุฉุกเฉินพร้อมพิกัด GPS
  /// ต้องส่ง [userId] เข้ามาเสมอตาม auth_data_guidelines.md
  Future<void> uploadEmergencyVideo({
    required String userId,
    required File videoFile,
    required List<Map<String, dynamic>> gpsTracks,
    String? categoryId,
  }) async {
    if (!canUpload) {
      throw Exception("Please wait before uploading again.");
    }

    markUploadStarted();

    var request = http.MultipartRequest(
      'POST',
      Uri.parse('${AppConfig.localApiUrl}/api/video/upload'),
    );

    request.fields['userId'] = userId;
    request.fields['title'] = 'Emergency Incident ${DateTime.now().toIso8601String()}';
    request.fields['type'] = 'emergency';
    if (categoryId != null) request.fields['categoryId'] = categoryId;
    request.fields['gpsTracks'] = jsonEncode(gpsTracks);

    request.files.add(await http.MultipartFile.fromPath('video', videoFile.path));

    var response = await request.send();

    if (response.statusCode != 200) {
      throw Exception("Upload failed with status ${response.statusCode}");
    }
  }

  /// อัปโหลดภาพถ่ายแจ้งเหตุฉุกเฉินพร้อมพิกัด GPS
  /// ต้องส่ง [userId] เข้ามาเสมอตาม auth_data_guidelines.md
  Future<void> uploadEmergencyPhotos({
    required String userId,
    required List<File> photoFiles,
    required List<Map<String, dynamic>> gpsTracks,
    String? categoryId,
  }) async {
    if (!canUpload) {
      throw Exception("Please wait before uploading again.");
    }

    if (photoFiles.length > maxEmergencyPhotos) {
      throw Exception("อัปโหลดรูปภาพได้สูงสุด $maxEmergencyPhotos รูปต่อครั้ง");
    }

    if (photoFiles.isEmpty) {
      throw Exception("No photos provided to upload.");
    }

    markUploadStarted();

    var request = http.MultipartRequest(
      'POST',
      Uri.parse('${AppConfig.localApiUrl}/api/video/upload-photos'),
    );

    request.fields['userId'] = userId;
    request.fields['title'] = 'Emergency Photo Report ${DateTime.now().toIso8601String()}';
    request.fields['type'] = 'emergency_photo';
    if (categoryId != null) request.fields['categoryId'] = categoryId;
    request.fields['gpsTracks'] = jsonEncode(gpsTracks);

    for (var file in photoFiles) {
      request.files.add(await http.MultipartFile.fromPath('photos', file.path));
    }

    var response = await request.send();

    if (response.statusCode != 200) {
      throw Exception("Upload failed with status ${response.statusCode}");
    }
  }

  /// ดึงพิกัดล่าสุดของ Live/วิดีโอ ที่กำลังออนไลน์หรือประมวลผลเสร็จแล้ว
  /// ใช้สำหรับแสดงบน Google Maps ในหน้า Home (Guest Mode)
  Future<List<Map<String, dynamic>>> getActiveLiveLocations() async {
    try {
      // ดึงวิดีโอที่มีสถานะ ready และเป็นประเภท emergency หรือ normal
      final response = await _client
          .from('videos')
          .select('id, user_id, type, status, video_gps_tracks(latitude, longitude, timestamp_offset)')
          .or('status.eq.ready,status.eq.processing')
          .order('created_at', ascending: false)
          .limit(20);

      final List<Map<String, dynamic>> locations = [];
      
      for (var video in response as List) {
        final tracks = video['video_gps_tracks'] as List?;
        if (tracks != null && tracks.isNotEmpty) {
          // ใช้พิกัดล่าสุด (ที่มี timestamp_offset มากที่สุด)
          final latestTrack = tracks.reduce((curr, next) => 
            (curr['timestamp_offset'] as int) > (next['timestamp_offset'] as int) ? curr : next
          );
          
          locations.add({
            'videoId': video['id'],
            'userId': video['user_id'],
            'type': video['type'],
            'latitude': latestTrack['latitude'],
            'longitude': latestTrack['longitude'],
          });
        }
      }
      return locations;
    } catch (e) {
      debugPrint("Error fetching active live locations: $e");
      return [];
    }
  }

  /// ดึงเหตุฉุกเฉินที่ยังค้างอยู่ (ไม่มีสถานะ resolved) พร้อมพิกัด GPS
  /// ใช้สำหรับ Home Map แสดงเหตุการณ์ใกล้เคียงผู้ใช้
  Future<List<Map<String, dynamic>>> getActiveEmergencyLocations() async {
    try {
      // ดึง emergency videos ที่ยังไม่มีการ resolve
      final response = await _client
          .from('videos')
          .select('''
            id, user_id, type, status, created_at,
            video_gps_tracks(latitude, longitude, timestamp_offset),
            donation_categories(name, icon_name)
          ''')
          .eq('type', 'emergency')
          .or('status.eq.ready,status.eq.processing,status.eq.live')
          .order('created_at', ascending: false)
          .limit(50);

      // ดึง IDs ที่มีการ resolve แล้ว
      final resolvedResponse = await _client
          .from('incident_responses')
          .select('video_id')
          .eq('status', 'resolved');

      final resolvedIds = (resolvedResponse as List)
          .map((r) => r['video_id'] as String)
          .toSet();

      final List<Map<String, dynamic>> locations = [];

      for (var video in response as List) {
        final videoId = video['id'] as String;
        // ข้ามเหตุการณ์ที่ resolve แล้ว
        if (resolvedIds.contains(videoId)) continue;

        final tracks = video['video_gps_tracks'] as List?;
        if (tracks != null && tracks.isNotEmpty) {
          final latestTrack = tracks.reduce((curr, next) =>
              (curr['timestamp_offset'] as int) > (next['timestamp_offset'] as int) ? curr : next);

          final category = video['donation_categories'];
          locations.add({
            'videoId': videoId,
            'userId': video['user_id'],
            'type': video['type'],
            'status': video['status'],
            'latitude': (latestTrack['latitude'] as num).toDouble(),
            'longitude': (latestTrack['longitude'] as num).toDouble(),
            'categoryName': category != null ? category['name'] : 'เหตุฉุกเฉิน',
            'categoryIcon': category != null ? category['icon_name'] : 'warning',
            'createdAt': video['created_at'],
          });
        }
      }
      return locations;
    } catch (e) {
      debugPrint("Error fetching active emergency locations: $e");
      return [];
    }
  }

  // ==========================================
  // Volunteer & Rescue Response Features
  // ==========================================

  /// Accept an emergency rescue job (stores volunteer start location)
  Future<String> acceptRescue({
    required String videoId,
    required String volunteerId,
    double? startLat,
    double? startLng,
  }) async {
    try {
      final response = await _client.from('incident_responses').insert({
        'video_id': videoId,
        'volunteer_id': volunteerId,
        'status': 'accepted',
        'accepted_at': DateTime.now().toIso8601String(),
        'volunteer_start_lat': startLat,
        'volunteer_start_lng': startLng,
      }).select('id').single();
      
      return response['id'] as String;
    } catch (e) {
      // Handle duplicate (UNIQUE constraint violation)
      if (e.toString().contains('duplicate') || e.toString().contains('unique')) {
        throw Exception('คุณได้รับงานนี้ไปแล้ว');
      }
      rethrow;
    }
  }

  /// Update the status of an ongoing rescue
  Future<void> updateRescueStatus({
    required String responseId,
    required String status,
    String? notes,
  }) async {
    final Map<String, dynamic> updates = {
      'status': status,
      'updated_at': DateTime.now().toIso8601String(),
    };
    
    if (status == 'arrived') updates['arrived_at'] = DateTime.now().toIso8601String();
    if (status == 'resolved' || status == 'cancelled') {
        updates['resolved_at'] = DateTime.now().toIso8601String();
    }
    if (notes != null) updates['notes'] = notes;

    await _client.from('incident_responses').update(updates).eq('id', responseId);
  }

  /// Fetch the volunteer's active rescues to persist state
  Future<List<Map<String, dynamic>>> getActiveRescues(String volunteerId) async {
    final response = await _client
        .from('incident_responses')
        .select('*, videos(*)')
        .eq('volunteer_id', volunteerId)
        .inFilter('status', ['accepted', 'arrived'])
        .order('accepted_at', ascending: false);
    
    return List<Map<String, dynamic>>.from(response as List);
  }

  /// Get the real GPS location of an emergency incident from video_gps_tracks
  Future<Map<String, double>?> getEmergencyLocation(String videoId) async {
    try {
      final response = await _client
          .from('video_gps_tracks')
          .select('latitude, longitude')
          .eq('video_id', videoId)
          .order('timestamp_offset', ascending: false)
          .limit(1)
          .maybeSingle();
      
      if (response != null) {
        return {
          'latitude': (response['latitude'] as num).toDouble(),
          'longitude': (response['longitude'] as num).toDouble(),
        };
      }
      return null;
    } catch (e) {
      debugPrint('Error fetching emergency location: $e');
      return null;
    }
  }

  /// Toggle the volunteer's active duty status
  Future<void> setVolunteerActiveStatus({
    required String userId,
    required bool isActive,
  }) async {
    await _client.from('consumer_profiles').update({
      'is_volunteer_active': isActive,
    }).eq('user_id', userId);
  }

  /// Check if user has an active volunteer profession
  Future<bool> isUserVolunteer(String userId) async {
    try {
      final response = await _client
          .from('user_group_roles')
          .select('profession_id, professions!inner(is_volunteer)')
          .eq('user_id', userId)
          .eq('professions.is_volunteer', true)
          .limit(1);
      return (response as List).isNotEmpty;
    } catch (e) {
      debugPrint('Error checking volunteer status: $e');
      return false;
    }
  }
}
