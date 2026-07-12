import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/checkout_session.dart';
import '../models/payment_transaction.dart';
import '../models/delivery_order.dart';
import '../models/vendor_contract.dart';
import '../models/cart_session.dart';
import '../models/cart_item.dart';
import '../models/payment_channel.dart';
import '../models/rider.dart';
import '../models/merchant_account.dart';
import '../models/payment_allocation.dart';
import '../models/payout_batch.dart';
import '../models/payout_batch_line.dart';
import '../models/delivery_run.dart';
import '../models/route_stop.dart';
import '../models/shipment.dart';
import '../models/carrier_config.dart';
import '../models/delivery_exception.dart';
import '../models/proof_of_delivery.dart';
import '../models/dashboard_snapshot.dart';
import '../models/projection_checkpoint.dart';
import '../models/kpi_aggregation.dart';

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

  Future<bool> updateCheckoutSessionStatus(
    String sessionId,
    String status, {
    String? paymentMethod,
  }) async {
    try {
      final response = await _client.rpc(
        'update_checkout_session_status',
        params: {
          'p_session_id': sessionId,
          'p_status': status,
          'p_payment_method': paymentMethod,
        },
      );
      return response as bool? ?? false;
    } catch (e, st) {
      debugPrint('[Phase2Repo] updateCheckoutSessionStatus error: $e');
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

  /// สร้าง delivery order
  /// [drugRiskFlags]: ผลลัพธ์จาก `DrugRiskScreeningService.buildDeliveryRiskFlags()`
  /// จะถูก merge เข้า `data['metadata']` อัตโนมัติ (DRUG_RISK_OVERRIDE_PLAN.md ข้อ 5.2)
  Future<DeliveryOrder?> createDeliveryOrder(
    Map<String, dynamic> data, {
    Map<String, dynamic>? drugRiskFlags,
  }) async {
    try {
      if (drugRiskFlags != null) {
        final rawMetadata = data['metadata'];
        final existingMetadata = rawMetadata != null
            ? Map<String, dynamic>.from(rawMetadata as Map)
            : <String, dynamic>{};
        data = {
          ...data,
          'metadata': {...existingMetadata, ...drugRiskFlags},
        };
      }
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

  Future<List<MerchantAccount>> getMerchantAccounts(String professionId) async {
    try {
      final response = await _client
          .from('merchant_accounts')
          .select()
          .eq('profession_id', professionId)
          .order('is_primary', ascending: false);
      return (response as List)
          .map((e) => MerchantAccount.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e, st) {
      debugPrint('[Phase2Repo] getMerchantAccounts error: $e');
      return [];
    }
  }

  Future<List<PaymentAllocation>> getPaymentAllocationsByProfession(String professionId) async {
    try {
      final response = await _client
          .from('payment_allocations')
          .select()
          .eq('profession_id', professionId)
          .order('created_at', ascending: false);
      return (response as List)
          .map((e) => PaymentAllocation.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e, st) {
      debugPrint('[Phase2Repo] getPaymentAllocationsByProfession error: $e');
      return [];
    }
  }

  Future<List<PaymentAllocation>> getPaymentAllocationsByOrder(String orderId) async {
    try {
      final response = await _client
          .from('payment_allocations')
          .select()
          .eq('order_id', orderId)
          .order('created_at', ascending: false);
      return (response as List)
          .map((e) => PaymentAllocation.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e, st) {
      debugPrint('[Phase2Repo] getPaymentAllocationsByOrder error: $e');
      return [];
    }
  }

  Future<String?> createPayoutBatch(
    String professionId, {
    String? merchantAccountId,
  }) async {
    try {
      final response = await _client.rpc(
        'create_payout_batch',
        params: {
          'p_profession_id': professionId,
          'p_merchant_account_id': merchantAccountId,
        },
      );
      return response as String?;
    } catch (e, st) {
      debugPrint('[Phase2Repo] createPayoutBatch error: $e');
      return null;
    }
  }

  Future<List<PayoutBatch>> getPayoutBatches(String professionId) async {
    try {
      final response = await _client
          .from('payout_batches')
          .select()
          .eq('profession_id', professionId)
          .order('batch_date', ascending: false);
      return (response as List)
          .map((e) => PayoutBatch.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e, st) {
      debugPrint('[Phase2Repo] getPayoutBatches error: $e');
      return [];
    }
  }

  Future<List<PayoutBatchLine>> getPayoutBatchLines(String batchId) async {
    try {
      final response = await _client
          .from('payout_batch_lines')
          .select()
          .eq('payout_batch_id', batchId)
          .order('created_at', ascending: true);
      return (response as List)
          .map((e) => PayoutBatchLine.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e, st) {
      debugPrint('[Phase2Repo] getPayoutBatchLines error: $e');
      return [];
    }
  }

  Future<Map<String, dynamic>?> getSettlementSummary(String professionId) async {
    try {
      final response = await _client.rpc(
        'get_settlement_summary',
        params: {'p_profession_id': professionId},
      );
      return response as Map<String, dynamic>?;
    } catch (e, st) {
      debugPrint('[Phase2Repo] getSettlementSummary error: $e');
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

  Future<List<CartItem>> getCartItems(String cartSessionId) async {
    try {
      final response = await _client
          .from('cart_items')
          .select()
          .eq('cart_session_id', cartSessionId)
          .order('created_at', ascending: true);
      return (response as List)
          .map((e) => CartItem.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e, st) {
      debugPrint('[Phase2Repo] getCartItems error: $e');
      return [];
    }
  }

  Future<bool> removeItemFromCart(String cartItemId) async {
    try {
      final response = await _client.rpc(
        'remove_item_from_cart',
        params: {
          'p_cart_item_id': cartItemId,
        },
      );
      return response as bool? ?? false;
    } catch (e, st) {
      debugPrint('[Phase2Repo] removeItemFromCart error: $e');
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

  // ------------------------
  // Delivery Extensions
  // ------------------------

  Future<List<DeliveryRun>> getDeliveryRuns(String professionId) async {
    try {
      final response = await _client
          .from('delivery_runs')
          .select()
          .eq('profession_id', professionId)
          .order('run_date', ascending: false);
      return (response as List)
          .map((e) => DeliveryRun.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e, st) {
      debugPrint('[Phase2Repo] getDeliveryRuns error: $e');
      return [];
    }
  }

  Future<List<RouteStop>> getRouteStops(String deliveryRunId) async {
    try {
      final response = await _client
          .from('route_stops')
          .select()
          .eq('delivery_run_id', deliveryRunId)
          .order('stop_sequence', ascending: true);
      return (response as List)
          .map((e) => RouteStop.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e, st) {
      debugPrint('[Phase2Repo] getRouteStops error: $e');
      return [];
    }
  }

  Future<bool> updateRouteStopStatus(String routeStopId, String status) async {
    try {
      final response = await _client.rpc(
        'update_route_stop_status',
        params: {
          'p_route_stop_id': routeStopId,
          'p_status': status,
        },
      );
      return response as bool? ?? false;
    } catch (e, st) {
      debugPrint('[Phase2Repo] updateRouteStopStatus error: $e');
      return false;
    }
  }

  Future<String?> createShipment({
    required String professionId,
    required String deliveryOrderId,
    String? carrierConfigId,
    String? trackingNumber,
    double weightKg = 0,
    Map<String, dynamic> dimensionsCm = const {},
    double shippingCost = 0,
  }) async {
    try {
      final response = await _client.rpc(
        'create_shipment',
        params: {
          'p_profession_id': professionId,
          'p_delivery_order_id': deliveryOrderId,
          'p_carrier_config_id': carrierConfigId,
          'p_tracking_number': trackingNumber,
          'p_weight_kg': weightKg,
          'p_dimensions_cm': dimensionsCm,
          'p_shipping_cost': shippingCost,
        },
      );
      return response as String?;
    } catch (e, st) {
      debugPrint('[Phase2Repo] createShipment error: $e');
      return null;
    }
  }

  Future<List<Shipment>> getShipments(String professionId) async {
    try {
      final response = await _client
          .from('shipments')
          .select()
          .eq('profession_id', professionId)
          .order('created_at', ascending: false);
      return (response as List)
          .map((e) => Shipment.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e, st) {
      debugPrint('[Phase2Repo] getShipments error: $e');
      return [];
    }
  }

  Future<List<CarrierConfig>> getCarrierConfigs(String professionId) async {
    try {
      final response = await _client
          .from('carrier_configs')
          .select()
          .eq('profession_id', professionId)
          .eq('is_active', true)
          .order('carrier_name');
      return (response as List)
          .map((e) => CarrierConfig.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e, st) {
      debugPrint('[Phase2Repo] getCarrierConfigs error: $e');
      return [];
    }
  }

  Future<String?> recordDeliveryException({
    required String professionId,
    required String deliveryOrderId,
    required String exceptionType,
    String severity = 'medium',
    String? description,
    String? photoUrl,
    double? gpsLat,
    double? gpsLng,
    String? routeStopId,
  }) async {
    try {
      final response = await _client.rpc(
        'record_delivery_exception',
        params: {
          'p_profession_id': professionId,
          'p_delivery_order_id': deliveryOrderId,
          'p_exception_type': exceptionType,
          'p_severity': severity,
          'p_description': description,
          'p_photo_url': photoUrl,
          'p_gps_lat': gpsLat,
          'p_gps_lng': gpsLng,
          'p_route_stop_id': routeStopId,
        },
      );
      return response as String?;
    } catch (e, st) {
      debugPrint('[Phase2Repo] recordDeliveryException error: $e');
      return null;
    }
  }

  Future<List<DeliveryException>> getDeliveryExceptions(String deliveryOrderId) async {
    try {
      final response = await _client
          .from('delivery_exceptions')
          .select()
          .eq('delivery_order_id', deliveryOrderId)
          .order('created_at', ascending: false);
      return (response as List)
          .map((e) => DeliveryException.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e, st) {
      debugPrint('[Phase2Repo] getDeliveryExceptions error: $e');
      return [];
    }
  }

  Future<String?> completeDeliveryWithProof({
    required String deliveryOrderId,
    required String proofType,
    String? proofUrl,
    Map<String, dynamic> metadata = const {},
    String? verifiedBy,
  }) async {
    try {
      final response = await _client.rpc(
        'complete_delivery_with_proof',
        params: {
          'p_delivery_order_id': deliveryOrderId,
          'p_proof_type': proofType,
          'p_proof_url': proofUrl,
          'p_metadata': metadata,
          'p_verified_by': verifiedBy,
        },
      );
      return response as String?;
    } catch (e, st) {
      debugPrint('[Phase2Repo] completeDeliveryWithProof error: $e');
      return null;
    }
  }

  Future<List<ProofOfDelivery>> getProofOfDeliveries(String deliveryOrderId) async {
    try {
      final response = await _client
          .from('proof_of_deliveries')
          .select()
          .eq('delivery_order_id', deliveryOrderId)
          .order('created_at', ascending: false);
      return (response as List)
          .map((e) => ProofOfDelivery.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e, st) {
      debugPrint('[Phase2Repo] getProofOfDeliveries error: $e');
      return [];
    }
  }

  // ========================
  // ANALYTICS / READ MODEL
  // ========================

  Future<List<DashboardSnapshot>> getDashboardSnapshots(String professionId, {String? snapshotType}) async {
    try {
      var query = _client
          .from('dashboard_snapshots')
          .select()
          .eq('profession_id', professionId);
      if (snapshotType != null) {
        query = query.eq('snapshot_type', snapshotType);
      }
      final response = await query
          .order('snapshot_date', ascending: false);
      return (response as List)
          .map((e) => DashboardSnapshot.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e, st) {
      debugPrint('[Phase2Repo] getDashboardSnapshots error: $e');
      return [];
    }
  }

  Future<String?> upsertDashboardSnapshot({
    required String professionId,
    required String snapshotType,
    required Map<String, dynamic> metrics,
  }) async {
    try {
      final response = await _client.rpc(
        'upsert_dashboard_snapshot',
        params: {
          'p_profession_id': professionId,
          'p_snapshot_type': snapshotType,
          'p_metrics': metrics,
        },
      );
      return response as String?;
    } catch (e, st) {
      debugPrint('[Phase2Repo] upsertDashboardSnapshot error: $e');
      return null;
    }
  }

  Future<String?> generateDailySnapshot(String professionId) async {
    try {
      final response = await _client.rpc(
        'generate_daily_snapshot',
        params: {'p_profession_id': professionId},
      );
      return response as String?;
    } catch (e, st) {
      debugPrint('[Phase2Repo] generateDailySnapshot error: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> getSnapshotComparison(String professionId, {String snapshotType = 'daily'}) async {
    try {
      final response = await _client.rpc(
        'get_snapshot_comparison',
        params: {
          'p_profession_id': professionId,
          'p_snapshot_type': snapshotType,
        },
      );
      return response as Map<String, dynamic>?;
    } catch (e, st) {
      debugPrint('[Phase2Repo] getSnapshotComparison error: $e');
      return null;
    }
  }

  Future<List<KpiAggregation>> getKpiAggregations(String professionId, {String? category}) async {
    try {
      var query = _client
          .from('kpi_aggregations')
          .select()
          .eq('profession_id', professionId);
      if (category != null) {
        query = query.eq('kpi_category', category);
      }
      final response = await query
          .order('period_end', ascending: false);
      return (response as List)
          .map((e) => KpiAggregation.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e, st) {
      debugPrint('[Phase2Repo] getKpiAggregations error: $e');
      return [];
    }
  }

  Future<String?> upsertKpiAggregation({
    required String professionId,
    required String kpiName,
    required String kpiCategory,
    required DateTime periodStart,
    required DateTime periodEnd,
    required double value,
    double? targetValue,
    String unit = 'count',
    bool isBetterHigher = true,
  }) async {
    try {
      final response = await _client.rpc(
        'upsert_kpi_aggregation',
        params: {
          'p_profession_id': professionId,
          'p_kpi_name': kpiName,
          'p_kpi_category': kpiCategory,
          'p_period_start': periodStart.toIso8601String().split('T')[0],
          'p_period_end': periodEnd.toIso8601String().split('T')[0],
          'p_value': value,
          'p_target_value': targetValue,
          'p_unit': unit,
          'p_is_better_higher': isBetterHigher,
        },
      );
      return response as String?;
    } catch (e, st) {
      debugPrint('[Phase2Repo] upsertKpiAggregation error: $e');
      return null;
    }
  }

  Future<List<ProjectionCheckpoint>> getProjectionCheckpoints(String professionId) async {
    try {
      final response = await _client
          .from('projection_checkpoints')
          .select()
          .eq('profession_id', professionId)
          .order('updated_at', ascending: false);
      return (response as List)
          .map((e) => ProjectionCheckpoint.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e, st) {
      debugPrint('[Phase2Repo] getProjectionCheckpoints error: $e');
      return [];
    }
  }

  Future<String?> advanceProjectionCheckpoint({
    required String professionId,
    required String projectionName,
    String? lastEventId,
    int lastEventSeq = 0,
    Map<String, dynamic> stateSnapshot = const {},
  }) async {
    try {
      final response = await _client.rpc(
        'advance_projection_checkpoint',
        params: {
          'p_profession_id': professionId,
          'p_projection_name': projectionName,
          'p_last_event_id': lastEventId,
          'p_last_event_seq': lastEventSeq,
          'p_state_snapshot': stateSnapshot,
        },
      );
      return response as String?;
    } catch (e, st) {
      debugPrint('[Phase2Repo] advanceProjectionCheckpoint error: $e');
      return null;
    }
  }

  // ========================
  // PAYMENT CHANNELS
  // ========================

  Future<List<PaymentChannel>> getPaymentChannels(String professionId) async {
    try {
      final response = await _client
          .from('payment_channels')
          .select()
          .eq('profession_id', professionId)
          .eq('is_enabled', true)
          .order('display_order', ascending: true);
      return (response as List)
          .map((e) => PaymentChannel.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e, st) {
      debugPrint('[Phase2Repo] getPaymentChannels error: $e');
      return [];
    }
  }

  Future<bool> updatePaymentChannelEnabled(String channelId, bool enabled) async {
    try {
      await _client
          .from('payment_channels')
          .update({'is_enabled': enabled, 'updated_at': DateTime.now().toIso8601String()})
          .eq('id', channelId);
      return true;
    } catch (e, st) {
      debugPrint('[Phase2Repo] updatePaymentChannelEnabled error: $e');
      return false;
    }
  }
}
