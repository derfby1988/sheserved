import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/dashboard_theme.dart';
import '../providers/phase_one_provider.dart';
import '../widgets/glass_card.dart';

class StockMovementTrackingPage extends ConsumerStatefulWidget {
  final String professionId;

  const StockMovementTrackingPage({
    super.key,
    required this.professionId,
  });

  @override
  ConsumerState<StockMovementTrackingPage> createState() => _StockMovementTrackingPageState();
}

class _StockMovementTrackingPageState extends ConsumerState<StockMovementTrackingPage> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      final notifier = ref.read(phaseOneProvider.notifier);
      notifier.loadStockMovements(widget.professionId);
      notifier.loadInventoryItems(widget.professionId);
      notifier.loadCustomMedications(widget.professionId);
    });
  }

  Future<void> _refresh() async {
    final notifier = ref.read(phaseOneProvider.notifier);
    notifier.loadStockMovements(widget.professionId);
    await Future.delayed(const Duration(milliseconds: 400));
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(phaseOneProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('ประวัติสต็อก'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: state.isLoading && state.stockMovements.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : state.stockMovements.isEmpty
                ? const Center(child: Text('ไม่มีประวัติการเคลื่อนไหวสต็อก'))
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: state.stockMovements.length,
                    itemBuilder: (context, index) {
                      final m = state.stockMovements[index];
                      final movementType = m['movement_type'] as String? ?? 'unknown';
                      final quantity = m['quantity'] as int? ?? 0;
                      final productId = m['product_id'] as String?;
                      final customMedId = m['custom_medication_id'] as String?;
                      final createdAt = DateTime.tryParse(m['created_at'] as String? ?? '');
                      final notes = m['notes'] as String?;

                      final itemName = _resolveItemName(
                        productId: productId,
                        customMedId: customMedId,
                        products: state.products,
                        medications: state.customMedications,
                      );

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: GlassCard(
                          section: GlassSection.card,
                          borderRadius: 12,
                          padding: const EdgeInsets.all(14),
                          child: Row(
                            children: [
                              Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  color: _movementColor(movementType).withValues(alpha: 0.15),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  _movementIcon(movementType),
                                  color: _movementColor(movementType),
                                  size: 24,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      itemName,
                                      style: const TextStyle(fontWeight: FontWeight.w600),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${_movementLabel(movementType)} · ${quantity > 0 ? '+' : ''}$quantity หน่วย',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: quantity >= 0 ? Colors.green : Colors.red,
                                      ),
                                    ),
                                    if (notes != null && notes.isNotEmpty)
                                      Text(
                                        notes,
                                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    if (createdAt != null)
                                      Text(
                                        '${createdAt.day}/${createdAt.month}/${createdAt.year} ${createdAt.hour.toString().padLeft(2, '0')}:${createdAt.minute.toString().padLeft(2, '0')}',
                                        style: const TextStyle(fontSize: 11, color: Colors.grey),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
      ),
    );
  }
}

String _resolveItemName({
  String? productId,
  String? customMedId,
  required List<dynamic> products,
  required List<dynamic> medications,
}) {
  if (productId != null) {
    for (final p in products) {
      if (p.id == productId) return p.name as String;
    }
  }
  if (customMedId != null) {
    for (final m in medications) {
      if (m.id == customMedId) return m.name as String;
    }
  }
  return 'สินค้า #${productId ?? customMedId ?? 'unknown'}';
}

IconData _movementIcon(String type) {
  return switch (type) {
    'receipt' => Icons.arrow_downward,
    'sale' => Icons.shopping_bag,
    'adjustment' => Icons.tune,
    'transfer_in' => Icons.arrow_forward,
    'transfer_out' => Icons.arrow_back,
    'expired' => Icons.warning,
    'damaged' => Icons.broken_image,
    _ => Icons.swap_horiz,
  };
}

Color _movementColor(String type) {
  return switch (type) {
    'receipt' || 'transfer_in' || 'return_in' => Colors.green,
    'sale' || 'transfer_out' || 'return_out' || 'expired' || 'damaged' => Colors.red,
    'adjustment' => Colors.orange,
    _ => Colors.blue,
  };
}

String _movementLabel(String type) {
  return switch (type) {
    'receipt' => 'รับเข้า',
    'sale' => 'ขาย',
    'adjustment' => 'ปรับสต็อก',
    'transfer_in' => 'โอนเข้า',
    'transfer_out' => 'โอนออก',
    'expired' => 'หมดอายุ',
    'damaged' => 'เสียหาย',
    'return_in' => 'รับคืน',
    'return_out' => 'คืนผู้จำหน่าย',
    'initial_stock' => 'ยกยอด',
    _ => type,
  };
}
