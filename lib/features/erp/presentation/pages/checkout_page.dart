import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../data/models/dashboard_theme.dart';
import '../../data/repositories/order_repository.dart';
import '../providers/phase_one_provider.dart';
import '../providers/phase_two_provider.dart';
import '../widgets/glass_card.dart';

final _orderRepoProvider = Provider<OrderRepository>((ref) {
  return OrderRepository(Supabase.instance.client);
});

class CheckoutPage extends ConsumerStatefulWidget {
  final String professionId;
  final String? sessionId;

  const CheckoutPage({
    Key? key,
    required this.professionId,
    this.sessionId,
  }) : super(key: key);

  @override
  ConsumerState<CheckoutPage> createState() => _CheckoutPageState();
}

class _CheckoutPageState extends ConsumerState<CheckoutPage> {
  String _selectedMethod = 'promptpay';

  @override
  void initState() {
    super.initState();
    if (widget.sessionId != null) {
      // Load checkout session data if needed
    }
    Future.microtask(() {
      ref.read(phaseTwoProvider.notifier).loadPaymentChannels(widget.professionId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(phaseTwoProvider);
    final cartTotal = state.cartTotal;
    final vat = cartTotal * 0.07;
    final discount = 0.0;
    final netTotal = cartTotal + vat - discount;

    return Scaffold(
      appBar: AppBar(
        title: const Text('ชำระเงิน / Checkout'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: state.isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildPaymentMethods(),
                const SizedBox(height: 20),
                _buildSummary(cartTotal, discount, vat, netTotal),
              ],
            ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: ElevatedButton(
            onPressed: state.isSaving ? null : () => _confirmPayment(netTotal),
            child: state.isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('ยืนยันการชำระเงิน'),
          ),
        ),
      ),
    );
  }

  Widget _buildPaymentMethods() {
    final state = ref.watch(phaseTwoProvider);
    final channels = state.paymentChannels;

    // Fallback to hardcoded if no channels loaded yet
    final methods = channels.isNotEmpty
        ? channels.map((c) => _PaymentMethod(
            c.channelCode,
            c.channelName,
            _resolveIcon(c.iconName),
          )).toList()
        : [
            _PaymentMethod('promptpay', 'PromptPay QR', Icons.qr_code),
            _PaymentMethod('cash', 'เงินสด', Icons.money),
            _PaymentMethod('credit_card', 'บัตรเครดิต', Icons.credit_card),
          ];

    // Auto-select first method if current selection not available
    if (methods.isNotEmpty && !methods.any((m) => m.value == _selectedMethod)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _selectedMethod = methods.first.value);
      });
    }

