import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../data/models/dashboard_theme.dart';
import '../providers/phase_two_provider.dart';
import '../widgets/glass_card.dart';

class CartPage extends ConsumerStatefulWidget {
  final String professionId;

  const CartPage({
    Key? key,
    required this.professionId,
  }) : super(key: key);

  @override
  ConsumerState<CartPage> createState() => _CartPageState();
}

class _CartPageState extends ConsumerState<CartPage> {
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _loadCart();
  }

  Future<void> _loadCart() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    await ref.read(phaseTwoProvider.notifier).loadCart(user.id);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(phaseTwoProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('ตะกร้าสินค้า / Cart'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: state.isLoading
          ? const Center(child: CircularProgressIndicator())
          : state.cartItems.isEmpty
              ? const Center(
                  child: Text(
                    'ตะกร้าว่างเปล่า\nเพิ่มสินค้าจากหน้าสินค้า',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: state.cartItems.length,
                  itemBuilder: (context, index) {
                    final item = state.cartItems[index];
                    return _CartItemCard(
                      item: item,
                      onRemove: () async {
                        final success = await ref.read(phaseTwoProvider.notifier).removeItemFromCart(item.id);
                        if (!success && mounted) {
                          _showSnackBar('ลบสินค้าล้มเหลว');
                        }
                      },
                    );
                  },
                ),
      bottomNavigationBar: state.cartItems.isEmpty || state.isLoading
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: GlassCard(
                  section: GlassSection.card,
                  borderRadius: 16,
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('รวมทั้งสิ้น', style: TextStyle(fontSize: 16)),
                          Text(
                            '฿${state.cartTotal.toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: state.isSaving || _isProcessing ? null : () => _checkout(),
                          child: state.isSaving || _isProcessing
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Text('ดำเนินการชำระเงิน'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  Future<void> _checkout() async {
    final state = ref.read(phaseTwoProvider);
    if (state.cartItems.isEmpty) return;

    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      _showSnackBar('กรุณาเข้าสู่ระบบก่อนทำรายการ');
      return;
    }

    setState(() => _isProcessing = true);

    // Create checkout session from cart
    final cartSnapshot = state.cartItems.map((i) => i.toJson()).toList();
    final session = await ref.read(phaseTwoProvider.notifier).startCheckout(
      professionId: widget.professionId,
      userId: user.id,
      cartSnapshot: {'items': cartSnapshot},
      totalAmount: state.cartTotal,
    );

    setState(() => _isProcessing = false);

    if (session != null && mounted) {
      Navigator.of(context).pushNamed(
        '/erp/checkout',
        arguments: {'professionId': widget.professionId, 'sessionId': session.id},
      );
    } else if (mounted) {
      _showSnackBar('สร้าง checkout session ล้มเหลว กรุณาลองใหม่');
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _CartItemCard extends StatelessWidget {
  final dynamic item;
  final VoidCallback onRemove;

  const _CartItemCard({
    required this.item,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final name = item.productName;
    final price = item.unitPrice;
    final qty = item.quantity;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassCard(
        section: GlassSection.card,
        borderRadius: 12,
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text('฿${price.toStringAsFixed(2)} x $qty'),
                ],
              ),
            ),
            Text(
              '฿${(price * qty).toStringAsFixed(2)}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            IconButton(
              onPressed: onRemove,
              icon: const Icon(Icons.delete_outline, color: Colors.red),
            ),
          ],
        ),
      ),
    );
  }
}
