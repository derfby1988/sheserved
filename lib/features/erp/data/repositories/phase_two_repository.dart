import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/checkout_session.dart';
import '../models/payment_transaction.dart';
import '../models/delivery_order.dart';
import '../models/vendor_contract.dart';
import '../models/cart_session.dart';
import '../models/rider.dart';

/// Repository สำหรับ ERP Phase 2 — Core Commerce & Platform
/// ครอบคลุม: Checkout, Payment, Delivery
class PhaseTwoRepository {
  final SupabaseClient _client;

  PhaseTwoRepository(this._client);

  // ========================
  // CHECKOUT SESSIONS
  // ========================

  Future<CheckoutSession?> createCheckoutSession({
    required String professionId,
    required String userId,
    required Map<String, dynamic> cartSnapshot,
    required double totalAmount,
    String? idempotencyKey,
  }) async {
    try {
      final response = await _client.rpc(
        'create_checkout_session',
        params: {
          'p_profession_id': professionId,
          'p_user_id': userId,
          'p_cart_snapshot': cartSnapshot,
          'p_total_amount': totalAmount,
          'p_idempotency_key': idempotencyKey,
        },
      );
      if (response == null) return null;
      return await getCheckoutSession(response as String);
    } catch (e, st) {
      debugPrint('[Phase2Repo] createCheckoutSession error: $e');
      return null;
    }
  }

  Future<CheckoutSession?> getCheckoutSession(String sessionId) async {
    try {
      final response = await _client
          .from('checkout_sessions')
          .select()
          .eq('id', sessionId)
          .single();
      return CheckoutSession.fromJson(response as Map<String, dynamic>);
    } catch (e, st) {
      debugPrint('[Phase2Repo] getCheckoutSession error: $e');
      return null;
    }
  }

  Future<bool> confirmCheckout(String sessionId, String orderId) async {
    try {
      final response = await _client.rpc(
        'confirm_checkout',
        params: {
          'p_session_id': sessionId,
          'p_order_id': orderId,
        },
      );
      return response as bool? ?? false;
    } catch (e, st) {
      debugPrint('[Phase2Repo] confirmCheckout error: $e');
      return false;
    }
  }

  // ========================
  // PAYMENT TRANSACTIONS
  // ========================

  Future<PaymentTransaction?> createPaymentTransaction(Map<String, dynamic> data) async {
    try {
      final response = await _client
          .from('payment_transactions')
          .insert(data)
          .select()
          .single();
      return PaymentTransaction.fromJson(response as Map<String, dynamic>);
    } catch (e, st) {
      debugPrint('[Phase2Repo] createPaymentTransaction error: $e');
      return null;
    }
  }

