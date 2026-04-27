import 'package:supabase/supabase.dart';
import 'dart:convert';

void main() async {
  final supabaseUrl = 'https://psxcgdwcwjdbpaemkozq.supabase.co';
  final supabaseKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InBzeGNnZHdjd2pkYnBhZW1rb3pxIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzAyNDQzNDQsImV4cCI6MjA4NTgyMDM0NH0.O2OP-tLPW214hQeFUWAFWMTYEn-_RA1MK6TAEJnKGfU';
  final client = SupabaseClient(supabaseUrl, supabaseKey);

  final videoId = 'bad3a79a-7a0c-472a-942f-17f202f79adc';
  
  // step 2
  final response1 = await client
      .from('thai_mhung_photos')
      .select()
      .eq('video_id', videoId)
      .order('created_at', ascending: true);
  
  print('Table response1 length: \${response1.length}');

  // step 3
  final incidentVideo = await client
      .from('videos')
      .select('category_id')
      .eq('id', videoId)
      .maybeSingle();
      
  final incidentCategoryId = incidentVideo?['category_id']?.toString();
  print('Category ID: \$incidentCategoryId');

  final response2 = await client
      .from('videos')
      .select()
      .eq('type', 'thai_mhung_photo')
      .eq('category_id', incidentCategoryId)
      .order('created_at', ascending: true)
      .limit(30);
      
  final allResults = List<Map<String, dynamic>>.from(response2);
  
  final List<Map<String, dynamic>> photos = [];
  for (final v in allResults) {
    var photoUrlsRaw = v['photo_urls'];
    List<String> photoUrls = [];
    if (photoUrlsRaw is List) {
      photoUrls = photoUrlsRaw.map((u) => u.toString()).toList();
    } else if (photoUrlsRaw is String) {
      try { photoUrls = List<String>.from(jsonDecode(photoUrlsRaw)); } catch (_) {}
    }
    
    if (photoUrls.isNotEmpty) {
      for (int i = 0; i < photoUrls.length; i++) {
        photos.add({
          'id': '\${v['id']}_\$i',
          'photo_url': photoUrls[i],
        });
      }
    } else {
      final url = v['bunny_url'] ?? v['thumbnail_url'] ?? '';
      if (url.toString().isNotEmpty) {
        photos.add({
          'id': v['id'],
          'photo_url': url.toString(),
        });
      }
    }
  }
  
  print('Photos extracted: \${photos.length}');
  for (var p in photos) {
    print('- \${p['id']}: \${p['photo_url']}');
  }
}
