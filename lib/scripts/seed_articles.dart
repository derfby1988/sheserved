import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/app_config.dart';

void main() async {
  print('Initializing Supabase...');
  // We need to use a simple client for script
  final supabase = SupabaseClient(AppConfig.supabaseUrl, AppConfig.supabaseAnonKey);

  print('Fetching existing articles to find a valid author_id...');
  final articlesResponse = await supabase.from('health_articles').select('author_id').limit(1);
  
  String? authorId;
  if (articlesResponse != null && (articlesResponse as List).isNotEmpty) {
    authorId = articlesResponse[0]['author_id'];
    print('Found existing author_id: $authorId');
  } else {
    print('No articles found, fetching first user...');
    final usersResponse = await supabase.from('users').select('id').limit(1);
    if (usersResponse != null && (usersResponse as List).isNotEmpty) {
      authorId = usersResponse[0]['id'];
      print('Found user_id to use as author: $authorId');
    }
  }

  if (authorId == null) {
    print('Error: Could not find a valid user to assign as author. Please create a user first.');
    return;
  }

  print('Generating 40 mock articles...');
  final categories = ['โภชนาการ', 'สมรรถภาพทางกาย', 'สุขภาพจิต', 'สุขภาพผู้หญิง', 'ความงามและผิวพรรณ', 'การแพทย์'];
  final titles = [
    'วิตามินที่จำเป็นสำหรับวัยทำงาน',
    'วิธีลดน้ำหนักแบบยั่งยืน',
    'การดูแลหัวใจด้วยการเดิน',
    'สมุนไพรไทยแก้เจ็บคอร้อนใน',
    'เทคนิคการหายใจลดความเครียด',
    'สัญญาณเตือนโรคมะเร็ง',
    'การกินแบบ Intermittent Fasting (IF)',
    'โปรตีนพืช vs โปรตีนสัตว์',
    'การดูแลสายตาจากหน้าจอคอมพิวเตอร์',
    'วิธีเลือกครีมกันแดดให้เหมาะกับผิว',
  ];

  final List<Map<String, dynamic>> mockData = [];
  for (int i = 1; i <= 40; i++) {
    final now = DateTime.now().subtract(Duration(days: i)).toIso8601String();
    mockData.add({
      'title': '${titles[i % titles.length]} (Vol. ${i ~/ 10 + 1}) #$i',
      'content': 'เนื้อหาจำลองสำหรับบทความเรื่อง ${titles[i % titles.length]} ลำดับที่ $i... การดูแลสุขภาพเป็นสิ่งสำคัญที่คุณควรใส่ใจทุกวัน...',
      'author_id': authorId,
      'category': categories[i % categories.length],
      'view_count': 100 + (i * 20),
      'like_count': 10 + (i % 30),
      'image_url': 'https://picsum.photos/seed/art$i/800/600',
      'created_at': now,
      'updated_at': now,
    });
  }

  print('Inserting 40 articles into health_articles table...');
  try {
    await supabase.from('health_articles').insert(mockData);
    print('Successfully inserted 40 mock articles!');
  } catch (e) {
    print('Error inserting articles: $e');
  }
}