  Future<List<PaymentTransaction>> getTransactionsByOrder(String orderId) async {
    try {
      final response = await _client
          .from('payment_transactions')
          .select()
          .eq('order_id', orderId)
          .order('created_at', ascending: false);
      return (response as List)
          .map((e) => PaymentTransaction.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e, st) {
      debugPrint('[Phase2Repo] getTransactionsByOrder error: $e');
      return [];
    }
  }

  // ========================
  // DELIVERY ORDERS
  // ========================

  Future<DeliveryOrder?> createDeliveryOrder(Map<String, dynamic> data) async {
    try {
      final response = await _client
          .from('delivery_orders')
          .insert(data)
          .select()
          .single();
      return DeliveryOrder.fromJson(response as Map<String, dynamic>);
    } catch (e, st) {
      debugPrint('[Phase2Repo] createDeliveryOrder error: $e');
      return null;
    }
  }

  Future<List<DeliveryOrder>> getDeliveryOrders(String professionId) async {
    try {
      final response = await _client
          .from('delivery_orders')
          .select()
          .eq('profession_id', professionId)
          .order('created_at', ascending: false);
      return (response as List)
          .map((e) => DeliveryOrder.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e, st) {
      debugPrint('[Phase2Repo] getDeliveryOrders error: $e');
      return [];
    }
  }

  Future<bool> updateDeliveryStatus(String deliveryId, String status, {String? notes}) async {
    try {
      final response = await _client.rpc(
        'update_delivery_status',
        params: {
          'p_delivery_order_id': deliveryId,
          'p_new_status': status,
          'p_notes': notes,
        },
      );
      return response as bool? ?? false;
    } catch (e, st) {
      debugPrint('[Phase2Repo] updateDeliveryStatus error: $e');
      return false;
    }
  }

  // ========================
  // SETTLEMENT CORE
  // ========================

  Future<List<VendorContract>> getVendorContracts(String professionId) async {
    try {
      final response = await _client
          .from('vendor_contracts')
          .select()
          .eq('profession_id', professionId)
          .eq('is_active', true)
          .order('fee_percent', ascending: false);
      return (response as List)
          .map((e) => VendorContract.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e, st) {
      debugPrint('[Phase2Repo] getVendorContracts error: $e');
      return [];
    }
  }

  Future<String?> calculatePaymentAllocation({
    required String orderId,
    required String paymentTxnId,
    required double grossAmount,
  }) async {
    try {
      final response = await _client.rpc(
        'calculate_payment_allocation',
        params: {
          'p_order_id': orderId,
          'p_payment_txn_id': paymentTxnId,
          'p_gross_amount': grossAmount,
        },
      );
      return response as String?;
    } catch (e, st) {
      debugPrint('[Phase2Repo] calculatePaymentAllocation error: $e');
      return null;
    }
  }

  // ========================
  // CART CORE
  // ========================

  Future<CartSession?> createCartSession(Map<String, dynamic> data) async {
    try {
      final response = await _client
          .from('cart_sessions')
          .insert(data)
          .select()
          .single();
      return CartSession.fromJson(response as Map<String, dynamic>);
    } catch (e, st) {
      debugPrint('[Phase2Repo] createCartSession error: $e');
      return null;
    }
  }

  Future<CartSession?> getActiveCartSession(String userId) async {
    try {
      final response = await _client
          .from('cart_sessions')
          .select()
          .eq('user_id', userId)
          .eq('status', 'active')
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();
      if (response == null) return null;
      return CartSession.fromJson(response as Map<String, dynamic>);
    } catch (e, st) {
      debugPrint('[Phase2Repo] getActiveCartSession error: $e');
      return null;
    }
  }

  Future<bool> addItemToCart({
    required String cartSessionId,
    required String productId,
    required int quantity,
    required double unitPrice,
  }) async {
    try {
      final response = await _client.rpc(
        'add_item_to_cart',
        params: {
          'p_cart_session_id': cartSessionId,
          'p_product_id': productId,
          'p_quantity': quantity,
          'p_unit_price': unitPrice,
        },
      );
      return response as bool? ?? false;
    } catch (e, st) {
      debugPrint('[Phase2Repo] addItemToCart error: $e');
      return false;
    }
  }

  // ========================
  // LOGISTICS CORE
  // ========================

  Future<List<Rider>> getRiders(String professionId) async {
    try {
      final response = await _client
          .from('riders')
          .select()
          .eq('profession_id', professionId)
          .eq('is_active', true)
          .order('full_name');
      return (response as List)
          .map((e) => Rider.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e, st) {
      debugPrint('[Phase2Repo] getRiders error: $e');
      return [];
    }
  }

  Future<String?> assignDeliveryToRider({
    required String deliveryOrderId,
    required String riderId,
    int stopSequence = 1,
  }) async {
    try {
      final response = await _client.rpc(
        'assign_delivery_to_rider',
        params: {
          'p_delivery_order_id': deliveryOrderId,
          'p_rider_id': riderId,
          'p_stop_sequence': stopSequence,
        },
      );
      return response as String?;
    } catch (e, st) {
      debugPrint('[Phase2Repo] assignDeliveryToRider error: $e');
      return null;
    }
  }
}
