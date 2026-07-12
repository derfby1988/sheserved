import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../data/models/checkout_session.dart';
import '../../data/models/payment_transaction.dart';
import '../../data/models/delivery_order.dart';
import '../../data/models/vendor_contract.dart';
import '../../data/models/cart_session.dart';
import '../../data/models/cart_item.dart';
import '../../data/models/payment_channel.dart';
import '../../data/models/payout_batch.dart';
import '../../data/models/payout_batch_line.dart';
import '../../data/repositories/phase_two_repository.dart';

// ========================
// Repository Provider
// ========================
final phaseTwoRepositoryProvider = Provider<PhaseTwoRepository>((ref) {
  return PhaseTwoRepository(Supabase.instance.client);
});

// ========================
// State
// ========================
class PhaseTwoState {
  final bool isLoading;
  final bool isSaving;
  final String? errorMessage;

  final CartSession? cartSession;
  final List<CartItem> cartItems;
  final CheckoutSession? activeCheckout;
  final List<PaymentTransaction> transactions;
  final List<DeliveryOrder> deliveryOrders;
  final List<VendorContract>? vendorContracts;
  final List<PaymentChannel> paymentChannels;
  final List<PayoutBatch> payoutBatches;
  final Map<String, List<PayoutBatchLine>> payoutBatchLines;

  PhaseTwoState({
    this.isLoading = false,
    this.isSaving = false,
    this.errorMessage,
    this.cartSession,
    this.cartItems = const [],
    this.activeCheckout,
    this.transactions = const [],
    this.deliveryOrders = const [],
    this.vendorContracts,
    this.paymentChannels = const [],
    this.payoutBatches = const [],
    this.payoutBatchLines = const {},
  });

  double get cartTotal => cartItems.fold(0, (sum, item) => sum + item.total);

  PhaseTwoState copyWith({
    bool? isLoading,
    bool? isSaving,
    String? errorMessage,
    bool clearError = false,
    CartSession? cartSession,
    bool clearCart = false,
    List<CartItem>? cartItems,
    CheckoutSession? activeCheckout,
    bool clearCheckout = false,
    List<PaymentTransaction>? transactions,
    List<DeliveryOrder>? deliveryOrders,
    List<VendorContract>? vendorContracts,
    List<PaymentChannel>? paymentChannels,
    List<PayoutBatch>? payoutBatches,
    Map<String, List<PayoutBatchLine>>? payoutBatchLines,
  }) {
    final shouldClearError = clearError ||
        ((isLoading != null && !isLoading) || (isSaving != null && !isSaving));
    return PhaseTwoState(
      isLoading: isLoading ?? this.isLoading,
      isSaving: isSaving ?? this.isSaving,
      errorMessage: shouldClearError ? null : (errorMessage ?? this.errorMessage),
      cartSession: clearCart ? null : (cartSession ?? this.cartSession),
      cartItems: cartItems ?? this.cartItems,
      activeCheckout: clearCheckout ? null : (activeCheckout ?? this.activeCheckout),
      transactions: transactions ?? this.transactions,
      deliveryOrders: deliveryOrders ?? this.deliveryOrders,
      vendorContracts: vendorContracts ?? this.vendorContracts,
      paymentChannels: paymentChannels ?? this.paymentChannels,
      payoutBatches: payoutBatches ?? this.payoutBatches,
      payoutBatchLines: payoutBatchLines ?? this.payoutBatchLines,
    );
  }
}

// ========================
// Notifier
// ========================
class PhaseTwoNotifier extends StateNotifier<PhaseTwoState> {
  final PhaseTwoRepository _repository;

  PhaseTwoNotifier(this._repository) : super(PhaseTwoState());

  // ========================
  // CART
  // ========================

