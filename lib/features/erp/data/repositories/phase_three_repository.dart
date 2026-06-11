import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/employee.dart';
import '../models/gl_entry.dart';
import '../models/dashboard_snapshot.dart';

/// Repository สำหรับ ERP Phase 3 — Finance & Operations + Read Model
class PhaseThreeRepository {
  final SupabaseClient _client;

  PhaseThreeRepository(this._client);

  // ========================
  // EMPLOYEES (HR Core)
  // ========================

  Future<List<Employee>> getEmployees(String professionId) async {
    try {
      final response = await _client
          .from('employees')
          .select()
          .eq('profession_id', professionId)
          .eq('is_active', true)
          .order('full_name');
      return (response as List)
          .map((e) => Employee.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e, st) {
      debugPrint('[Phase3Repo] getEmployees error: $e');
      return [];
    }
  }

  Future<Employee?> createEmployee(Map<String, dynamic> data) async {
    try {
      final response = await _client
          .from('employees')
          .insert(data)
          .select()
          .single();
      return Employee.fromJson(response as Map<String, dynamic>);
    } catch (e, st) {
      debugPrint('[Phase3Repo] createEmployee error: $e');
      return null;
    }
  }

  // ========================
  // GL ENTRIES (Accounting Core)
  // ========================

  Future<List<GlEntry>> getGlEntries(String professionId, {int limit = 50}) async {
    try {
      final response = await _client
          .from('gl_entries')
          .select()
          .eq('profession_id', professionId)
          .order('created_at', ascending: false)
          .limit(limit);
      return (response as List)
          .map((e) => GlEntry.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e, st) {
      debugPrint('[Phase3Repo] getGlEntries error: $e');
      return [];
    }
  }

  Future<bool> createGlFromOrder(String orderId) async {
    try {
      final response = await _client.rpc(
        'create_gl_from_order',
        params: {'p_order_id': orderId},
      );
      return response as bool? ?? false;
    } catch (e, st) {
      debugPrint('[Phase3Repo] createGlFromOrder error: $e');
      return false;
    }
  }

  // ========================
  // DASHBOARD SNAPSHOTS (Read Model)
  // ========================

  Future<List<DashboardSnapshot>> getDashboardSnapshots(
    String professionId, {
    String type = 'daily',
    int limit = 30,
  }) async {
    try {
      final response = await _client
          .from('dashboard_snapshots')
          .select()
          .eq('profession_id', professionId)
          .eq('snapshot_type', type)
          .order('snapshot_date', ascending: false)
          .limit(limit);
      return (response as List)
          .map((e) => DashboardSnapshot.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e, st) {
      debugPrint('[Phase3Repo] getDashboardSnapshots error: $e');
      return [];
    }
  }

  Future<String?> upsertDashboardSnapshot({
    required String professionId,
    required String type,
    required Map<String, dynamic> metrics,
  }) async {
    try {
      final response = await _client.rpc(
        'upsert_dashboard_snapshot',
        params: {
          'p_profession_id': professionId,
          'p_snapshot_type': type,
          'p_metrics': metrics,
        },
      );
      return response as String?;
    } catch (e, st) {
      debugPrint('[Phase3Repo] upsertDashboardSnapshot error: $e');
      return null;
    }
  }
}
