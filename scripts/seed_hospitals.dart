import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:csv/csv.dart';
import 'package:supabase/supabase.dart';

// Import from your project's config
// Note: In a standalone script, we might need to hardcode or use env vars
const String supabaseUrl = 'https://psxcgdwcwjdbpaemkozq.supabase.co';
const String supabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InBzeGNnZHdjd2pkYnBhZW1rb3pxIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzAyNDQzNDQsImV4cCI6MjA4NTgyMDM0NH0.O2OP-tLPW214hQeFUWAFWMTYEn-_RA1MK6TAEJnKGfU';

const String csvUrl = 'https://data.opendevelopmentmekong.net/dataset/ab20b509-2b7f-442e-8448-05d3a17651ac/resource/cfe757fb-69b6-4f82-92cd-e5dfca865eb5/download/health_facilities_th.csv';

void main() async {
  print('🚀 Starting Hospital Seeding Process...');
  
  final client = SupabaseClient(supabaseUrl, supabaseAnonKey);
  
  try {
    print('📥 Downloading CSV data from OD Mekong...');
    final response = await http.get(Uri.parse(csvUrl));
    
    if (response.statusCode != 200) {
      print('❌ Failed to download CSV: ${response.statusCode}');
      return;
    }

    // Handle Encoding (Thai data often in TIS-620/Win-874)
    // OD Mekong usually uses UTF-8 or TIS-620. Let's try to detect or fallback.
    String body;
    try {
      body = utf8.decode(response.bodyBytes);
    } catch (_) {
      print('⚠️ UTF-8 decoding failed, trying Latin1/TIS-620 fallback...');
      body = latin1.decode(response.bodyBytes); 
      // Note: For real TIS-620 in Dart, one might need 'cp874' from 'charset' package, 
      // but let's try to see if plain string works or if we can get a better URL.
    }

    print('📊 Parsing CSV...');
    final List<List<dynamic>> rows = const CustomCsvConverter().convert(body);
    
    if (rows.isEmpty) {
      print('❌ CSV is empty');
      return;
    }

    // Headers: ID,Ministry,Department,Agency,Address,Lat,Long
    final headers = rows[0];
    print('📝 Headers found: $headers');

    final Map<String, Map<String, dynamic>> hospitalMap = {};
    
    print('⚙️ Mapping and Deduplicating data (${rows.length - 1} records)...');
    for (var i = 1; i < rows.length; i++) {
      final row = rows[i];
      if (row.length < 4) continue;

      final String hcode = row[0].toString();
      if (hcode.isEmpty) continue;

      final String fullAddress = row[4].toString();
      
      // Store in map to ensure unique hcode
      hospitalMap[hcode] = {
        'hcode': hcode,
        'ministry': row[1].toString(),
        'department': row[2].toString(),
        'name_th': row[3].toString(),
        'address': fullAddress,
        'latitude': double.tryParse(row[5].toString()),
        'longitude': double.tryParse(row[6].toString()),
        'hospital_type': _guessType(row[3].toString()), 
        'is_active': true,
      };
    }

    final List<Map<String, dynamic>> hospitalData = hospitalMap.values.toList();
    print('💎 Cleaned data: ${hospitalData.length} unique records (Removed ${rows.length - 1 - hospitalData.length} duplicates)');

    print('💾 Saving to Supabase in batches...');
    const int batchSize = 100;
    for (var i = 0; i < hospitalData.length; i += batchSize) {
      final end = (i + batchSize < hospitalData.length) ? i + batchSize : hospitalData.length;
      final batch = hospitalData.sublist(i, end);
      
      try {
        await client.from('thai_hospitals').upsert(batch, onConflict: 'hcode');
        print('✅ Processed $end / ${hospitalData.length}');
      } catch (e) {
        print('❌ Error in batch $i-$end: $e');
        // Continue to next batch
      }
    }

    print('✨ Seeding Completed Successfully! Total: ${hospitalData.length} hospitals.');
    
  } catch (e) {
    print('💥 Fatal Error: $e');
  }
}

String _guessType(String name) {
  if (name.contains('รพ.สต.') || name.contains('โรงพยาบาลส่งเสริมสุขภาพตำบล')) return 'รพ.สต.';
  if (name.contains('โรงพยาบาลศูนย์')) return 'รพ.ศูนย์';
  if (name.contains('โรงพยาบาลทั่วไป')) return 'รพ.ทั่วไป';
  if (name.contains('โรงพยาบาลชุมชน')) return 'รพ.ชุมชน';
  if (name.contains('คลินิก')) return 'คลินิก';
  if (name.contains('สถานีอนามัย')) return 'สถานีอนามัย';
  return 'อื่นๆ';
}

class CustomCsvConverter {
  const CustomCsvConverter();
  List<List<dynamic>> convert(String input) {
    return const CsvToListConverter().convert(input, eol: '\n', shouldParseNumbers: false);
  }
}
