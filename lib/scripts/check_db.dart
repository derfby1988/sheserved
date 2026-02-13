import 'package:supabase/supabase.dart';

void main() async {
  final client = SupabaseClient(
    'https://psxcgdwcwjdbpaemkozq.supabase.co', 
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InBzeGNnZHdjd2pkYnBhZW1rb3pxIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzAyNDQzNDQsImV4cCI6MjA4NTgyMDM0NH0.O2OP-tLPW214hQeFUWAFWMTYEn-_RA1MK6TAEJnKGfU'
  );
  try {
    final response = await client.from('health_articles').select('id').limit(100);
    if (response != null) {
      print('Found ${(response as List).length} articles.');
    } else {
      print('No response from Supabase.');
    }
  } catch (e) {
    print('Error: $e');
  }
}
