import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../config/app_config.dart';
import '../../models/video_models.dart';

/// Repository สำหรับจัดการข้อมูลวิดีโอ
class VideoRepository {
  final SupabaseClient _client;
  DateTime? _lastUploadTimestamp;

  /// จำนวนภาพถ่ายสูงสุดต่อการแจ้งเหตุ 1 ครั้ง (โหมด Emergency ทั่วไป)
  static const int maxEmergencyPhotos = 5;

  /// จำนวนภาพถ่ายสูงสุดสำหรับโหมดไทยมุงโดยเฟพาะ (ตามแผน §4 Thai Mhung)
  static const int maxThaiMhungPhotos = 3;

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
    // Attempt Local API first, since FFmpeg system is local
    try {
      final url = type != null 
          ? '${AppConfig.localApiUrl}/api/videos?type=$type' 
          : '${AppConfig.localApiUrl}/api/videos';
      final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 3));
      if (response.statusCode == 200) {
        final List data = jsonDecode(response.body);
        return data.map((json) => Video.fromJson(json)).toList();
      }
    } catch (e) {
      debugPrint('VideoRepository: Local fetch failed (this is normal if server is off) - $e');
    }

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
    // Attempt Local API first
    try {
      final response = await http.get(Uri.parse('${AppConfig.localApiUrl}/api/videos/emergency/list')).timeout(const Duration(seconds: 3));
      if (response.statusCode == 200) {
        final List data = jsonDecode(response.body);
        return data.map((json) => Video.fromJson(json)).toList();
      }
    } catch (e) {
      debugPrint('VideoRepository: Local emergency list failed - $e');
    }

    final response = await _client
        .from('videos')
        .select('*, donation_categories(name)')
        .eq('type', 'emergency')
        .order('created_at', ascending: false)
        .limit(20);
    return (response as List).map((json) => Video.fromJson(json)).toList();
  }

  /// ดึงภาพไทยมุงที่เกี่ยวข้องกับหมวดหมู่เหตุการณ์
  Future<List<Video>> getThaiMhungPhotos(String categoryId) async {
    final response = await _client
        .from('videos')
        .select()
        .eq('type', 'emergency_photo')
        .eq('category_id', categoryId)
        .order('created_at', ascending: false)
        .limit(10);
    return (response as List).map((json) => Video.fromJson(json)).toList();
  }

  /// ดึงวิดีโอตาม ID
  Future<Video?> getVideoById(String id) async {
    // Attempt Local API first
    try {
      final response = await http.get(Uri.parse('${AppConfig.localApiUrl}/api/videos/$id')).timeout(const Duration(seconds: 3));
      if (response.statusCode == 200) {
        return Video.fromJson(jsonDecode(response.body));
      }
    } catch (e) {
      debugPrint('VideoRepository: Local video info $id failed - $e');
    }

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
    // Attempt Local API first
    try {
      final response = await http.get(Uri.parse('${AppConfig.localApiUrl}/api/videos/$videoId/gps-tracks')).timeout(const Duration(seconds: 3));
      if (response.statusCode == 200) {
        final List data = jsonDecode(response.body);
        return data.map((json) => VideoGpsTrack.fromJson(json)).toList();
      }
    } catch (e) {
      debugPrint('VideoRepository: Local gps tracks failed - $e');
    }

    final response = await _client
        .from('video_gps_tracks')
        .select()
        .eq('video_id', videoId)
        .order('timestamp_offset');
    return (response as List)
        .map((json) => VideoGpsTrack.fromJson(json))
        .toList();
  }

  /// ตอบรับการช่วยเหลือเหตุการณ์ (Dual-Write: Local API + Supabase Cloud Sync)
  /// -------------------------------------------------------------------
  /// ✅ Primary Path: Local API POST /accept → Local PostgreSQL
  ///    → Sync ไปยัง Supabase Cloud ทันที (Dual-Write)
  /// ✅ Fallback Path: Supabase Cloud เท่านั้น (เมื่อ Local API ไม่ตอบสนอง)
  /// -------------------------------------------------------------------
  /// ต้องส่ง [responderId] เข้ามาเสมอตาม auth_data_guidelines.md
  /// ห้ามใช้ _client.auth.currentUser ในการดึง userId
  Future<String?> acceptIncident({
    required String videoId,
    required String responderId,
    double? latitude,
    double? longitude,
  }) async {
    // ---- Primary Path: Local API ----
    try {
      final response = await http.post(
        Uri.parse('${AppConfig.localApiUrl}/api/videos/$videoId/accept'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'responderId': responderId,
          'latitude': latitude,
          'longitude': longitude,
        }),
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final responseId = data['responseId']?.toString();

        // ✅ Dual-Write: sync ไปยัง Supabase Cloud เพื่อให้ข้อมูลตรงกัน
        // ใช้ upsert เพื่อป้องกัน duplicate (วิธีนี้ปลอดภัยกว่า insert)
        try {
          await _client.from('incident_responses').upsert({
            'video_id': videoId,
            'volunteer_id': responderId,
            'status': 'en_route',
            'accepted_at': DateTime.now().toIso8601String(),
            'volunteer_start_lat': latitude,
            'volunteer_start_lng': longitude,
          }, onConflict: 'video_id, volunteer_id');
          debugPrint('VideoRepository: ✅ Synced acceptIncident to Supabase (responseId=$responseId)');
        } catch (syncErr) {
          // Sync ล้มเหลว ไม่ใช่ error ร้ายแรง — Local API ยังทำงานปกติ
          debugPrint('VideoRepository: ⚠️ Supabase sync failed (non-critical): $syncErr');
        }

        return responseId;
      }
    } catch (e) {
      debugPrint('VideoRepository: Local acceptIncident failed → fallback to Supabase: $e');
    }

    // ---- Fallback Path: Supabase Cloud (เมื่อ Local API ไม่ตอบสนอง) ----
    try {
      final result = await _client.from('incident_responses').insert({
        'video_id': videoId,
        'volunteer_id': responderId,
        'status': 'en_route',
        'accepted_at': DateTime.now().toIso8601String(),
        'volunteer_start_lat': latitude,
        'volunteer_start_lng': longitude,
      }).select('id').single();

      debugPrint('VideoRepository: ✅ acceptIncident via Supabase fallback');
      return result['id']?.toString();
    } catch (supabaseErr) {
      debugPrint('VideoRepository: ❌ Both Local and Supabase acceptIncident failed: $supabaseErr');
    }

    return null;
  }

  /// Accept an emergency rescue job — Legacy method ใช้ Supabase โดยตรง
  /// ✅ Deprecated: ใช้ acceptIncident() แทน (รองรับ Dual-Write)
  /// คงไว้เพื่อ backward compatibility กับโค้ดเก่าที่ยังเรียกใช้อยู่
  @Deprecated('Use acceptIncident() instead. It now supports Dual-Write (Local + Supabase Sync)')
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
      if (e.toString().contains('duplicate') || e.toString().contains('unique')) {
        throw Exception('คุณได้รับงานนี้ไปแล้ว');
      }
      rethrow;
    }
  }

  /// เพิ่ม Interaction (like, gift, view)
  Future<void> addInteraction(VideoInteraction interaction) async {
    if (AppConfig.useLocalDatabase) {
      try {
        final url = Uri.parse('${AppConfig.localApiUrl}/api/videos/${interaction.videoId}/interactions');
        final response = await http.post(
          url,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(interaction.toJson()),
        ).timeout(const Duration(seconds: 3));

        if (response.statusCode == 200) {
          debugPrint('VideoRepository: Recorded interaction locally');
          return;
        }
      } catch (e) {
        debugPrint('VideoRepository: Local interaction failed, falling back to Supabase: $e');
      }
    }

    await _client.from('video_interactions').insert(interaction.toJson());
  }

  /// ดึงจำนวน Interaction สรุป
  Future<Map<String, dynamic>> getInteractionSummary(String videoId) async {
    final likes = await _client
        .from('video_interactions')
        .select('id')
        .eq('video_id', videoId)
        .eq('type', 'like');

    final gifts = await _client
        .from('video_interactions')
        .select('value')
        .eq('video_id', videoId)
        .eq('type', 'gift');

    final views = await _client
        .from('video_interactions')
        .select('id')
        .eq('video_id', videoId)
        .eq('type', 'view');

    double totalDonation = 0;
    for (final g in (gifts as List)) {
      totalDonation += (g['value'] as num? ?? 0).toDouble();
    }

    return {
      'likes': (likes as List).length,
      'donations': totalDonation,
      'views': (views as List).length,
    };
  }

  /// สร้าง RealtimeChannel สำหรับฟังเหตุการณ์ที่มีการ Insert ในตาราง video_interactions
  RealtimeChannel subscribeToInteractions(String videoId, void Function(Map<String, dynamic> payload) onInsert) {
    return _client.channel('public:video_interactions:$videoId')
      .onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'video_interactions',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'video_id',
          value: videoId,
        ),
        callback: (payload) {
          onInsert(payload.newRecord);
        },
      )
      .subscribe();
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
  Future<String?> uploadEmergencyVideo({
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
      Uri.parse('${AppConfig.localApiUrl}/api/videos/upload'),
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

    final respStr = await response.stream.bytesToString();
    final data = jsonDecode(respStr);
    return data['video']?['id']?.toString() ?? data['id']?.toString();
  }

  /// อัปโหลดภาพถ่ายแจ้งเหตุฉุกเฉินพร้อมพิกัด GPS
  /// ต้องส่ง [userId] เข้ามาเสมอตาม auth_data_guidelines.md
  /// [isThaiMhung] = true ใช้ quota 3 รูป, false ใช้ quota 5 รูป
  Future<String?> uploadEmergencyPhotos({
    required String userId,
    required List<File> photoFiles,
    required List<Map<String, dynamic>> gpsTracks,
    String? categoryId,
    bool isThaiMhung = false,
  }) async {
    if (!canUpload) {
      throw Exception("Please wait before uploading again.");
    }

    // ✅ Quota แยกตาม Mode ตามแผน §4 Thai Mhung
    final int quota = isThaiMhung ? maxThaiMhungPhotos : maxEmergencyPhotos;
    if (photoFiles.length > quota) {
      final modeName = isThaiMhung ? 'ไทยมุง' : 'Emergency';
      throw Exception("โหมด$modeName อัปโหลดรูปภาพได้สูงสุด $quota รูปต่อครั้ง");
    }

    if (photoFiles.isEmpty) {
      throw Exception("No photos provided to upload.");
    }

    markUploadStarted();

    var request = http.MultipartRequest(
      'POST',
      Uri.parse('${AppConfig.localApiUrl}/api/videos/upload-photos'),
    );

    request.fields['userId'] = userId;
    request.fields['title'] = 'Emergency Incident Photos ${DateTime.now().toIso8601String()}';
    request.fields['type'] = isThaiMhung ? 'thai_mhung_photo' : 'emergency_photo';
    // ✅ ส่ง isThaiMhung flag ไปยัง backend เพื่อ enforce quota ฝั่ง server ด้วย
    request.fields['isThaiMhung'] = isThaiMhung.toString();
    if (categoryId != null) request.fields['categoryId'] = categoryId;
    request.fields['gpsTracks'] = jsonEncode(gpsTracks);

    for (var file in photoFiles) {
      request.files.add(await http.MultipartFile.fromPath('photos', file.path));
    }

    var response = await request.send();

    if (response.statusCode != 200) {
      throw Exception("Upload failed with status ${response.statusCode}");
    }

    final respStr = await response.stream.bytesToString();
    final data = jsonDecode(respStr);
    return data['video']?['id']?.toString() ?? data['id']?.toString();
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
            video_gps_tracks(latitude, longitude, timestamp_offset)
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

        double parseDouble(dynamic value) {
          if (value == null) return 0.0;
          if (value is num) return value.toDouble();
          if (value is String) return double.tryParse(value) ?? 0.0;
          return 0.0;
        }

        final tracks = video['video_gps_tracks'] as List?;
        if (tracks != null && tracks.isNotEmpty) {
          final latestTrack = tracks.reduce((curr, next) =>
              (curr['timestamp_offset'] as int) > (next['timestamp_offset'] as int) ? curr : next);

          locations.add({
            'videoId': videoId,
            'userId': video['user_id'],
            'type': video['type'],
            'status': video['status'],
            'latitude': parseDouble(latestTrack['latitude']),
            'longitude': parseDouble(latestTrack['longitude']),
            'categoryName': 'เหตุฉุกเฉิน',
            'categoryIcon': 'warning',
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
  // acceptRescue() และ acceptIncident() ถูกรวม Dual-Write แล้ว
  // ดูที่บรรทัด ~145 ด้านบน

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
        double parseDouble(dynamic value) {
          if (value == null) return 0.0;
          if (value is num) return value.toDouble();
          if (value is String) return double.tryParse(value) ?? 0.0;
          return 0.0;
        }

        return {
          'latitude': parseDouble(response['latitude']),
          'longitude': parseDouble(response['longitude']),
        };
      }
      return null;
    } catch (e) {
      debugPrint('Error fetching emergency location: $e');
      return null;
    }
  }
  
  /// Get list of responders (volunteers) currently rushing to this incident
  Future<List<Map<String, dynamic>>> getIncidentResponders(String videoId) async {
    try {
      // Query incident_responses and join with consumer_profiles for name
      final response = await _client
          .from('incident_responses')
          .select('''
            id, volunteer_id, status, accepted_at, volunteer_start_lat, volunteer_start_lng,
            consumer_profiles!incident_responses_volunteer_id_fkey(full_name),
            user_group_roles!incident_responses_volunteer_id_fkey(
               professions(name, color_hex)
            )
          ''')
          .eq('video_id', videoId)
          .inFilter('status', ['accepted', 'arrived'])
          .order('accepted_at', ascending: true);

      final List<Map<String, dynamic>> responders = [];
      for (var row in response as List) {
        String? volunteerName;
        String? professionName;

        // Extract name
        final profile = row['consumer_profiles'];
        if (profile is Map) {
           volunteerName = profile['full_name'];
        } else if (profile is List && profile.isNotEmpty) {
           volunteerName = profile.first['full_name'];
        }

        // Extract profession
        final roles = row['user_group_roles'];
        String? professionColor;
        if (roles is List && roles.isNotEmpty) {
           final prof = roles.first['professions'];
           if (prof != null) {
              professionName = prof['name'];
              professionColor = prof['color_hex'];
           }
        }

        responders.add({
          'id': row['id'],
          'volunteerId': row['volunteer_id'],
          'status': row['status'],
          'acceptedAt': row['accepted_at'],
          'startLat': row['volunteer_start_lat'],
          'startLng': row['volunteer_start_lng'],
          'volunteerName': volunteerName ?? 'อาสาสมัคร',
          'professionName': professionName ?? 'ทีมกู้ภัย',
          'professionColor': professionColor,
        });
      }


      return responders;
    } catch (e) {
      debugPrint('Error fetching incident responders: $e');
      return [];
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
