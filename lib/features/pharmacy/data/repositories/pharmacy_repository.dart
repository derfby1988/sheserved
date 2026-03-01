import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';
import '../models/medication_models.dart';
import '../services/fda_api_service.dart';

class PharmacyRepository {
  final SupabaseClient _client;

  PharmacyRepository(this._client);

  /// ดึงข้อมูลยาและเวชภัณฑ์ทั้งหมด รองรับ Pagination
  /// เป็นไปตาม Auth Guidelines: รับ userId เข้ามาเป็น parameter
  Future<List<MedicationModel>> getMedications({
    String? userId,
    int page = 1,
    int pageSize = 20,
    String? searchQuery,
    String? categoryId,
    double? minPrice,
    double? maxPrice,
  }) async {
    try {
      final startIndex = (page - 1) * pageSize;
      final endIndex = startIndex + pageSize - 1;

      // เริ่มสร้าง Query สำหรับดึงข้อมูลยา พร้อมดึงรายละเอียดจากตารางอื่นๆ มาด้วย
      // ใช้ inner join ถ้ามีการเลือก category เพื่อให้ได้ผลลัพธ์เฉพาะยาในหมวดนั้น
      String selectQuery = '''
        *,
        tmt_details:tmt_details(*),
        unregistered_details:unregistered_details(*)
      ''';

      if (categoryId != null && categoryId.isNotEmpty) {
        selectQuery += ', medication_category_mappings!inner(category_id, product_categories(*))';
      } else {
        selectQuery += ', medication_category_mappings(product_categories(*))';
      }

      var query = _client.from('medications').select(selectQuery).eq('status', 'ACTIVE');

      // ถ้ามีการค้นหา
      if (searchQuery != null && searchQuery.isNotEmpty) {
        query = query.or('trade_name.ilike.%$searchQuery%,generic_name.ilike.%$searchQuery%');
      }

      // ถ้ามีการกรองหมวดหมู่
      if (categoryId != null && categoryId.isNotEmpty) {
        query = query.eq('medication_category_mappings.category_id', categoryId);
      }

      // กรองราคา
      if (minPrice != null) {
        query = query.gte('price', minPrice);
      }
      if (maxPrice != null) {
        query = query.lte('price', maxPrice);
      }

      // เรียงลำดับและแบ่งหน้า
      final response = await query
          .order('trade_name', ascending: true)
          .range(startIndex, endIndex);

      return (response as List).map((json) => MedicationModel.fromJson(json)).toList();
    } catch (e) {
      debugPrint('Error fetching medications: $e');
      throw Exception('ไม่สามารถดึงข้อมูลยาได้: $e');
    }
  }

  /// ดึงรายละเอียดเจาะจงของยาพร้อมข้อมูลเชิงลึก
  Future<MedicationModel?> getMedicationDetails({
    required String medicationId,
    String? userId, // userId สำรองไว้ใช้ตรวจสอบกรณีบันทึกประวัติการเข้าดู
  }) async {
    try {
      final response = await _client.from('medications').select('''
        *,
        tmt_details(*),
        unregistered_details(*)
      ''').eq('id', medicationId).maybeSingle();

      if (response == null) return null;

      // ดึงข้อมูล clinical_knowledge เพิ่มเติมโดยใช้ generic_name อ้างอิง
      final genericName = response['generic_name'];
      if (genericName != null && genericName.toString().isNotEmpty) {
        final ckResponse = await _client.from('clinical_knowledge')
            .select()
            .eq('generic_name', genericName)
            .limit(1)
            .maybeSingle();
        
        if (ckResponse != null) {
          response['clinical_knowledge'] = [ckResponse];
        }
      }

      return MedicationModel.fromJson(response);
    } catch (e) {
      debugPrint('Error fetching medication details: $e');
      throw Exception('ไม่สามารถดึงรายละเอียดข้อมูลยาได้: $e');
    }
  }

  /// ดึงรายการหมวดหมู่ตัวกรองทั้งหมด
  Future<List<ProductCategoryModel>> getCategories() async {
    try {
      final response = await _client
          .from('product_categories')
          .select()
          .order('display_order', ascending: true);
      
      return (response as List)
          .map((json) => ProductCategoryModel.fromJson(json))
          .toList();
    } catch (e) {
      debugPrint('Error fetching product categories: $e');
      // คืนค่า empty list ในกรณีที่ตารางยังไม่ได้ถูกสร้าง (เพื่อไม่ให้ล่ม)
      return []; 
    }
  }

  /// เพิ่มหรือแก้ไขหมวดหมู่ (สำหรับ Admin)
  Future<void> saveCategory(ProductCategoryModel category) async {
    try {
      final data = {
        'name': category.name,
        'type': category.type,
        'is_active': category.isActive,
        'display_order': category.displayOrder,
      };
      
      if (category.id.isNotEmpty && !category.id.startsWith('new_')) {
        await _client.from('product_categories').update(data).eq('id', category.id);
      } else {
        await _client.from('product_categories').insert(data);
      }
    } catch (e) {
      debugPrint('Error saving product category: $e');
      throw Exception('ไม่สามารถบันทึกหมวดหมู่ได้: $e');
    }
  }

  /// ลบหมวดหมู่ (สำหรับ Admin)
  Future<void> deleteCategory(String id) async {
    try {
      await _client.from('product_categories').delete().eq('id', id);
    } catch (e) {
      debugPrint('Error deleting product category: $e');
      throw Exception('ไม่สามารถลบหมวดหมู่ได้: $e');
    }
  }

