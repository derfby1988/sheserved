import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/dashboard_theme.dart';
import '../../data/models/inventory_item.dart';
import '../../data/models/inventory_alert.dart';
import '../../data/models/inventory_transfer.dart';
import '../../data/models/product.dart';
import '../../data/models/custom_medication.dart';
import '../../data/models/stock_adjustment.dart';
import '../../data/models/stocktake_session.dart';
import '../providers/phase_one_provider.dart';
import '../widgets/glass_card.dart';

class InventoryPage extends ConsumerStatefulWidget {
  final String professionId;

  const InventoryPage({
    super.key,
    required this.professionId,
  });

  @override
  ConsumerState<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends ConsumerState<InventoryPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 6, vsync: this);
    Future.microtask(() => _loadAll());
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _loadAll() {
    final notifier = ref.read(phaseOneProvider.notifier);
    notifier.loadInventoryItems(widget.professionId);
    notifier.loadInventoryAlerts(widget.professionId);
    notifier.loadStocktakeSessions(widget.professionId);
    notifier.loadInventoryTransfers(widget.professionId);
    notifier.loadStockAdjustments(widget.professionId);
    notifier.loadProducts(widget.professionId);
    notifier.loadInventoryLots(widget.professionId);
  }

  Future<void> _refresh() async {
    _loadAll();
    await Future.delayed(const Duration(milliseconds: 800));
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(phaseOneProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('คลังสินค้า / Inventory'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: const [
            Tab(text: 'สต็อก'),
            Tab(text: 'แจ้งเตือน'),
            Tab(text: 'ตรวจนับ'),
            Tab(text: 'โอนย้าย'),
            Tab(text: 'ปรับสต็อก'),
            Tab(text: 'รับเข้า'),
          ],
        ),
      ),
      body: state.isLoading && state.inventoryItems.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : state.errorMessage != null && state.inventoryItems.isEmpty
              ? Center(child: Text('Error: ${state.errorMessage}'))
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _StockTab(
                      items: state.inventoryItems,
                      products: state.products,
                      medications: state.customMedications,
                      onRefresh: _refresh,
                    ),
                    _AlertsTab(alerts: state.inventoryAlerts, onRefresh: _refresh),
                    _StocktakeTab(
                      sessions: state.stocktakeSessions,
                      onRefresh: _refresh,
                      onComplete: _completeStocktake,
                    ),
                    _TransfersTab(
                      transfers: state.inventoryTransfers,
                      onRefresh: _refresh,
                      onComplete: _completeTransfer,
                    ),
                    _AdjustmentsTab(
                      adjustments: state.stockAdjustments,
                      onRefresh: _refresh,
                    ),
                    _ReceiptTab(
                      professionId: widget.professionId,
                      products: state.products,
                      onRefresh: _refresh,
                    ),
                  ],
                ),
      floatingActionButton: AnimatedBuilder(
        animation: _tabController,
        builder: (context, child) {
          final index = _tabController.index;
          if (index == 3) {
            return FloatingActionButton(
              onPressed: () => _showCreateTransferDialog(),
              child: const Icon(Icons.swap_horiz),
            );
          }
          if (index == 4) {
            return FloatingActionButton(
              onPressed: () => _showCreateAdjustmentDialog(),
              child: const Icon(Icons.tune),
            );
          }
          return const SizedBox.shrink();
        },
      ),
    );
  }

  Future<void> _completeStocktake(String sessionId) async {
    final success = await ref.read(phaseOneProvider.notifier).completeStocktakeSession(
      sessionId: sessionId,
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(success != null ? 'ปิดรอบตรวจนับสำเร็จ (ส่วนต่าง $success รายการ)' : 'ปิดรอบตรวจนับล้มเหลว')),
      );
    }
    if (success != null) await _refresh();
  }

  Future<void> _completeTransfer(String transferId) async {
    final success = await ref.read(phaseOneProvider.notifier).completeInventoryTransfer(
      transferId: transferId,
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(success ? 'ยืนยันโอนย้ายสำเร็จ' : 'ยืนยันโอนย้ายล้มเหลว')),
      );
    }
    if (success) await _refresh();
  }

  void _showCreateAdjustmentDialog() {
    final state = ref.read(phaseOneProvider);
    if (state.inventoryItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ไม่มีสินค้าในสต็อก')),
      );
      return;
    }
    String? selectedItemId;
    String adjustmentType = 'count';
    final qtyController = TextEditingController();
    final reasonController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ปรับสต็อก'),
        content: StatefulBuilder(
          builder: (ctx, setState) => SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(labelText: 'สินค้า'),
                  items: state.inventoryItems.map((i) {
                    final name = _resolveItemName(i, state.products, state.customMedications);
                    return DropdownMenuItem(value: i.id, child: Text('$name (คงเหลือ ${i.quantity})'));
                  }).toList(),
                  onChanged: (v) => setState(() => selectedItemId = v),
                ),
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(labelText: 'ประเภท'),
                  initialValue: adjustmentType,
                  items: const [
                    DropdownMenuItem(value: 'count', child: Text('ตรวจนับ')),
                    DropdownMenuItem(value: 'damage', child: Text('เสียหาย')),
                    DropdownMenuItem(value: 'expired', child: Text('หมดอายุ')),
                    DropdownMenuItem(value: 'found', child: Text('พบเพิ่ม')),
                    DropdownMenuItem(value: 'lost', child: Text('สูญหาย')),
                    DropdownMenuItem(value: 'other', child: Text('อื่นๆ')),
                  ],
                  onChanged: (v) => setState(() => adjustmentType = v ?? 'count'),
                ),
                TextField(
                  controller: qtyController,
                  decoration: const InputDecoration(labelText: 'จำนวนหลังปรับ'),
                  keyboardType: TextInputType.number,
                ),
                TextField(
                  controller: reasonController,
                  decoration: const InputDecoration(labelText: 'เหตุผล (ถ้ามี)'),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('ยกเลิก')),
          TextButton(
            onPressed: () async {
              if (selectedItemId == null) return;
              final qty = int.tryParse(qtyController.text);
              if (qty == null) return;
              final messenger = ScaffoldMessenger.of(context);
              Navigator.of(ctx).pop();
              final id = await ref.read(phaseOneProvider.notifier).createStockAdjustment(
                professionId: widget.professionId,
                inventoryItemId: selectedItemId!,
                adjustmentType: adjustmentType,
                quantityAfter: qty,
                reason: reasonController.text.trim().isEmpty ? null : reasonController.text.trim(),
              );
              if (mounted) {
                messenger.showSnackBar(
                  SnackBar(content: Text(id != null ? 'ปรับสต็อกสำเร็จ' : 'ปรับสต็อกล้มเหลว')),
                );
              }
              if (id != null) await _refresh();
            },
            child: const Text('บันทึก'),
          ),
        ],
      ),
    );
  }

  void _showCreateTransferDialog() {
    final state = ref.read(phaseOneProvider);
    if (state.inventoryItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ไม่มีสินค้าในสต็อก')),
      );
      return;
    }
    final selectedItems = <Map<String, dynamic>>[];
    String? currentItemId;
    final qtyController = TextEditingController();
    final notesController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('สร้างรายการโอนย้าย'),
        content: StatefulBuilder(
          builder: (ctx, setState) => SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('เลือกสินค้าและจำนวน', style: TextStyle(fontWeight: FontWeight.w600)),
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(labelText: 'สินค้า'),
                  items: state.inventoryItems.map((i) {
                    final name = _resolveItemName(i, state.products, state.customMedications);
                    return DropdownMenuItem(value: i.id, child: Text('$name (คงเหลือ ${i.quantity})'));
                  }).toList(),
                  onChanged: (v) => currentItemId = v,
                ),
                TextField(
                  controller: qtyController,
                  decoration: const InputDecoration(labelText: 'จำนวน'),
                  keyboardType: TextInputType.number,
                ),
                TextButton(
                  onPressed: () {
                    if (currentItemId == null) return;
                    final qty = int.tryParse(qtyController.text);
                    if (qty == null || qty <= 0) return;
                    setState(() {
                      selectedItems.add({'inventory_item_id': currentItemId!, 'quantity': qty});
                      qtyController.clear();
                    });
                  },
                  child: const Text('เพิ่มรายการ'),
                ),
                if (selectedItems.isNotEmpty)
                  ...selectedItems.map((item) {
                    final id = item['inventory_item_id'] as String;
                    final qty = item['quantity'] as int;
                    final name = _resolveItemName(
                      state.inventoryItems.firstWhere((i) => i.id == id),
                      state.products,
                      state.customMedications,
                    );
                    return ListTile(
                      dense: true,
                      title: Text(name, style: const TextStyle(fontSize: 13)),
                      trailing: Text('x$qty', style: const TextStyle(fontSize: 13)),
                    );
                  }),
                TextField(
                  controller: notesController,
                  decoration: const InputDecoration(labelText: 'หมายเหตุ (ถ้ามี)'),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('ยกเลิก')),
          TextButton(
            onPressed: () async {
              if (selectedItems.isEmpty) return;
              final messenger = ScaffoldMessenger.of(context);
              Navigator.of(ctx).pop();
              final id = await ref.read(phaseOneProvider.notifier).createInventoryTransfer(
                professionId: widget.professionId,
                items: selectedItems,
                notes: notesController.text.trim().isEmpty ? null : notesController.text.trim(),
              );
              if (mounted) {
                messenger.showSnackBar(
                  SnackBar(content: Text(id != null ? 'สร้างรายการโอนย้ายสำเร็จ' : 'สร้างรายการโอนย้ายล้มเหลว')),
                );
              }
              if (id != null) await _refresh();
            },
            child: const Text('บันทึก'),
          ),
        ],
      ),
    );
  }
}

