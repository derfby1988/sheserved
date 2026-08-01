import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/customer_package.dart';
import '../models/customer.dart';

/// Repository สำหรับ CRM & Appointment Core Functions (Step 3 Integration)
class CrmRepository {
  final SupabaseClient _client;

  CrmRepository(this._client);

  // ==========================================
  // 1. PREPAID COURSE PACKAGES (customer_packages)
  // ==========================================

  Future<List<CustomerPackage>> getCustomerPackages(String professionId, {String? customerId}) async {
    try {
      var query = _client.from('customer_packages').select().eq('profession_id', professionId);
      if (customerId != null && customerId.isNotEmpty) {
        query = query.eq('customer_id', customerId);
      }
      final response = await query.order('created_at', ascending: false);
      return (response as List).map((e) => CustomerPackage.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      debugPrint('[CrmRepo] getCustomerPackages error: $e');
      return [];
    }
  }

  Future<CustomerPackage?> createCustomerPackage(Map<String, dynamic> data) async {
    try {
      final response = await _client.from('customer_packages').insert(data).select().single();
      return CustomerPackage.fromJson(response);
    } catch (e) {
      debugPrint('[CrmRepo] createCustomerPackage error: $e');
      return null;
    }
  }

  Future<bool> deductPackageSession(String packageId, {int sessionsToDeduct = 1, String? appointmentId, String? notes}) async {
    try {
      final pkgRes = await _client.from('customer_packages').select().eq('id', packageId).single();
      final pkg = CustomerPackage.fromJson(pkgRes);

      if (pkg.remainingSessions < sessionsToDeduct) {
        debugPrint('[CrmRepo] Insufficient sessions available in package');
        return false;
      }

      final newUsed = pkg.usedSessions + sessionsToDeduct;
      final newRemaining = pkg.remainingSessions - sessionsToDeduct;
      final newStatus = newRemaining <= 0 ? 'completed' : 'active';

      await _client.from('customer_packages').update({
        'used_sessions': newUsed,
        'remaining_sessions': newRemaining,
        'status': newStatus,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', packageId);

      await _client.from('package_session_logs').insert({
        'package_id': packageId,
        'profession_id': pkg.professionId,
        'appointment_id': appointmentId,
        'sessions_deducted': sessionsToDeduct,
        'notes': notes,
      });

      return true;
    } catch (e) {
      debugPrint('[CrmRepo] deductPackageSession error: $e');
      return false;
    }
  }

  // ==========================================
  // 2. APPOINTMENTS (VIEW appointments)
  // ==========================================

  Future<List<Map<String, dynamic>>> getAppointments(String professionId, {String? status}) async {
    try {
      var query = _client.from('appointments').select().eq('profession_id', professionId);
      if (status != null && status.isNotEmpty) {
        query = query.eq('status', status);
      }
      final response = await query.order('scheduled_at', ascending: true);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('[CrmRepo] getAppointments error: $e');
      return [];
    }
  }

  // ==========================================
  // 3. LOYALTY WALLETS & COUPON USAGES (VIEWS)
  // ==========================================

  Future<List<Map<String, dynamic>>> getCustomerLoyaltyWallets(String professionId) async {
    try {
      final response = await _client.from('customer_loyalty_wallets').select().eq('profession_id', professionId);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('[CrmRepo] getCustomerLoyaltyWallets error: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getCouponUsages(String professionId) async {
    try {
      final response = await _client.from('coupon_usages').select().eq('profession_id', professionId);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('[CrmRepo] getCouponUsages error: $e');
      return [];
    }
  }

  // ==========================================
  // 4. LOYALTY POINTS & COUPON POS INTEGRATION (Group B - Phase 4-8)
  // ==========================================

  /// ตรวจสอบความถูกต้องและคำนวณส่วนลดจากคูปอง
  Future<Map<String, dynamic>?> validateCouponCode({
    required String professionId,
    required String code,
    required double orderAmount,
  }) async {
    try {
      final response = await _client
          .from('coupons')
          .select()
          .eq('profession_id', professionId)
          .eq('code', code.trim().toUpperCase())
          .eq('is_active', true)
          .maybeSingle();

      if (response == null) {
        return {'valid': false, 'message': 'ไม่พบคูปอง หรือคูปองถูกยกเลิกแล้ว'};
      }

      final minOrder = (response['min_order_amount'] as num?)?.toDouble() ?? 0.0;
      if (orderAmount < minOrder) {
        return {
          'valid': false,
          'message': 'ยอดสั่งซื้อขั้นต่ำสำหรับคูปองนี้คือ ฿${minOrder.toStringAsFixed(2)}',
        };
      }

      final endDateStr = response['end_date'] as String?;
      if (endDateStr != null) {
        final endDate = DateTime.parse(endDateStr);
        if (DateTime.now().isAfter(endDate)) {
          return {'valid': false, 'message': 'คูปองนี้หมดอายุแล้ว'};
        }
      }

      final usageLimit = response['usage_limit'] as int?;
      final usageCount = response['usage_count'] as int? ?? 0;
      if (usageLimit != null && usageCount >= usageLimit) {
        return {'valid': false, 'message': 'คูปองนี้ถูกใช้งานเต็มสิทธิ์แล้ว'};
      }

      final couponType = response['coupon_type'] as String;
      final rawValue = (response['value'] as num).toDouble();
      final maxDiscount = (response['max_discount'] as num?)?.toDouble();

      double discountAmount = 0;
      if (couponType == 'percentage') {
        discountAmount = orderAmount * (rawValue / 100.0);
        if (maxDiscount != null && maxDiscount > 0 && discountAmount > maxDiscount) {
          discountAmount = maxDiscount;
        }
      } else if (couponType == 'fixed_amount') {
        discountAmount = rawValue;
      }

      if (discountAmount > orderAmount) {
        discountAmount = orderAmount;
      }

      return {
        'valid': true,
        'coupon_id': response['id'],
        'code': response['code'],
        'coupon_type': couponType,
        'discount_amount': discountAmount,
      };
    } catch (e) {
      debugPrint('[CrmRepo] validateCouponCode error: $e');
      return {'valid': false, 'message': 'เกิดข้อผิดพลาดในการตรวจสอบคูปอง'};
    }
  }

  /// บันทึกการใช้งานคูปองตอน Checkout
  Future<bool> redeemCoupon({
    required String professionId,
    required String couponId,
    String? customerId,
    String? orderId,
    required double discountAmount,
  }) async {
    try {
      await _client.from('coupon_redemptions').insert({
        'profession_id': professionId,
        'coupon_id': couponId,
        'customer_id': customerId,
        'order_id': orderId,
        'discount_amount': discountAmount,
      });

      // อัปเดตจำนวนครั้งที่ใช้งานคูปอง
      await _client.rpc('increment_coupon_usage', params: {
        'p_coupon_id': couponId,
      }).catchError((_) async {
        final couponRes = await _client.from('coupons').select('usage_count').eq('id', couponId).single();
        final currentCount = couponRes['usage_count'] as int? ?? 0;
        await _client.from('coupons').update({'usage_count': currentCount + 1}).eq('id', couponId);
      });

      return true;
    } catch (e) {
      debugPrint('[CrmRepo] redeemCoupon error: $e');
      return false;
    }
  }

  /// คำนวณและเพิ่มแต้มสะสมให้ลูกค้า
  Future<bool> earnLoyaltyPoints({
    required String professionId,
    required String customerId,
    required int pointsToEarn,
    String? orderId,
    String? description,
  }) async {
    try {
      final custRes = await _client.from('customers').select('total_points').eq('id', customerId).single();
      final currentPoints = custRes['total_points'] as int? ?? 0;
      final newPoints = currentPoints + pointsToEarn;

      await _client.from('customers').update({
        'total_points': newPoints,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', customerId);

      await _client.from('loyalty_points').insert({
        'profession_id': professionId,
        'customer_id': customerId,
        'points_change': pointsToEarn,
        'points_balance': newPoints,
        'transaction_type': 'earn',
        'reference_type': 'order',
        'reference_id': orderId,
        'description': description ?? 'ได้รับแต้มสะสมจากการซื้อสินค้า/บริการ',
      });

      return true;
    } catch (e) {
      debugPrint('[CrmRepo] earnLoyaltyPoints error: $e');
      return false;
    }
  }

  /// หักแต้มสะสมของลูกค้าเมื่อนำมาแลกส่วนลด
  Future<bool> redeemLoyaltyPoints({
    required String professionId,
    required String customerId,
    required int pointsToRedeem,
    String? orderId,
    String? description,
  }) async {
    try {
      final custRes = await _client.from('customers').select('total_points').eq('id', customerId).single();
      final currentPoints = custRes['total_points'] as int? ?? 0;

      if (currentPoints < pointsToRedeem) {
        debugPrint('[CrmRepo] Insufficient points');
        return false;
      }

      final newPoints = currentPoints - pointsToRedeem;

      await _client.from('customers').update({
        'total_points': newPoints,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', customerId);

      await _client.from('loyalty_points').insert({
        'profession_id': professionId,
        'customer_id': customerId,
        'points_change': -pointsToRedeem,
        'points_balance': newPoints,
        'transaction_type': 'redeem',
        'reference_type': 'order',
        'reference_id': orderId,
        'description': description ?? 'ใช้แต้มสะสมแลกส่วนลดหน้าร้าน',
      });

      return true;
    } catch (e) {
      debugPrint('[CrmRepo] redeemLoyaltyPoints error: $e');
      return false;
    }
  }

  // ==========================================
  // 5. CUSTOMER FEEDBACKS / CSAT
  // ==========================================

  Future<bool> submitCustomerFeedback(Map<String, dynamic> data) async {
    try {
      await _client.from('customer_feedbacks').insert(data);
      return true;
    } catch (e) {
      debugPrint('[CrmRepo] submitCustomerFeedback error: $e');
      return false;
    }
  }
}

