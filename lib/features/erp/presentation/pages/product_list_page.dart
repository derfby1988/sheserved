import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/dashboard_theme.dart';
import '../../data/models/product.dart';
import '../providers/phase_one_provider.dart';
import '../widgets/glass_card.dart';

class ProductListPage extends ConsumerStatefulWidget {
  final String professionId;

  const ProductListPage({
    Key? key,
    required this.professionId,
  }) : super(key: key);

  @override
  ConsumerState<ProductListPage> createState() => _ProductListPageState();
}

class _ProductListPageState extends ConsumerState<ProductListPage> {
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
        title: const Text('สินค้า / บริการ'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: state.isLoading
          ? const Center(child: CircularProgressIndicator())
          : state.errorMessage != null
              ? Center(child: Text('Error: ${state.errorMessage}'))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: state.products.length,
                  itemBuilder: (context, index) {
                    final product = state.products[index];
                    return _ProductCard(
                      product: product,
                      onTap: () => _showProductDetail(product),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCreateProductDialog(),
        icon: const Icon(Icons.add),
        label: const Text('เพิ่มสินค้า'),
      ),
    );
  }

  void _showProductDetail(Product product) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _ProductDetailSheet(product: product),
    );
  }

  void _showCreateProductDialog() {
    // Simplified — ใน production ควรมีฟอร์มเต็ม
    final nameController = TextEditingController();
    final skuController = TextEditingController();
    final priceController = TextEditingController();
    final costController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('เพิ่มสินค้าใหม่'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameController, decoration: const InputDecoration(labelText: 'ชื่อสินค้า')),
            TextField(controller: skuController, decoration: const InputDecoration(labelText: 'SKU')),
            TextField(controller: costController, decoration: const InputDecoration(labelText: 'ต้นทุน'), keyboardType: TextInputType.number),
            TextField(controller: priceController, decoration: const InputDecoration(labelText: 'ราคาขาย'), keyboardType: TextInputType.number),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('ยกเลิก')),
          ElevatedButton(
            onPressed: () async {
              final notifier = ref.read(phaseOneProvider.notifier);
              final success = await notifier.createProduct({
                'profession_id': widget.professionId,
                'name': nameController.text.trim(),
                'sku': skuController.text.trim(),
                'cost_price': double.tryParse(costController.text) ?? 0,
                'sale_price': double.tryParse(priceController.text) ?? 0,
              });
              if (success && mounted) {
                Navigator.pop(context);
                notifier.loadProducts(widget.professionId);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('เพิ่มสินค้าสำเร็จ')),
                );
              }
            },
            child: const Text('บันทึก'),
          ),
        ],
      ),
    );
  }
}

class _ProductCard extends StatelessWidget {
  final Product product;
  final VoidCallback onTap;

  const _ProductCard({required this.product, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassCard(
        section: GlassSection.card,
        borderRadius: 16,
        padding: const EdgeInsets.all(14),
        child: ListTile(
          title: Text(product.name, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('SKU: ${product.sku ?? '-'}'),
              Text('ราคา: ฿${product.salePrice.toStringAsFixed(2)}'),
            ],
          ),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                product.isStockable ? 'Stock' : 'Service',
                style: TextStyle(
                  fontSize: 11,
                  color: product.isStockable ? Colors.green : Colors.blue,
                ),
              ),
              if (product.hasLotTracking)
                const Text('FEFO', style: TextStyle(fontSize: 10, color: Colors.orange)),
            ],
          ),
          onTap: onTap,
        ),
      ),
    );
  }
}

class _ProductDetailSheet extends StatelessWidget {
  final Product product;

  const _ProductDetailSheet({required this.product});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(product.name, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text('SKU: ${product.sku ?? '-'}'),
          Text('Barcode: ${product.barcode ?? '-'}'),
          const SizedBox(height: 12),
          Row(
            children: [
              _InfoChip(label: 'ต้นทุน', value: '฿${product.costPrice.toStringAsFixed(2)}'),
              const SizedBox(width: 8),
              _InfoChip(label: 'ราคาขาย', value: '฿${product.salePrice.toStringAsFixed(2)}'),
              const SizedBox(width: 8),
              _InfoChip(label: 'Margin', value: '${product.profitMargin.toStringAsFixed(1)}%'),
            ],
          ),
          const SizedBox(height: 12),
          if (product.isStockable) ...[
            Text('จุดสั่งซื้อใหม่: ${product.reorderPoint} | จำนวนสั่ง: ${product.reorderQty}'),
            if (product.shelfLifeDays != null)
              Text('อายุการเก็บ: ${product.shelfLifeDays} วัน'),
          ],
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final String label;
  final String value;

  const _InfoChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