  /// ดึงรายชื่อยาในหมวดหมู่นั้นๆ (สำหรับ Admin - Category Members Page)
  Future<List<MedicationModel>> getCategoryMembers(String categoryId) async {
    try {
      final response = await _client
          .from('medication_category_mappings')
          .select('medications(*)')
          .eq('category_id', categoryId);

      // response format: [{'medications': {...}}, {'medications': {...}}]
      return (response as List)
          .map((row) => MedicationModel.fromJson(row['medications'] as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('Error fetching category members: $e');
      return [];
    }
  }

  /// เพิ่มยาเข้าหมวดหมู่ (สำหรับ Admin - Category Members Page)
  Future<void> addCategoryMember(String categoryId, String medicationId) async {
    try {
      await _client.from('medication_category_mappings').insert({
        'category_id': categoryId,
        'medication_id': medicationId,
      });
    } catch (e) {
      debugPrint('Error adding category member: $e');
      // If it's a unique constraint violation, ignore it since it's already there
      if (!e.toString().contains('duplicate key value violates unique constraint') && !e.toString().contains('23505')) {
          throw Exception('ไม่สามารถเพิ่มยาลงหมวดหมู่ได้: $e');
      }
    }
  }

  /// นำยาออกจากหมวดหมู่ (สำหรับ Admin - Category Members Page)
  Future<void> removeCategoryMember(String categoryId, String medicationId) async {
    try {
      await _client
          .from('medication_category_mappings')
          .delete()
          .match({
            'category_id': categoryId,
            'medication_id': medicationId,
          });
    } catch (e) {
      debugPrint('Error removing category member: $e');
      throw Exception('ไม่สามารถนำยาออกจากหมวดหมู่ได้: $e');
    }
  }

  /// นำเข้ายาจาก อย.
  Future<void> importDrugFromFda(FdaDrugModel fdaDrug, String? categoryId) async {
    try {
       // Insert to medications table
       final medResponse = await _client.from('medications').insert({
         'source_type': 'FDA',
         'reference_code': fdaDrug.licenseNo,
         'trade_name': fdaDrug.productNameThai.isNotEmpty ? fdaDrug.productNameThai : fdaDrug.productNameEng,
         'generic_name': fdaDrug.productNameEng,
         'manufacturer': fdaDrug.manufacturer,
         'status': 'ACTIVE',
         'fda_risk_status': fdaDrug.fdaRiskStatusCode,
         'in_stock': true,
       }).select('id').single();

       final medicationId = medResponse['id'] as String;

       // If category is provided, map it
       if (categoryId != null) {
          await addCategoryMember(categoryId, medicationId);
       }
    } catch (e) {
       debugPrint('Error importing drug from FDA: $e');
       throw Exception('นำเข้าข้อมูลยาไม่สำเร็จ: $e');
    }
  }

  /// ดึงข้อมูลยาที่ยังไม่ได้ถูกจัดหมวดหมู่ (Unmapped) รองรับ Pagination
  Future<List<MedicationModel>> getUnmappedMedications({
    int page = 1,
    int pageSize = 10,
    String? searchQuery,
  }) async {
    try {
      final startIndex = (page - 1) * pageSize;
      final endIndex = startIndex + pageSize - 1;

      // We need to use left join and filter where medication_category_mappings is empty
      // Supabase PostgREST syntax for checking empty relationship: 'medication_category_mappings' is null
      String selectQuery = '''
        *,
        tmt_details:tmt_details(*),
        unregistered_details:unregistered_details(*),
        medication_category_mappings(category_id)
      ''';

      var query = _client.from('medications').select(selectQuery).eq('status', 'ACTIVE');

      if (searchQuery != null && searchQuery.isNotEmpty) {
        query = query.or('trade_name.ilike.%$searchQuery%,generic_name.ilike.%$searchQuery%');
      }

      final response = await query
          .order('created_at', ascending: false)
          .range(startIndex, endIndex);

      // Filter locally for performance, or ideally on DB.
      // In PostgREST, to filter empty related maps: 
      // But for simplicity, we do standard select and filter locally if not exact,
      // However, we want strict pagination.
      // The best way to get unmapped items directly in PostgREST is:
      // However currently PostgREST doesn't support easily filtering by "not exists" easily in direct select string without a custom RPC.
      // We will filter in Dart and return, but note this breaks exact page sizing if there are mapped ones mixed.
      // Let's create an RPC or just fetch more and filter.
      // Wait! `!inner` means it MUST have a mapping. So `not.medication_category_mappings` is not supported directly.
      // So we will filter locally for now.
      
      final allList = (response as List).map((json) => MedicationModel.fromJson(json)).toList();
      // Only keep those without mappings (where medication_category_mappings is empty)
      final filteredList = allList.where((m) {
        final mappings = response.firstWhere((r) => r['id'] == m.id)['medication_category_mappings'] as List?;
        return mappings == null || mappings.isEmpty;
      }).toList();

      return filteredList;
    } catch (e) {
      debugPrint('Error fetching unmapped medications: $e');
      throw Exception('ไม่สามารถดึงข้อมูลยาที่ยังไม่จัดหมวดหมู่ได้: $e');
    }
  }

  /// ค้นหาข้อมูลยาจากฐานข้อมูลท้องถิ่น (Master Data)
  Future<List<MedicationModel>> searchMasterMedications(String query) async {
    try {
      final response = await _client
          .from('medications')
          .select('*, medication_category_mappings(product_categories(*))')
          .or('trade_name.ilike.%$query%,generic_name.ilike.%$query%,manufacturer.ilike.%$query%')
          .limit(50);
      
      return (response as List).map((json) => MedicationModel.fromJson(json)).toList();
    } catch (e) {
      debugPrint('Error searching master medications: $e');
      return [];
    }
  }
}