// ========================
// Helpers
// ========================

String _resolveItemName(
  InventoryItem item,
  List<Product> products,
  List<CustomMedication> medications,
) {
  if (item.productId != null) {
    for (final p in products) {
      if (p.id == item.productId) return p.name;
    }
  }
  if (item.customMedicationId != null) {
    for (final m in medications) {
      if (m.id == item.customMedicationId) return m.name;
    }
  }
  return 'สินค้า #${item.productId ?? item.customMedicationId ?? item.id.substring(0, 8)}';
}

// ========================
// 1. สต็อก Tab
// ========================

class _StockTab extends StatelessWidget {
  final List<InventoryItem> items;
  final List<Product> products;
  final List<CustomMedication> medications;
  final Future<void> Function() onRefresh;

  const _StockTab({
    required this.items,
    required this.products,
    required this.medications,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return RefreshIndicator(
        onRefresh: onRefresh,
        child: ListView(children: const [Center(child: Padding(padding: EdgeInsets.all(32), child: Text('ไม่มีข้อมูลสต็อก')))]),
      );
    }
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        final name = _resolveItemName(item, products, medications);
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: GlassCard(
            section: GlassSection.card,
            borderRadius: 16,
            padding: const EdgeInsets.all(14),
            child: ListTile(
              title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('คงเหลือ: ${item.quantity} | ต้นทุน: ฿${item.costPrice.toStringAsFixed(2)} | ขาย: ฿${item.sellingPrice.toStringAsFixed(2)}'),
                  if (item.reorderPoint > 0)
                    Text('จุดสั่งซื้อ: ${item.reorderPoint} | สั่ง: ${item.reorderQty}'),
                ],
              ),
              trailing: _StockStatusChip(item: item),
            ),
          ),
        );
      },
    ),
  );
}
}

