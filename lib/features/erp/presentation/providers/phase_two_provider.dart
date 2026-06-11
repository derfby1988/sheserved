import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../data/models/checkout_session.dart';
import '../../data/models/payment_transaction.dart';
import '../../data/models/delivery_order.dart';
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

  final CheckoutSession? activeCheckout;
  final List<PaymentTransaction> transactions;
  final List<DeliveryOrder> deliveryOrders;

  PhaseTwoState({
    this.isLoading = false,
    this.isSaving = false,
    this.errorMessage,
    this.activeCheckout,
    this.transactions = const [],
    this.deliveryOrders = const [],
  });

  PhaseTwoState copyWith({
    bool? isLoading,
    bool? isSaving,
    String? errorMessage,
    bool clearError = false,
    CheckoutSession? activeCheckout,
    bool clearCheckout = false,
    List<PaymentTransaction>? transactions,
    List<DeliveryOrder>? deliveryOrders,
  }) {
    final shouldClearError = clearError ||
        ((isLoading != null && !isLoading) || (isSaving != null && !isSaving));
    return PhaseTwoState(
      isLoading: isLoading ?? this.isLoading,
      isSaving: isSaving ?? this.isSaving,
      errorMessage: shouldClearError ? null : (errorMessage ?? this.errorMessage),
      activeCheckout: clearCheckout ? null : (activeCheckout ?? this.activeCheckout),
      transactions: transactions ?? this.transactions,
      deliveryOrders: deliveryOrders ?? this.deliveryOrders,
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

  Future<bool> createDeliveryOrder(Map<String, dynamic> data) async {
    state = state.copyWith(isSaving: true, clearError: true);
    try {
      final order = await _repository.createDeliveryOrder(data);
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
}

// ========================
// Provider
// ========================
final phaseTwoProvider =
    StateNotifierProvider<PhaseTwoNotifier, PhaseTwoState>((ref) {
  final repo = ref.watch(phaseTwoRepositoryProvider);
  return PhaseTwoNotifier(repo);
});