  Future<void> loadCart(String userId) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final cart = await _repository.getActiveCartSession(userId);
      if (cart == null) {
        state = state.copyWith(isLoading: false, clearCart: true);
        return;
      }
      final items = await _repository.getCartItems(cart.id);
      state = state.copyWith(isLoading: false, cartSession: cart, cartItems: items);
    } catch (e, st) {
      debugPrint('[Phase2] loadCart ERROR: $e');
      state = state.copyWith(isLoading: false, errorMessage: 'โหลดตะกร้าล้มเหลว: $e');
    }
  }

  Future<bool> addItemToCart({
    required String professionId,
    required String userId,
    required String productId,
    required String productName,
    required double unitPrice,
    int quantity = 1,
  }) async {
    state = state.copyWith(isSaving: true, clearError: true);
    try {
      String? cartId = state.cartSession?.id;
      if (cartId == null) {
        final cart = await _repository.createCartSession({
          'profession_id': professionId,
          'user_id': userId,
          'status': 'active',
        });
        if (cart == null) {
          state = state.copyWith(isSaving: false, errorMessage: 'สร้างตะกร้าไม่สำเร็จ');
          return false;
        }
        cartId = cart.id;
      }

      final success = await _repository.addItemToCart(
        cartSessionId: cartId,
        productId: productId,
        quantity: quantity,
        unitPrice: unitPrice,
      );
      if (success) {
        final items = await _repository.getCartItems(cartId);
        state = state.copyWith(isSaving: false, cartItems: items);
      } else {
        state = state.copyWith(isSaving: false, errorMessage: 'เพิ่มสินค้าไม่สำเร็จ');
      }
      return success;
    } catch (e, st) {
      debugPrint('[Phase2] addItemToCart ERROR: $e');
      state = state.copyWith(isSaving: false, errorMessage: 'เพิ่มสินค้าล้มเหลว: $e');
      return false;
    }
  }

  Future<bool> removeItemFromCart(String cartItemId) async {
    state = state.copyWith(isSaving: true, clearError: true);
    try {
      final success = await _repository.removeItemFromCart(cartItemId);
      if (success && state.cartSession != null) {
        final items = await _repository.getCartItems(state.cartSession!.id);
        state = state.copyWith(isSaving: false, cartItems: items);
      } else {
        state = state.copyWith(isSaving: false, errorMessage: 'ลบสินค้าไม่สำเร็จ');
      }
      return success;
    } catch (e, st) {
      debugPrint('[Phase2] removeItemFromCart ERROR: $e');
      state = state.copyWith(isSaving: false, errorMessage: 'ลบสินค้าล้มเหลว: $e');
      return false;
    }
  }

  Future<void> clearCart() async {
    state = state.copyWith(clearCart: true);
  }

  // ========================
  // CHECKOUT
  // ========================

  Future<CheckoutSession?> startCheckout({
    required String professionId,
    required String userId,
    required Map<String, dynamic> cartSnapshot,
    required double totalAmount,
    String? idempotencyKey,
  }) async {
    state = state.copyWith(isLoading: true, clearError: true, clearCheckout: true);
    try {
      final session = await _repository.createCheckoutSession(
        professionId: professionId,
        userId: userId,
        cartSnapshot: cartSnapshot,
        totalAmount: totalAmount,
        idempotencyKey: idempotencyKey,
      );
      state = state.copyWith(isLoading: false, activeCheckout: session);
      return session;
    } catch (e, st) {
      debugPrint('[Phase2] startCheckout ERROR: $e');
      state = state.copyWith(isLoading: false, errorMessage: 'สร้าง checkout session ล้มเหลว: $e');
      return null;
    }
  }

  Future<bool> confirmCheckout(String sessionId, String orderId) async {
    state = state.copyWith(isSaving: true, clearError: true);
    try {
      final success = await _repository.confirmCheckout(sessionId, orderId);
      state = state.copyWith(isSaving: false);
      return success;
    } catch (e, st) {
      debugPrint('[Phase2] confirmCheckout ERROR: $e');
      state = state.copyWith(isSaving: false, errorMessage: 'ยืนยัน checkout ล้มเหลว: $e');
      return false;
    }
  }

  Future<bool> updateCheckoutSessionStatus(
    String sessionId,
    String status, {
    String? paymentMethod,
  }) async {
    try {
      return await _repository.updateCheckoutSessionStatus(
        sessionId,
        status,
        paymentMethod: paymentMethod,
      );
    } catch (e, st) {
      debugPrint('[Phase2] updateCheckoutSessionStatus ERROR: $e');
      return false;
    }
  }

  Future<PaymentTransaction?> createPaymentTransaction({
    required String professionId,
    required String orderId,
    required String userId,
    required double amount,
    required String paymentMethod,
    String? provider,
    String? checkoutSessionId,
  }) async {
    state = state.copyWith(isSaving: true, clearError: true);
    try {
      final txn = await _repository.createPaymentTransaction({
        'profession_id': professionId,
        'order_id': orderId,
        'user_id': userId,
        'amount': amount,
        'payment_method': paymentMethod,
        'provider': provider,
        'checkout_session_id': checkoutSessionId,
        'status': 'completed',
      });
      state = state.copyWith(isSaving: false);
      return txn;
    } catch (e, st) {
      debugPrint('[Phase2] createPaymentTransaction ERROR: $e');
      state = state.copyWith(isSaving: false, errorMessage: 'สร้างรายการชำระเงินล้มเหลว: $e');
      return null;
    }
  }

  // ========================
  // PAYMENT
  // ========================

  Future<bool> recordPayment(Map<String, dynamic> data) async {
    state = state.copyWith(isSaving: true, clearError: true);
    try {
      final txn = await _repository.createPaymentTransaction(data);
      state = state.copyWith(isSaving: false);
      return txn != null;
    } catch (e, st) {
      debugPrint('[Phase2] recordPayment ERROR: $e');
      state = state.copyWith(isSaving: false, errorMessage: 'บันทึกการชำระเงินล้มเหลว: $e');
      return false;
    }
  }

  Future<String?> calculatePaymentAllocation({
    required String orderId,
    required String paymentTxnId,
    required double grossAmount,
  }) async {
    try {
      return await _repository.calculatePaymentAllocation(
        orderId: orderId,
        paymentTxnId: paymentTxnId,
        grossAmount: grossAmount,
      );
    } catch (e, st) {
      debugPrint('[Phase2] calculatePaymentAllocation ERROR: $e');
      return null;
    }
  }

  Future<void> loadTransactions(String orderId) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final txns = await _repository.getTransactionsByOrder(orderId);
      state = state.copyWith(isLoading: false, transactions: txns);
    } catch (e, st) {
      debugPrint('[Phase2] loadTransactions ERROR: $e');
      state = state.copyWith(isLoading: false, errorMessage: 'โหลดประวัติการชำระเงินล้มเหลว: $e');
    }
  }

  // ========================
  // DELIVERY
  // ========================

  Future<void> loadDeliveryOrders(String professionId) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final orders = await _repository.getDeliveryOrders(professionId);
      state = state.copyWith(isLoading: false, deliveryOrders: orders);
    } catch (e, st) {
      debugPrint('[Phase2] loadDeliveryOrders ERROR: $e');
      state = state.copyWith(isLoading: false, errorMessage: 'โหลดรายการจัดส่งล้มเหลว: $e');
    }
  }

  /// สร้าง delivery order
  /// [drugRiskFlags]: ผลลัพธ์จาก `DrugRiskScreeningService.buildDeliveryRiskFlags()`
  Future<bool> createDeliveryOrder(
    Map<String, dynamic> data, {
    Map<String, dynamic>? drugRiskFlags,
  }) async {
    state = state.copyWith(isSaving: true, clearError: true);
    try {
      final order = await _repository.createDeliveryOrder(
        data,
        drugRiskFlags: drugRiskFlags,
      );
      state = state.copyWith(isSaving: false);
      return order != null;
    } catch (e, st) {
      debugPrint('[Phase2] createDeliveryOrder ERROR: $e');
      state = state.copyWith(isSaving: false, errorMessage: 'สร้างรายการจัดส่งล้มเหลว: $e');
      return false;
    }
  }

  Future<bool> updateDeliveryStatus(String deliveryId, String status, {String? notes}) async {
    state = state.copyWith(isSaving: true, clearError: true);
    try {
      final success = await _repository.updateDeliveryStatus(deliveryId, status, notes: notes);
      state = state.copyWith(isSaving: false);
      return success;
    } catch (e, st) {
      debugPrint('[Phase2] updateDeliveryStatus ERROR: $e');
      state = state.copyWith(isSaving: false, errorMessage: 'อัปเดตสถานะจัดส่งล้มเหลว: $e');
      return false;
    }
  }

  // Delivery Extensions
  Future<String?> createShipment({
    required String professionId,
    required String deliveryOrderId,
    String? carrierConfigId,
    String? trackingNumber,
    double weightKg = 0,
    double shippingCost = 0,
  }) async {
    try {
      return await _repository.createShipment(
        professionId: professionId,
        deliveryOrderId: deliveryOrderId,
        carrierConfigId: carrierConfigId,
        trackingNumber: trackingNumber,
        weightKg: weightKg,
        shippingCost: shippingCost,
      );
    } catch (e, st) {
      debugPrint('[Phase2] createShipment ERROR: $e');
      return null;
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
  }) async {
    try {
      return await _repository.recordDeliveryException(
        professionId: professionId,
        deliveryOrderId: deliveryOrderId,
        exceptionType: exceptionType,
        severity: severity,
        description: description,
        photoUrl: photoUrl,
        gpsLat: gpsLat,
        gpsLng: gpsLng,
      );
    } catch (e, st) {
      debugPrint('[Phase2] recordDeliveryException ERROR: $e');
      return null;
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
      return await _repository.completeDeliveryWithProof(
        deliveryOrderId: deliveryOrderId,
        proofType: proofType,
        proofUrl: proofUrl,
        metadata: metadata,
        verifiedBy: verifiedBy,
      );
    } catch (e, st) {
      debugPrint('[Phase2] completeDeliveryWithProof ERROR: $e');
      return null;
    }
  }

  Future<void> loadVendorContracts(String professionId) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final contracts = await _repository.getVendorContracts(professionId);
      state = state.copyWith(isLoading: false, vendorContracts: contracts);
    } catch (e, st) {
      debugPrint('[Phase2] loadVendorContracts ERROR: $e');
      state = state.copyWith(isLoading: false, errorMessage: 'โหลดสัญญาผู้ให้บริการล้มเหลว: $e');
    }
  }

  // ========================
  // ANALYTICS / READ MODEL
  // ========================

  Future<void> loadDashboardSnapshots(String professionId, {String? snapshotType}) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final snapshots = await _repository.getDashboardSnapshots(professionId, snapshotType: snapshotType);
      state = state.copyWith(isLoading: false, /* dashboardSnapshots: snapshots */);
    } catch (e, st) {
      debugPrint('[Phase2] loadDashboardSnapshots ERROR: $e');
      state = state.copyWith(isLoading: false, errorMessage: 'โหลด snapshot ล้มเหลว: $e');
    }
  }

  Future<String?> generateDailySnapshot(String professionId) async {
    try {
      return await _repository.generateDailySnapshot(professionId);
    } catch (e, st) {
      debugPrint('[Phase2] generateDailySnapshot ERROR: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> getSnapshotComparison(String professionId, {String snapshotType = 'daily'}) async {
    try {
      return await _repository.getSnapshotComparison(professionId, snapshotType: snapshotType);
    } catch (e, st) {
      debugPrint('[Phase2] getSnapshotComparison ERROR: $e');
      return null;
    }
  }

  Future<void> loadKpiAggregations(String professionId, {String? category}) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final kpis = await _repository.getKpiAggregations(professionId, category: category);
      state = state.copyWith(isLoading: false, /* kpiAggregations: kpis */);
    } catch (e, st) {
      debugPrint('[Phase2] loadKpiAggregations ERROR: $e');
      state = state.copyWith(isLoading: false, errorMessage: 'โหลด KPI ล้มเหลว: $e');
    }
  }

  // ========================
  // PAYMENT CHANNELS
  // ========================

  Future<void> loadPaymentChannels(String professionId) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final channels = await _repository.getPaymentChannels(professionId);
      state = state.copyWith(isLoading: false, paymentChannels: channels);
    } catch (e, st) {
      debugPrint('[Phase2] loadPaymentChannels ERROR: $e');
      state = state.copyWith(isLoading: false, errorMessage: 'โหลดช่องทางชำระเงินล้มเหลว: $e');
    }
  }

  // ========================
  // PAYOUT BATCHES (Settlement Core)
  // ========================

  Future<void> loadPayoutBatches(String professionId) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final batches = await _repository.getPayoutBatches(professionId);
      state = state.copyWith(isLoading: false, payoutBatches: batches);
    } catch (e, st) {
      debugPrint('[Phase2] loadPayoutBatches ERROR: $e');
      state = state.copyWith(isLoading: false, errorMessage: 'โหลดรอบจ่ายล้มเหลว: $e');
    }
  }

  Future<void> loadPayoutBatchLines(String batchId) async {
    try {
      final lines = await _repository.getPayoutBatchLines(batchId);
      final updated = Map<String, List<PayoutBatchLine>>.from(state.payoutBatchLines);
      updated[batchId] = lines;
      state = state.copyWith(payoutBatchLines: updated);
    } catch (e, st) {
      debugPrint('[Phase2] loadPayoutBatchLines ERROR: $e');
    }
  }

  Future<bool> togglePaymentChannel(String channelId, bool enabled) async {
    state = state.copyWith(isSaving: true, clearError: true);
    try {
      final success = await _repository.updatePaymentChannelEnabled(channelId, enabled);
      if (success) {
        final updated = state.paymentChannels.map((c) {
          if (c.id == channelId) return c.copyWith(isEnabled: enabled);
          return c;
        }).toList();
        state = state.copyWith(isSaving: false, paymentChannels: updated);
      } else {
        state = state.copyWith(isSaving: false, errorMessage: 'อัปเดตช่องทางชำระเงินไม่สำเร็จ');
      }
      return success;
    } catch (e, st) {
      debugPrint('[Phase2] togglePaymentChannel ERROR: $e');
      state = state.copyWith(isSaving: false, errorMessage: 'อัปเดตช่องทางชำระเงินล้มเหลว: $e');
      return false;
    }
  }
}

// ========================
// Provider
// ========================
final phaseTwoProvider =
    StateNotifierProvider<PhaseTwoNotifier, PhaseTwoState>((ref) {
  final repo = ref.watch(phaseTwoRepositoryProvider);
  return PhaseTwoNotifier(repo);
});