class _StockStatusChip extends StatelessWidget {
  final InventoryItem item;

  const _StockStatusChip({required this.item});

  @override
  Widget build(BuildContext context) {
    Color color = Colors.green;
    String label = 'ปกติ';
    if (item.isOutOfStock) {
      color = Colors.red;
      label = 'หมด';
    } else if (item.isLowStock) {
      color = Colors.orange;
      label = 'ต่ำ';
    }
    return Chip(
      label: Text(label, style: const TextStyle(fontSize: 11)),
      backgroundColor: color.withValues(alpha: 0.15),
      side: BorderSide(color: color.withValues(alpha: 0.5)),
    );
  }
}

// ========================
// 2. แจ้งเตือน Tab
// ========================

class _AlertsTab extends StatelessWidget {
  final List<InventoryAlert> alerts;
  final Future<void> Function() onRefresh;

  const _AlertsTab({required this.alerts, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    if (alerts.isEmpty) {
      return RefreshIndicator(
        onRefresh: onRefresh,
        child: ListView(children: const [Center(child: Padding(padding: EdgeInsets.all(32), child: Text('ไม่มีแจ้งเตือน')))]),
      );
    }
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: alerts.length,
      itemBuilder: (context, index) {
        final alert = alerts[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: GlassCard(
            section: GlassSection.card,
            borderRadius: 16,
            padding: const EdgeInsets.all(14),
            child: ListTile(
              title: Text(alert.typeLabel, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(alert.message),
              trailing: _SeverityChip(severity: alert.severity, label: alert.severityLabel),
            ),
          ),
        );
      },
    ),
  );
}
}