    return GlassCard(
      section: GlassSection.card,
      borderRadius: 16,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'วิธีชำระเงิน',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          if (methods.isEmpty)
            const Text('ไม่มีช่องทางชำระเงินที่เปิดใช้งาน', style: TextStyle(color: Colors.grey))
          else
            ...methods.map((m) => RadioListTile<String>(
                  title: Row(
                    children: [
                      Icon(m.icon),
                      const SizedBox(width: 12),
                      Text(m.label),
                    ],
                  ),
                  value: m.value,
                  groupValue: _selectedMethod,
                  onChanged: (v) => setState(() => _selectedMethod = v!),
                )),
        ],
      ),
    );
  }

  IconData _resolveIcon(String? name) {
    switch (name) {
      case 'qr_code':
        return Icons.qr_code;
      case 'credit_card':
        return Icons.credit_card;
      case 'money':
        return Icons.money;
      case 'account_balance':
        return Icons.account_balance;
      case 'wallet':
        return Icons.account_balance_wallet;
      default:
        return Icons.payment;
    }
  }

  Widget _buildSummary(double subtotal, double discount, double vat, double netTotal) {
    return GlassCard(
      section: GlassSection.card,
      borderRadius: 16,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'สรุปรายการ',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          _buildSummaryRow('ยอดรวม', '฿${subtotal.toStringAsFixed(2)}'),
          _buildSummaryRow('ส่วนลด', '-฿${discount.toStringAsFixed(2)}'),
          _buildSummaryRow('VAT (7%)', '฿${vat.toStringAsFixed(2)}'),
          const Divider(),
          _buildSummaryRow('ยอดสุทธิ', '฿${netTotal.toStringAsFixed(2)}', isTotal: true),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(String label, String value, {bool isTotal = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: isTotal ? 16 : 14)),
          Text(
            value,
            style: TextStyle(
              fontSize: isTotal ? 18 : 14,
              fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmPayment(double amount) async {
    if (widget.sessionId == null) {
      _showSnackBar('ไม่พบ checkout session');
      return;
    }

    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      _showSnackBar('กรุณาเข้าสู่ระบบก่อนทำรายการ');
      return;
    }

    final notifier = ref.read(phaseTwoProvider.notifier);
    final cartState = ref.read(phaseTwoProvider);
    final cartItems = cartState.cartItems;

    if (cartItems.isEmpty) {
      _showSnackBar('ตะกร้าว่างเปล่า');
      return;
    }

    final orderRepo = ref.read(_orderRepoProvider);
    final phaseOneRepo = ref.read(phaseOneRepositoryProvider);

    // --- 0. Update checkout session to payment_pending ---
    await notifier.updateCheckoutSessionStatus(
      widget.sessionId!,
      'payment_pending',
      paymentMethod: _selectedMethod,
    );

    // --- 1. Reserve stock for each cart item ---
    final reservationIds = <String>[];
    for (final item in cartItems) {
      final rid = await phaseOneRepo.createInventoryReservation(
        professionId: widget.professionId,
        productId: item.productId,
        quantity: item.quantity,
        reservationType: 'cart',
        referenceId: widget.sessionId!,
        expiresAt: DateTime.now().add(const Duration(minutes: 15)),
      );
      if (rid == null) {
        for (final existingId in reservationIds) {
          await phaseOneRepo.releaseStockReservation(existingId);
        }
        _showSnackBar('สินค้า ${item.productName} มีไม่เพียงพอ');
        return;
      }
      reservationIds.add(rid);
    }

    // 2. Create real order from cart
    final order = await orderRepo.createOrderFromCart(
      professionId: widget.professionId,
      userId: user.id,
      cartItems: cartItems.map((i) => i.toJson()).toList(),
      posMode: 'mode_b_counter',
    );

    if (order == null) {
      for (final rid in reservationIds) {
        await phaseOneRepo.releaseStockReservation(rid);
      }
      _showSnackBar('สร้างรายการขายล้มเหลว');
      return;
    }

    // 3. Confirm checkout session with real order_id
    final confirmed = await notifier.confirmCheckout(widget.sessionId!, order.id);
    if (!confirmed) {
      for (final rid in reservationIds) {
        await phaseOneRepo.releaseStockReservation(rid);
      }
      _showSnackBar('ยืนยัน checkout ล้มเหลว');
      return;
    }

    // 4. Create payment transaction with REAL order_id + checkout_session link
    final txn = await notifier.createPaymentTransaction(
      professionId: widget.professionId,
      orderId: order.id,
      userId: user.id,
      amount: amount,
      paymentMethod: _selectedMethod,
      checkoutSessionId: widget.sessionId,
    );

    if (txn == null && mounted) {
      for (final rid in reservationIds) {
        await phaseOneRepo.releaseStockReservation(rid);
      }
      _showSnackBar('ชำระเงินล้มเหลว กรุณาลองใหม่');
      return;
    }

    // 4a. Auto-calculate settlement allocation (fee split)
    if (txn != null) {
      await notifier.calculatePaymentAllocation(
        orderId: order.id,
        paymentTxnId: txn.id,
        grossAmount: amount,
      );
    }

    // 5. Update order status to paid
    await orderRepo.updateOrderStatus(order.id, 'paid');

    // 6. Deduct stock only after payment success
    for (final rid in reservationIds) {
      await phaseOneRepo.deductStock(
        reservationId: rid,
        orderId: order.id,
      );
    }

    if (mounted) {
      _showSnackBar('ชำระเงินสำเร็จ');
      notifier.clearCart();
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _PaymentMethod {
  final String value;
  final String label;
  final IconData icon;

  _PaymentMethod(this.value, this.label, this.icon);
}
