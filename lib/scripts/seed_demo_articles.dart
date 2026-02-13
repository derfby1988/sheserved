import 'package:supabase/supabase.dart';
import 'dart:math';

void main() async {
  print('🚀 Starting Standalone Seed Demo Data script...');
  
  // Hardcoded config to avoid Flutter UI dependencies
  const String supabaseUrl = 'https://psxcgdwcwjdbpaemkozq.supabase.co';
  const String supabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InBzeGNnZHdjd2pkYnBhZW1rb3pxIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzAyNDQzNDQsImV4cCI6MjA4NTgyMDM0NH0.O2OP-tLPW214hQeFUWAFWMTYEn-_RA1MK6TAEJnKGfU';

  // Initialize Supabase Client
  final supabase = SupabaseClient(supabaseUrl, supabaseAnonKey);

  print('🔍 Fetching valid users for author and commenters...');
  try {
    final usersResponse = await supabase.from('users').select('id, username').limit(10);
    
    if (usersResponse == null || (usersResponse as List).isEmpty) {
      print('❌ Error: No users found in the database. Please register some users first.');
      return;
    }

    final users = (usersResponse as List);
    final authorId = users[0]['id'];
    print('✅ Found ${users.length} users. Using "${users[0]['username']}" as the primary author.');

    final categories = ['โภชนาการ', 'สมรรถภาพทางกาย', 'สุขภาพจิต', 'สุขภาพผู้หญิง', 'ความงามและผิวพรรณ', 'การแพทย์'];
    final articleTemplates = [
      {'title': '10 อาหารซูเปอร์ฟู้ดเพื่อสุขภาพหัวใจ', 'content': 'การดูแลหัวใจเริ่มต้นที่จานอาหารของคุณ...'},
      {'title': 'เทคนิคการนอนหลับให้ลึกและมีคุณภาพ', 'content': 'กุญแจสำคัญของการมีสุขภาพดีคือการนอน...'},
      {'title': 'โยคะ 15 นาที แก้ไขอาการออฟฟิศซินโดรม', 'content': 'หากคุณต้องนั่งทำงานท่าเดิมนานๆ ลองทำตามท่าเหล่านี้...'},
      {'title': 'ความลับของผิวใสด้วยวิตามินซีธรรมชาติ', 'content': 'วิตามินซีมีบทบาทสำคัญต่อการสร้างคอลลาเจน...'},
      {'title': 'วิธีจัดการความเครียดในวัยทำงานอย่างยั่งยืน', 'content': 'ความเครียดสะสมสามารถส่งผลต่อสุขภาพระยะยาว...'},
      {'title': 'ทำไมการดื่มน้ำให้เพียงพอถึงเปลี่ยนชีวิตคุณได้', 'content': 'ร่างกายเราประกอบด้วยน้ำเป็นส่วนใหญ่...'},
      {'title': 'การวิ่งมาราธอนครั้งแรก: คู่มือการเตรียมตัว', 'content': 'การเตรียมความพร้อมทั้งร่างกายและจิตใจเป็นสิ่งสำคัญ...'},
      {'title': 'ความเชื่อผิดๆ เกี่ยวกับการลดน้ำหนักที่ควรเลิก', 'content': 'อย่าหลงเชื่อสูตรลดน้ำหนักที่ฟังดูดีเกินจริง...'},
      {'title': 'ประโยชน์ของอาหารหมักดองต่อระบบขับถ่าย', 'content': 'โปรไบโอติกในอาหารหมักช่วยปรับสมดุลลำไส้...'},
      {'title': 'วิธีตรวจเช็คสุขภาพเบื้องต้นด้วยตัวเองที่บ้าน', 'content': 'สังเกตสัญญาณเตือนจากร่างกายก่อนจะลุกลาม...'},
    ];

    final commentTemplates = [
      'ข้อมูลมีประโยชน์มากเลยค่ะ ขอบคุณที่แบ่งปันนะคะ',
      'ลองทำตามดูแล้ว ได้ผลดีจริงๆ ครับ',
      'มีคำถามเพิ่มเติมเกี่ยวกับส่วนนี้ครับ...',
      'บทความอ่านง่ายและเข้าใจได้ทันทีเลย ชอบมากค่ะ',
      'อยากให้มีบทความภาคต่อเกี่ยวกับเรื่องนี้จัง',
      'เป็นความรู้ใหม่ที่ผมไม่เคยรู้มาก่อนเลย ขอบคุณครับ',
      'แชร์ให้เพื่อนๆ อ่านเรียบร้อยแล้วครับ มีประโยชน์มาก',
      'กำลังหาวิธีแก้เรื่องนี้พอดีเลย เจอในบทความนี้ครบเลยค่ะ',
    ];

    print('📝 Generating 20 articles...');
    final Random random = Random();
    
    for (int i = 1; i <= 20; i++) {
      final template = articleTemplates[i % articleTemplates.length];
      final now = DateTime.now().subtract(Duration(days: i, hours: random.nextInt(24))).toIso8601String();
      
      // Insert Article
      final articleInsert = await supabase.from('health_articles').insert({
        'title': '${template['title']} #${i}',
        'content': '${template['content']} นี่คือเนื้อหาจำลองเพิ่มเติมสำหรับบทความที่ $i เพื่อให้บทความมีความยาวและความน่าสนใจ โดยเน้นสาระสำคัญในการดูแลสุขภาพอย่างถูกวิธี...',
        'author_id': authorId,
        'category': categories[random.nextInt(categories.length)],
        'view_count': 50 + random.nextInt(500),
        'like_count': 0,
        'image_url': 'https://picsum.photos/seed/art$i/800/600',
        'created_at': now,
        'updated_at': now,
      }).select('id');

      if (articleInsert == null || (articleInsert as List).isEmpty) {
        print('⚠️ Failed to insert article $i');
        continue;
      }

      final String articleId = articleInsert[0]['id'];
      print('✅ Article $i inserted (ID: $articleId)');

      // Generate 2-4 comments for this article
      final numComments = 2 + random.nextInt(3);
      final List<Map<String, dynamic>> commentsData = [];
      
      for (int j = 1; j <= numComments; j++) {
        final commenter = users[random.nextInt(users.length)];
        final commentTime = DateTime.parse(now).add(Duration(hours: j * 2)).toIso8601String();
        
        commentsData.add({
          'article_id': articleId,
          'user_id': commenter['id'],
          'content': commentTemplates[random.nextInt(commentTemplates.length)],
          'comment_number': j,
          'created_at': commentTime,
          'like_count': random.nextInt(10),
        });
      }

      await supabase.from('health_article_comments').insert(commentsData);
      print('   💬 Added $numComments comments to article $i');
    }

    print('⭐ Seeding process completed successfully!');
    
  } catch (e) {
    print('❌ A critical error occurred: $e');
  }
}