class _SeverityChip extends StatelessWidget {
  final String severity;
  final String label;

  const _SeverityChip({required this.severity, required this.label});

  @override
  Widget build(BuildContext context) {
    Color color = Colors.grey;
    switch (severity) {
      case 'low':
        color = Colors.blue;
      case 'medium':
        color = Colors.orange;
      case 'high':
        color = Colors.red;
      case 'critical':
        color = Colors.purple;
    }
    return Chip(
      label: Text(label, style: const TextStyle(fontSize: 11)),
      backgroundColor: color.withValues(alpha: 0.15),
      side: BorderSide(color: color.withValues(alpha: 0.5)),
    );
  }
}

// ========================
// 3. ตรวจนับ Tab
// ========================

class _StocktakeTab extends StatelessWidget {
  final List<StocktakeSession> sessions;
  final Future<void> Function() onRefresh;
  final Future<void> Function(String) onComplete;

  const _StocktakeTab({
    required this.sessions,
    required this.onRefresh,
    required this.onComplete,
  });

  @override
  Widget build(BuildContext context) {
    if (sessions.isEmpty) {
      return RefreshIndicator(
        onRefresh: onRefresh,
        child: ListView(children: const [Center(child: Padding(padding: EdgeInsets.all(32), child: Text('ไม่มีรอบตรวจนับ')))]),
      );
    }
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: sessions.length,
      itemBuilder: (context, index) {
        final s = sessions[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: GlassCard(
            section: GlassSection.card,
            borderRadius: 16,
            padding: const EdgeInsets.all(14),
            child: ListTile(
              title: Text('รอบตรวจนับ #${s.id.substring(0, 8)}', style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('สถานะ: ${s.isInProgress ? 'กำลังดำเนินการ' : (s.isCompleted ? 'เสร็จสิ้น' : s.status)}'),
                  Text('เริ่ม: ${s.startedAt.toLocal().toString().split(' ')[0]}'),
                  if (s.notes != null) Text('หมายเหตุ: ${s.notes}'),
                ],
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Chip(
                    label: Text(s.isInProgress ? 'ดำเนินการ' : 'เสร็จ', style: const TextStyle(fontSize: 11)),
                    backgroundColor: (s.isInProgress ? Colors.orange : Colors.green).withValues(alpha: 0.15),
                    side: BorderSide(color: (s.isInProgress ? Colors.orange : Colors.green).withValues(alpha: 0.5)),
                  ),
                  if (s.isInProgress)
                    IconButton(
                      icon: const Icon(Icons.check_circle_outline),
                      tooltip: 'ปิดรอบตรวจนับ',
                      onPressed: () => onComplete(s.id),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
}
}

// ========================
// 4. โอนย้าย Tab
// ========================

class _TransfersTab extends StatelessWidget {
  final List<InventoryTransfer> transfers;
  final Future<void> Function() onRefresh;
  final Future<void> Function(String) onComplete;

  const _TransfersTab({
    required this.transfers,
    required this.onRefresh,
    required this.onComplete,
  });

  @override
  Widget build(BuildContext context) {
    if (transfers.isEmpty) {
      return RefreshIndicator(
        onRefresh: onRefresh,
        child: ListView(children: const [Center(child: Padding(padding: EdgeInsets.all(32), child: Text('ไม่มีรายการโอนย้าย')))]),
      );
    }
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: transfers.length,
      itemBuilder: (context, index) {
        final t = transfers[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: GlassCard(
            section: GlassSection.card,
            borderRadius: 16,
            padding: const EdgeInsets.all(14),
            child: ListTile(
              title: Text('โอนย้าย #${t.id.substring(0, 8)}', style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('จาก: ${t.fromBranchId ?? 'คลังหลัก'} → ถึง: ${t.toBranchId ?? 'คลังปลายทาง'}'),
                  if (t.notes != null) Text('หมายเหตุ: ${t.notes}'),
                ],
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Chip(
                    label: Text(t.statusLabel, style: const TextStyle(fontSize: 11)),
                    backgroundColor: _transferColor(t.transferStatus).withValues(alpha: 0.15),
                    side: BorderSide(color: _transferColor(t.transferStatus).withValues(alpha: 0.5)),
                  ),
                  if (t.isPending)
                    IconButton(
                      icon: const Icon(Icons.check_circle_outline),
                      tooltip: 'ยืนยันโอนย้าย',
                      onPressed: () => onComplete(t.id),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
}

  Color _transferColor(String status) {
    switch (status) {
      case 'pending': return Colors.orange;
      case 'in_transit': return Colors.blue;
      case 'completed': return Colors.green;
      case 'rejected': return Colors.red;
      case 'cancelled': return Colors.grey;
      default: return Colors.grey;
    }
  }
}

// ========================
// 5. ปรับสต็อก Tab
// ========================

class _AdjustmentsTab extends StatelessWidget {
  final List<StockAdjustment> adjustments;
  final Future<void> Function() onRefresh;

  const _AdjustmentsTab({required this.adjustments, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    if (adjustments.isEmpty) {
      return RefreshIndicator(
        onRefresh: onRefresh,
        child: ListView(children: const [Center(child: Padding(padding: EdgeInsets.all(32), child: Text('ไม่มีรายการปรับสต็อก')))]),
      );
    }
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: adjustments.length,
      itemBuilder: (context, index) {
        final adj = adjustments[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: GlassCard(
            section: GlassSection.card,
            borderRadius: 16,
            padding: const EdgeInsets.all(14),
            child: ListTile(
              title: Text('${adj.typeLabel} #${adj.id.substring(0, 8)}', style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('ก่อน: ${adj.quantityBefore} → หลัง: ${adj.quantityAfter} (ส่วนต่าง ${adj.variance >= 0 ? '+' : ''}${adj.variance})'),
                  if (adj.reason != null) Text('เหตุผล: ${adj.reason}'),
                ],
              ),
              trailing: Chip(
                label: Text(adj.typeLabel, style: const TextStyle(fontSize: 11)),
                backgroundColor: _adjustmentColor(adj.adjustmentType).withValues(alpha: 0.15),
                side: BorderSide(color: _adjustmentColor(adj.adjustmentType).withValues(alpha: 0.5)),
              ),
            ),
          ),
        );
      },
    ),
  );
}

  Color _adjustmentColor(String type) {
    switch (type) {
      case 'count': return Colors.blue;
      case 'damage': return Colors.red;
      case 'expired': return Colors.orange;
      case 'found': return Colors.green;
      case 'lost': return Colors.brown;
      default: return Colors.grey;
    }
  }
}

// ========================
// 6. รับเข้า Tab (legacy)
// ========================

class _ReceiptTab extends ConsumerStatefulWidget {
  final String professionId;
  final List<dynamic> products;
  final Future<void> Function() onRefresh;

  const _ReceiptTab({
    required this.professionId,
    required this.products,
    required this.onRefresh,
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
            initialValue: _selectedProductId,
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
