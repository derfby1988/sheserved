import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../data/models/dashboard_theme.dart';
import '../../data/models/order.dart';
import '../../data/repositories/order_repository.dart';
import '../providers/phase_one_provider.dart';
import '../widgets/glass_card.dart';

final orderRepositoryProvider = Provider<OrderRepository>((ref) {
  return OrderRepository(Supabase.instance.client);
});

/// Counter POS Page (Mode B) — ขายหน้าร้านแบบเคาน์เตอร์
class CounterPosPage extends ConsumerStatefulWidget {
  final String professionId;

  const CounterPosPage({
    Key? key,
    required this.professionId,
  }) : super(key: key);

  @override
  ConsumerState<CounterPosPage> createState() => _CounterPosPageState();
}

class _CounterPosPageState extends ConsumerState<CounterPosPage> {
  final List<Map<String, dynamic>> _cartItems = [];
  String? _selectedCustomerId;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(phaseOneProvider.notifier).loadProducts(widget.professionId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(phaseOneProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('ขายหน้าร้าน / Counter POS'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Column(
        children: [
          // Product Grid
          Expanded(
            flex: 3,
            child: state.isLoading
                ? const Center(child: CircularProgressIndicator())
                : GridView.builder(
                    padding: const EdgeInsets.all(16),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      childAspectRatio: 1.2,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                    ),
                    itemCount: state.products.length,
                    itemBuilder: (context, index) {
                      final product = state.products[index];
                      return _ProductGridItem(
                        product: product,
                        onTap: () => _addToCart(product),
                      );
                    },
                  ),
          ),
          // Cart Summary
          Expanded(
            flex: 2,
            child: GlassCard(
              section: GlassSection.card,
              borderRadius: 24,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'รายการ',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        '${_cartItems.length} รายการ',
                        style: const TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: _cartItems.isEmpty
                        ? const Center(
                            child: Text(
                              'แตะสินค้าเพื่อเพิ่มลงตะกร้า',
                              style: TextStyle(color: Colors.grey),
                            ),
                          )
                        : ListView.builder(
                            itemCount: _cartItems.length,
                            itemBuilder: (context, index) {
                              final item = _cartItems[index];
                              return _CartListItem(
                                item: item,
                                onRemove: () => setState(() => _cartItems.removeAt(index)),
                              );
                            },
                          ),
                  ),
                  const Divider(),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('รวม', style: TextStyle(fontSize: 16)),
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
                      onPressed: _cartItems.isEmpty || _isProcessing ? null : () => _checkout(),
                      child: _isProcessing
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Text('ชำระเงิน'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  double get _total {
    return _cartItems.fold(0, (sum, item) {
      final price = (item['price'] as num?)?.toDouble() ?? 0;
      final qty = (item['quantity'] as int?) ?? 1;
      return sum + (price * qty);
    });
  }

  void _addToCart(dynamic product) {
    setState(() {
      final existingIndex = _cartItems.indexWhere(
        (item) => item['id'] == product.id,
      );
      if (existingIndex >= 0) {
        _cartItems[existingIndex]['quantity'] =
            (_cartItems[existingIndex]['quantity'] as int) + 1;
      } else {
        _cartItems.add({
          'id': product.id,
          'name': product.name,
          'price': product.salePrice,
          'quantity': 1,
        });
      }
    });
  }

  Future<void> _checkout() async {
    if (_cartItems.isEmpty) return;

    final repo = ref.read(orderRepositoryProvider);
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
      cartItems: _cartItems,
      posMode: 'mode_b_counter',
    );

    setState(() => _isProcessing = false);

    if (order != null && mounted) {
      // Clear cart
      setState(() => _cartItems.clear());

      // Navigate to order success
      Navigator.of(context).pushNamed(
        '/order/success',
        arguments: {'orderId': order.id},
      );
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('สร้างรายการขายล้มเหลว กรุณาลองใหม่')),
      );
    }
  }
}

class _ProductGridItem extends StatelessWidget {
  final dynamic product;
  final VoidCallback onTap;

  const _ProductGridItem({required this.product, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      section: GlassSection.card,
      borderRadius: 16,
      padding: const EdgeInsets.all(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.medication, size: 32),
            const SizedBox(height: 8),
            Text(
              product.name,
              maxLines: 2,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              '฿${product.salePrice.toStringAsFixed(0)}',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.green,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CartListItem extends StatelessWidget {
  final Map<String, dynamic> item;
  final VoidCallback onRemove;

  const _CartListItem({required this.item, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final name = item['name'] as String? ?? '';
    final price = (item['price'] as num?)?.toDouble() ?? 0;
    final qty = (item['quantity'] as int?) ?? 1;

    return ListTile(
      dense: true,
      title: Text(name, style: const TextStyle(fontSize: 14)),
      subtitle: Text('฿${price.toStringAsFixed(0)} x $qty'),
      trailing: Text(
        '฿${(price * qty).toStringAsFixed(0)}',
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      leading: IconButton(
        icon: const Icon(Icons.remove_circle_outline, color: Colors.red, size: 20),
        onPressed: onRemove,
      ),
    );
  }
}
