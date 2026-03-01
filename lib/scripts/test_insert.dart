import 'package:supabase/supabase.dart';
import 'dart:io';

void main() async {
  const String supabaseUrl = 'https://psxcgdwcwjdbpaemkozq.supabase.co';
  const String supabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InBzeGNnZHdjd2pkYnBhZW1rb3pxIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzAyNDQzNDQsImV4cCI6MjA4NTgyMDM0NH0.O2OP-tLPW214hQeFUWAFWMTYEn-_RA1MK6TAEJnKGfU';

  final supabase = SupabaseClient(supabaseUrl, supabaseAnonKey);

  try {
    print('Testing insert into health_article_products...');
    // Just try inserting a dummy product to a dummy article id (must be valid article_id though, or it'll fail FK)
    final articlesResponse = await supabase.from('health_articles').select('id').limit(1);
    final articleId = articlesResponse[0]['id'];
    
    await supabase.from('health_article_products').insert({
      'article_id': articleId,
      'name': 'Test',
      'tag_type': 'medication',
      'is_approved': true,
    });
    print('Insert successful!');
  } catch (e) {
    print('❌ Error: $e');
  }
  exit(0);
}
