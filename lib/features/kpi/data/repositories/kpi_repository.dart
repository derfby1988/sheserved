import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/kpi_models.dart';

class KpiRepository {
  final SupabaseClient _client;

  KpiRepository(this._client);

  // ========================
  // KPI Targets
  // ========================

  /// ดึงเป้าหมายทั้งหมดของ profession (รองรับ branch filter)
  Future<List<KpiTarget>> getKpiTargets({
    required String professionId,
    String? branchId,
    String? employeeId,
    String? targetType,
    String? periodType,
    int page = 1,
    int pageSize = 50,
  }) async {
    var query = _client
        .from('kpi_targets')
        .select()
        .eq('profession_id', professionId);

    if (branchId != null) {
      query = query.eq('branch_id', branchId);
    }
    if (employeeId != null) {
      query = query.eq('employee_id', employeeId);
    }
    if (targetType != null) {
      query = query.eq('target_type', targetType);
    }
    if (periodType != null) {
      query = query.eq('period_type', periodType);
    }

    final start = (page - 1) * pageSize;
    final end = start + pageSize - 1;
    final response = await query.order('start_date', ascending: false).range(start, end);

    return (response as List<dynamic>)
        .map((e) => KpiTarget.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  /// สร้างเป้าหมายใหม่
  Future<KpiTarget> createKpiTarget(KpiTarget target) async {
    final response = await _client
        .from('kpi_targets')
        .insert(target.toMap())
        .select()
        .single();
    return KpiTarget.fromMap(response);
  }

  /// อัปเดตเป้าหมาย
  Future<KpiTarget> updateKpiTarget(String id, Map<String, dynamic> updates) async {
    final response = await _client
        .from('kpi_targets')
        .update(updates)
        .eq('id', id)
        .select()
        .single();
    return KpiTarget.fromMap(response);
  }

  /// ลบเป้าหมาย
  Future<void> deleteKpiTarget(String id) async {
    await _client.from('kpi_targets').delete().eq('id', id);
  }

  // ========================
  // KPI Actuals (Read Model)
  // ========================

  /// ดึง actuals สำหรับแสดง Dashboard
  Future<List<KpiActual>> getKpiActuals({
    required String professionId,
    String? branchId,
    String? employeeId,
    String? targetType,
    String? periodType,
    DateTime? periodStart,
    int limit = 100,
  }) async {
    var query = _client
        .from('kpi_actuals')
        .select()
        .eq('profession_id', professionId);

    if (branchId != null) {
      query = query.eq('branch_id', branchId);
    }
    if (employeeId != null) {
      query = query.eq('employee_id', employeeId);
    }
    if (targetType != null) {
      query = query.eq('target_type', targetType);
    }
    if (periodType != null) {
      query = query.eq('period_type', periodType);
    }
    if (periodStart != null) {
      query = query.gte('period_start', periodStart.toIso8601String().split('T').first);
    }

    final response = await query
        .order('period_start', ascending: false)
        .limit(limit);

    return (response as List<dynamic>)
        .map((e) => KpiActual.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  /// ดึง summary สำหรับ Dashboard (ยอดรวมตาม period)
  Future<KpiDashboardSummary> getDashboardSummary({
    required String professionId,
    String? branchId,
    required String targetType,
    required String periodType,
    DateTime? periodStart,
  }) async {
    var query = _client
        .from('kpi_actuals')
        .select('actual_amount, target_amount, last_refresh_at')
        .eq('profession_id', professionId)
        .eq('target_type', targetType)
        .eq('period_type', periodType);

    if (branchId != null) {
      query = query.eq('branch_id', branchId);
    }
    if (periodStart != null) {
      query = query.eq('period_start', periodStart.toIso8601String().split('T').first);
    }

    final response = await query;
    final rows = (response as List<dynamic>);

    double totalActual = 0;
    double totalTarget = 0;
    DateTime? latestRefresh;

    for (final row in rows) {
      totalActual += (row['actual_amount'] as num?)?.toDouble() ?? 0;
      totalTarget += (row['target_amount'] as num?)?.toDouble() ?? 0;
      final refreshRaw = row['last_refresh_at'];
      if (refreshRaw != null) {
        final dt = DateTime.tryParse(refreshRaw as String);
        if (dt != null && (latestRefresh == null || dt.isAfter(latestRefresh))) {
          latestRefresh = dt;
        }
      }
    }

    final achievementRate = totalTarget > 0
        ? (totalActual / totalTarget * 100).clamp(0, 999.99)
        : 0.0;

    return KpiDashboardSummary(
      targetType: targetType,
      periodType: periodType,
      totalActual: totalActual,
      totalTarget: totalTarget,
      overallAchievementRate: achievementRate,
      recordCount: rows.length,
      lastRefreshAt: latestRefresh,
    );
  }

  // ========================
  // Alert Thresholds
  // ========================

  /// ดึงเกณฑ์การแจ้งเตือนของ profession
  Future<List<KpiAlertThreshold>> getAlertThresholds({
    required String professionId,
  }) async {
    final response = await _client
        .from('kpi_alert_thresholds')
        .select()
        .eq('profession_id', professionId);

    return (response as List<dynamic>)
        .map((e) => KpiAlertThreshold.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  /// อัปเดตเกณฑ์การแจ้งเตือน
  Future<KpiAlertThreshold> updateAlertThreshold(
    String id,
    Map<String, dynamic> updates,
  ) async {
    final response = await _client
        .from('kpi_alert_thresholds')
        .update(updates)
        .eq('id', id)
        .select()
        .single();
    return KpiAlertThreshold.fromMap(response);
  }

  // ========================
  // Refresh Function (RPC)
  // ========================

  /// เรียก refresh_kpi_actuals() ผ่าน Supabase RPC
  Future<Map<String, int>> refreshKpiActuals({
    required String professionId,
    String periodType = 'daily',
    int lookbackDays = 30,
    String targetType = 'revenue',
  }) async {
    try {
      final response = await _client.rpc(
        'refresh_kpi_actuals',
        params: {
          'p_profession_id': professionId,
          'p_period_type': periodType,
          'p_lookback_days': lookbackDays,
          'p_target_type': targetType,
        },
      );
      // Response is a table result; parse inserted/updated
      if (response is List && response.isNotEmpty) {
        final row = response.first as Map<String, dynamic>?;
        if (row != null) {
          return {
            'inserted': (row['inserted'] as num?)?.toInt() ?? 0,
            'updated': (row['updated'] as num?)?.toInt() ?? 0,
          };
        }
      }
      return {'inserted': 0, 'updated': 0};
    } catch (e) {
      throw Exception('refresh_kpi_actuals failed: $e');
    }
  }

  /// เรียก refresh_kpi_employee_actuals() ผ่าน Supabase RPC
  Future<Map<String, int>> refreshKpiEmployeeActuals({
    required String professionId,
    String periodType = 'daily',
    int lookbackDays = 30,
  }) async {
    try {
      final response = await _client.rpc(
        'refresh_kpi_employee_actuals',
        params: {
          'p_profession_id': professionId,
          'p_period_type': periodType,
          'p_lookback_days': lookbackDays,
        },
      );
      if (response is List && response.isNotEmpty) {
        final row = response.first as Map<String, dynamic>?;
        if (row != null) {
          return {
            'inserted': (row['inserted'] as num?)?.toInt() ?? 0,
            'updated': (row['updated'] as num?)?.toInt() ?? 0,
          };
        }
      }
      return {'inserted': 0, 'updated': 0};
    } catch (e) {
      throw Exception('refresh_kpi_employee_actuals failed: $e');
    }
  }

  /// เรียก refresh_kpi_appointments() ผ่าน Supabase RPC
  Future<Map<String, int>> refreshKpiAppointments({
    required String professionId,
    String periodType = 'daily',
    int lookbackDays = 30,
  }) async {
    try {
      final response = await _client.rpc(
        'refresh_kpi_appointments',
        params: {
          'p_profession_id': professionId,
          'p_period_type': periodType,
          'p_lookback_days': lookbackDays,
        },
      );
      if (response is List && response.isNotEmpty) {
        final row = response.first as Map<String, dynamic>?;
        if (row != null) {
          return {
            'inserted': (row['inserted'] as num?)?.toInt() ?? 0,
            'updated': (row['updated'] as num?)?.toInt() ?? 0,
          };
        }
      }
      return {'inserted': 0, 'updated': 0};
    } catch (e) {
      throw Exception('refresh_kpi_appointments failed: $e');
    }
  }
}
