import 'package:supabase/supabase.dart';
import 'dart:math';

void main() async {
  print('🚀 Starting Product Seeding script...');
  
  const String supabaseUrl = 'https://psxcgdwcwjdbpaemkozq.supabase.co';
  const String supabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InBzeGNnZHdjd2pkYnBhZW1rb3pxIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzAyNDQzNDQsImV4cCI6MjA4NTgyMDM0NH0.O2OP-tLPW214hQeFUWAFWMTYEn-_RA1MK6TAEJnKGfU';

  final supabase = SupabaseClient(supabaseUrl, supabaseAnonKey);

  try {
    print('🔍 Fetching articles...');
    final articlesResponse = await supabase.from('health_articles').select('id, category');
    
    if (articlesResponse == null || (articlesResponse as List).isEmpty) {
      print('❌ No articles found. Please run seed_demo_articles.dart first.');
      return;
    }

    final articles = (articlesResponse as List);
    print('✅ Found ${articles.length} articles.');

    final productTemplates = {
      'โภชนาการ': [
        {'name': 'เวย์โปรตีน Isolate พรีเมียม', 'url': 'https://example.com/whey'},
        {'name': 'วิตามินซีคอมเพล็กซ์ 1000mg', 'url': 'https://example.com/vitc'},
        {'name': 'น้ำมันปลา Omega-3 เข้มข้น', 'url': 'https://example.com/fishoil'},
      ],
      'สมรรถภาพทางกาย': [
        {'name': 'รองเท้าวิ่งรองรับแรงกระแทก', 'url': 'https://example.com/shoes'},
        {'name': 'เสื่อโยคะแบบกันลื่นพิเศษ', 'url': 'https://example.com/yoga-mat'},
        {'name': 'เครื่องวัดอัตราการเต้นของหัวใจ', 'url': 'https://example.com/heart-monitor'},
      ],
      'สุขภาพจิต': [
        {'name': 'น้ำมันหอมระเหยลาเวนเดอร์', 'url': 'https://example.com/lavender'},
        {'name': 'เทียนหอมอโรมาเธอราพี', 'url': 'https://example.com/candle'},
        {'name': 'หูฟังตัดเสียงรบกวน', 'url': 'https://example.com/headphones'},
      ],
      'ความงามและผิวพรรณ': [
        {'name': 'เซรั่มไฮยาลูรอนิกแอซิด', 'url': 'https://example.com/hyaluron'},
        {'name': 'ครีมกันแดด SPF50+ PA++++', 'url': 'https://example.com/sunscreen'},
        {'name': 'มอยส์เจอไรเซอร์สูตรอ่อนโยน', 'url': 'https://example.com/moisturizer'},
      ],
      'สุขภาพผู้หญิง': [
        {'name': 'อาหารเสริมธาตุเหล็กและโฟเลต', 'url': 'https://example.com/iron'},
        {'name': 'แผ่นประคบร้อนแก้ปวดประจำเดือน', 'url': 'https://example.com/heat-pad'},
        {'name': 'เจลทำความสะอาดจุดซ่อนเร้น', 'url': 'https://example.com/cleanser'},
      ],
      'การแพทย์': [
        {'name': 'เครื่องวัดความดันระบบดิจิทัล', 'url': 'https://example.com/blood-pressure'},
        {'name': 'ปรอทวัดไข้แบบอินฟราเรด', 'url': 'https://example.com/thermometer'},
        {'name': 'หน้ากากอนามัยมาตรฐาน N95', 'url': 'https://example.com/mask'},
      ],
    };

    final Random random = Random();
    int productsAdded = 0;

    print('📦 Seeding products for each article...');
    for (var article in articles) {
      final articleId = article['id'];
      final category = article['category'] ?? 'โภชนาการ';
      
      final templates = productTemplates[category] ?? productTemplates['โภชนาการ']!;
      final numToAdd = 1 + random.nextInt(3); // 1-3 products
      
      final List<Map<String, dynamic>> productsData = [];
      for (int i = 0; i < numToAdd; i++) {
        final template = templates[random.nextInt(templates.length)];
        productsData.add({
          'article_id': articleId,
          'name': template['name'],
          'url': template['url'],
          'image_url': 'https://picsum.photos/seed/prod${random.nextInt(1000)}/300/300',
          'tag_type': 'author',
          'is_approved': true,
        });
      }

      await supabase.from('health_article_products').insert(productsData);
      productsAdded += numToAdd;
      print('   ✅ Added $numToAdd products to article: ${articleId.substring(0,8)}...');
    }

    print('⭐ Successfully added $productsAdded products in total!');
    
  } catch (e) {
    print('❌ Error: $e');
  }
}
