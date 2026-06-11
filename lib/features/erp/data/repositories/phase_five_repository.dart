import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/refund_request.dart';
import '../models/loyalty_rule.dart';
import '../models/scheduled_report.dart';

/// Repository สำหรับ ERP Phase 5 — Refund + Loyalty + Reports
class PhaseFiveRepository {
  final SupabaseClient _client;

  PhaseFiveRepository(this._client);

  // ========================
  // REFUNDS
  // ========================

  Future<List<RefundRequest>> getRefundRequests(String professionId) async {
    try {
      final response = await _client
          .from('refund_requests')
          .select()
          .eq('profession_id', professionId)
          .order('requested_at', ascending: false);
      return (response as List)
          .map((e) => RefundRequest.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('[Phase5Repo] getRefundRequests error: $e');
      return [];
    }
  }

  Future<String?> requestRefund(Map<String, dynamic> params) async {
    try {
      final response = await _client.rpc(
        'request_refund',
        params: {
          'p_profession_id': params['profession_id'],
          'p_order_id': params['order_id'],
          'p_customer_id': params['customer_id'],
          'p_amount': params['amount'],
          'p_reason': params['reason'],
          'p_requested_by': params['requested_by'],
        },
      );
      return response as String?;
    } catch (e) {
      debugPrint('[Phase5Repo] requestRefund error: $e');
      return null;
    }
  }

  Future<bool> reviewRefund(String refundId, String status, String reviewedBy, {String? notes}) async {
    try {
      final response = await _client.rpc(
        'review_refund',
        params: {
          'p_refund_id': refundId,
          'p_status': status,
          'p_reviewed_by': reviewedBy,
          'p_notes': notes,
        },
      );
      return response as bool? ?? false;
    } catch (e) {
      debugPrint('[Phase5Repo] reviewRefund error: $e');
      return false;
    }
  }

  // ========================
  // LOYALTY RULES
  // ========================

  Future<List<LoyaltyRule>> getLoyaltyRules(String professionId) async {
    try {
      final response = await _client
          .from('loyalty_point_rules')
          .select()
          .eq('profession_id', professionId)
          .order('created_at', ascending: false);
      return (response as List)
          .map((e) => LoyaltyRule.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('[Phase5Repo] getLoyaltyRules error: $e');
      return [];
    }
  }

  Future<LoyaltyRule?> createLoyaltyRule(Map<String, dynamic> data) async {
    try {
      final response = await _client
          .from('loyalty_point_rules')
          .insert(data)
          .select()
          .single();
      return LoyaltyRule.fromJson(response);
    } catch (e) {
      debugPrint('[Phase5Repo] createLoyaltyRule error: $e');
      return null;
    }
  }

  Future<int?> calculateLoyaltyPoints(String professionId, double orderTotal, {String itemType = 'all'}) async {
    try {
      final response = await _client.rpc(
        'calculate_loyalty_points',
        params: {
          'p_profession_id': professionId,
          'p_order_total': orderTotal,
          'p_item_type': itemType,
        },
      );
      return response as int?;
    } catch (e) {
      debugPrint('[Phase5Repo] calculateLoyaltyPoints error: $e');
      return null;
    }
  }

  // ========================
  // SCHEDULED REPORTS
  // ========================

  Future<List<ScheduledReport>> getScheduledReports(String professionId) async {
    try {
      final response = await _client
          .from('scheduled_reports')
          .select()
          .eq('profession_id', professionId)
          .order('created_at', ascending: false);
      return (response as List)
          .map((e) => ScheduledReport.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('[Phase5Repo] getScheduledReports error: $e');
      return [];
    }
  }

  Future<ScheduledReport?> createScheduledReport(Map<String, dynamic> data) async {
    try {
      final response = await _client
          .from('scheduled_reports')
          .insert(data)
          .select()
          .single();
      return ScheduledReport.fromJson(response);
    } catch (e) {
      debugPrint('[Phase5Repo] createScheduledReport error: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> generateReportPayload(String professionId, String reportType, DateTime startDate, DateTime endDate) async {
    try {
      final response = await _client.rpc(
        'generate_report_payload',
        params: {
          'p_profession_id': professionId,
          'p_report_type': reportType,
          'p_start_date': startDate.toIso8601String().substring(0, 10),
          'p_end_date': endDate.toIso8601String().substring(0, 10),
        },
      );
      return response as Map<String, dynamic>?;
    } catch (e) {
      debugPrint('[Phase5Repo] generateReportPayload error: $e');
      return null;
    }
  }
}
