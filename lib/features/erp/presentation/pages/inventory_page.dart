import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/dashboard_theme.dart';
import '../../data/models/inventory_lot.dart';
import '../providers/phase_one_provider.dart';
import '../widgets/glass_card.dart';

class InventoryPage extends ConsumerStatefulWidget {
  final String professionId;

  const InventoryPage({
    Key? key,
    required this.professionId,
  }) : super(key: key);

  @override
  ConsumerState<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends ConsumerState<InventoryPage> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      final notifier = ref.read(phaseOneProvider.notifier);
      notifier.loadInventoryLots(widget.professionId);
      notifier.loadProducts(widget.professionId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(phaseOneProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('คลังสินค้า / Inventory'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: state.isLoading
          ? const Center(child: CircularProgressIndicator())
          : state.errorMessage != null
              ? Center(child: Text('Error: ${state.errorMessage}'))
              : DefaultTabController(
                  length: 3,
                  child: Column(
                    children: [
                      const TabBar(
                        tabs: [
                          Tab(text: 'Lots'),
                          Tab(text: 'หมดอายุ'),
                          Tab(text: 'รับเข้า'),
                        ],
                      ),
                      Expanded(
                        child: TabBarView(
                          children: [
                            _LotsTab(lots: state.inventoryLots),
                            _ExpiryTab(lots: state.expiringLots + state.expiredLots),
                            _ReceiptTab(
                              professionId: widget.professionId,
                              products: state.products,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }
}

class _LotsTab extends StatelessWidget {
  final List<InventoryLot> lots;

  const _LotsTab({required this.lots});

  @override
  Widget build(BuildContext context) {
    if (lots.isEmpty) {
      return const Center(child: Text('ไม่มีข้อมูล Lot'));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: lots.length,
      itemBuilder: (context, index) {
        final lot = lots[index];
        return _LotCard(lot: lot);
      },
    );
  }
}

class _LotCard extends StatelessWidget {
  final InventoryLot lot;

  const _LotCard({required this.lot});

  @override
  Widget build(BuildContext context) {
    Color statusColor = Colors.green;
    if (lot.status == 'expired') statusColor = Colors.red;
    if (lot.status == 'depleted') statusColor = Colors.grey;
    if (lot.status == 'quarantined') statusColor = Colors.orange;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassCard(
        section: GlassSection.card,
        borderRadius: 16,
        padding: const EdgeInsets.all(14),
        child: ListTile(
          title: Text('Lot: ${lot.lotNumber}', style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('คงเหลือ: ${lot.quantityRemaining} / ${lot.quantityReceived}'),
              if (lot.expiryDate != null)
                Text(
                  'หมดอายุ: ${lot.expiryDate!.toLocal().toString().split(' ')[0]}',
                  style: TextStyle(color: lot.isNearExpiry ? Colors.orange : null),
                ),
              Text('ต้นทุน: ฿${lot.unitCost.toStringAsFixed(2)}'),
            ],
          ),
          trailing: Chip(
            label: Text(lot.statusLabel, style: const TextStyle(fontSize: 11)),
            backgroundColor: statusColor.withOpacity(0.15),
            side: BorderSide(color: statusColor.withOpacity(0.5)),
          ),
        ),
      ),
    );
  }
}

class _ExpiryTab extends StatelessWidget {
  final List<InventoryLot> lots;

  const _ExpiryTab({required this.lots});

  @override
  Widget build(BuildContext context) {
    if (lots.isEmpty) {
      return const Center(child: Text('ไม่มีสินค้าใกล้หมดอายุ'));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: lots.length,
      itemBuilder: (context, index) {
        final lot = lots[index];
        return _LotCard(lot: lot);
      },
    );
  }
}

class _ReceiptTab extends ConsumerStatefulWidget {
  final String professionId;
  final List<dynamic> products;

  const _ReceiptTab({
    required this.professionId,
    required this.products,
  });

  @override
  ConsumerState<_ReceiptTab> createState() => _ReceiptTabState();
}

class _ReceiptTabState extends ConsumerState<_ReceiptTab> {
  String? _selectedProductId;
  final _lotController = TextEditingController();
  final _qtyController = TextEditingController();
  final _costController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          DropdownButtonFormField<String>(
            decoration: const InputDecoration(labelText: 'เลือกสินค้า'),
            value: _selectedProductId,
            items: widget.products.map<DropdownMenuItem<String>>((p) {
              return DropdownMenuItem(value: p.id as String, child: Text(p.name as String));
            }).toList(),
            onChanged: (v) => setState(() => _selectedProductId = v),
          ),
          TextField(controller: _lotController, decoration: const InputDecoration(labelText: 'Lot Number')),
          TextField(controller: _qtyController, decoration: const InputDecoration(labelText: 'จำนวน'), keyboardType: TextInputType.number),
          TextField(controller: _costController, decoration: const InputDecoration(labelText: 'ต้นทุนต่อหน่วย'), keyboardType: TextInputType.number),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _selectedProductId == null ? null : () => _submitReceipt(),
              child: const Text('บันทึกรับเข้า'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _submitReceipt() async {
    final notifier = ref.read(phaseOneProvider.notifier);
    final success = await notifier.recordStockReceipt(
      professionId: widget.professionId,
      productId: _selectedProductId!,
      branchId: null,
      warehouseLocationId: null,
      lotNumber: _lotController.text.trim(),
      quantity: int.tryParse(_qtyController.text) ?? 0,
      unitCost: double.tryParse(_costController.text) ?? 0,
    );

    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('บันทึกรับเข้าสำเร็จ')),
      );
      notifier.loadInventoryLots(widget.professionId);
      _lotController.clear();
      _qtyController.clear();
      _costController.clear();
    }
  }
}
