import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/video_models.dart';

/// Repository สำหรับจัดการข้อมูลวิดีโอ
class VideoRepository {
  final SupabaseClient _client;

  VideoRepository(this._client);

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
}
