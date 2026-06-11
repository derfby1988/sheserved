import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../data/models/dashboard_theme.dart';
import '../../data/repositories/order_repository.dart';
import '../providers/phase_two_provider.dart';
import '../widgets/glass_card.dart';

final _orderRepoProvider = Provider<OrderRepository>((ref) {
  return OrderRepository(Supabase.instance.client);
});

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
  List<Map<String, dynamic>> _items = [];
  bool _isLoading = true;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _loadCart();
  }

  Future<void> _loadCart() async {
    final repo = ref.read(_orderRepoProvider);
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      setState(() => _isLoading = false);
      return;
    }

    final cart = await repo.getShoppingCart(user.id);
    final items = (cart?['items'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];
    setState(() {
      _items = items;
      _isLoading = false;
    });
  }

  Future<void> _saveCart() async {
    final repo = ref.read(_orderRepoProvider);
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    await repo.upsertShoppingCart(user.id, _items);
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
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? const Center(
                  child: Text(
                    'ตะกร้าว่างเปล่า\nเพิ่มสินค้าจากหน้าสินค้า',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _items.length,
                  itemBuilder: (context, index) {
                    final item = _items[index];
                    return _CartItemCard(
                      item: item,
                      onRemove: () {
                        setState(() => _items.removeAt(index));
                        _saveCart();
                      },
                    );
                  },
                ),
      bottomNavigationBar: _items.isEmpty || _isLoading
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
                            '฿${_total.toStringAsFixed(2)}',
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
                          onPressed: _isProcessing ? null : () => _checkout(),
                          child: _isProcessing
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

  double get _total {
    return _items.fold(0, (sum, item) {
      final price = (item['price'] as num?)?.toDouble() ?? 0;
      final qty = (item['quantity'] as int?) ?? 1;
      return sum + (price * qty);
    });
  }

  Future<void> _checkout() async {
    if (_items.isEmpty) return;

    final repo = ref.read(_orderRepoProvider);
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กรุณาเข้าสู่ระบบก่อนทำรายการ')),
      );
      return;
    }

    setState(() => _isProcessing = true);

    final order = await repo.createOrderFromCart(
      professionId: widget.professionId,
      userId: user.id,
      cartItems: _items,
      posMode: 'mode_a',
    );

    setState(() => _isProcessing = false);

    if (order != null && mounted) {
      // Clear cart
      setState(() => _items.clear());
      await _saveCart();

      // Navigate to checkout or success
      Navigator.of(context).pushNamed(
        '/erp/checkout',
        arguments: {'professionId': widget.professionId, 'orderId': order.id},
      );
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('สร้างรายการขายล้มเหลว กรุณาลองใหม่')),
      );
    }
  }
}

class _CartItemCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final VoidCallback onRemove;

  const _CartItemCard({
    required this.item,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final name = item['name'] as String? ?? 'สินค้า';
    final price = (item['price'] as num?)?.toDouble() ?? 0;
    final qty = (item['quantity'] as int?) ?? 1;

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
