import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/dashboard_theme.dart';
import '../providers/phase_one_provider.dart';
import '../widgets/glass_card.dart';

class InventoryDashboardPage extends ConsumerStatefulWidget {
  final String professionId;

  const InventoryDashboardPage({
    super.key,
    required this.professionId,
  });

  @override
  ConsumerState<InventoryDashboardPage> createState() => _InventoryDashboardPageState();
}

class _InventoryDashboardPageState extends ConsumerState<InventoryDashboardPage> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      final notifier = ref.read(phaseOneProvider.notifier);
      notifier.loadInventoryItems(widget.professionId);
      notifier.loadInventoryAlerts(widget.professionId);
      notifier.loadInventoryTransfers(widget.professionId);
      notifier.loadStocktakeSessions(widget.professionId);
    });
  }

  Future<void> _refresh() async {
    final notifier = ref.read(phaseOneProvider.notifier);
    notifier.loadInventoryItems(widget.professionId);
    notifier.loadInventoryAlerts(widget.professionId);
    notifier.loadInventoryTransfers(widget.professionId);
    notifier.loadStocktakeSessions(widget.professionId);
    await Future.delayed(const Duration(milliseconds: 600));
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(phaseOneProvider);

    final totalItems = state.inventoryItems.length;
    final lowStockCount = state.inventoryItems.where((i) => i.isLowStock).length;
    final outOfStockCount = state.inventoryItems.where((i) => i.isOutOfStock).length;
    final activeAlerts = state.inventoryAlerts.where((a) => !a.isResolved).length;
    final pendingTransfers = state.inventoryTransfers.where((t) => t.isPending).length;
    final inProgressStocktakes = state.stocktakeSessions.where((s) => s.isInProgress).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('ภาพรวมคลังสินค้า'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _SummaryGrid(
              totalItems: totalItems,
              lowStock: lowStockCount,
              outOfStock: outOfStockCount,
              alerts: activeAlerts,
              transfers: pendingTransfers,
              stocktakes: inProgressStocktakes,
            ),
            const SizedBox(height: 20),
            _QuickActions(
              onInventory: () => Navigator.of(context).pushNamed('/erp/inventory', arguments: {'professionId': widget.professionId}),
              onTransfer: () => Navigator.of(context).pushNamed('/erp/inventory/transfer', arguments: {'professionId': widget.professionId}),
              onAdjustment: () => Navigator.of(context).pushNamed('/erp/inventory/adjustment', arguments: {'professionId': widget.professionId}),
            ),
            const SizedBox(height: 20),
            if (state.inventoryAlerts.isNotEmpty) ...[
              const Text('แจ้งเตือนล่าสุด', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              ...state.inventoryAlerts.take(5).map((alert) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: GlassCard(
                  section: GlassSection.card,
                  borderRadius: 12,
                  padding: const EdgeInsets.all(12),
                  child: ListTile(
                    dense: true,
                    title: Text(alert.typeLabel, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(alert.message),
                    trailing: _AlertSeverityChip(severity: alert.severity),
                  ),
                ),
              )),
            ],
          ],
        ),
      ),
    );
  }
}

class _SummaryGrid extends StatelessWidget {
  final int totalItems;
  final int lowStock;
  final int outOfStock;
  final int alerts;
  final int transfers;
  final int stocktakes;

  const _SummaryGrid({
    required this.totalItems,
    required this.lowStock,
    required this.outOfStock,
    required this.alerts,
    required this.transfers,
    required this.stocktakes,
  });

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.4,
      children: [
        _SummaryCard(
          label: 'สินค้าทั้งหมด',
          value: '$totalItems',
          icon: Icons.inventory_2,
          color: Colors.blue,
        ),
        _SummaryCard(
          label: 'ใกล้หมด',
          value: '$lowStock',
          icon: Icons.warning,
          color: Colors.orange,
        ),
        _SummaryCard(
          label: 'หมดสต็อก',
          value: '$outOfStock',
          icon: Icons.error,
          color: Colors.red,
        ),
        _SummaryCard(
          label: 'แจ้งเตือน',
          value: '$alerts',
          icon: Icons.notifications,
          color: Colors.purple,
        ),
        _SummaryCard(
          label: 'โอนย้ายรอดำเนินการ',
          value: '$transfers',
          icon: Icons.swap_horiz,
          color: Colors.teal,
        ),
        _SummaryCard(
          label: 'ตรวจนับดำเนินการ',
          value: '$stocktakes',
          icon: Icons.fact_check,
          color: Colors.indigo,
        ),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _SummaryCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      section: GlassSection.card,
      borderRadius: 16,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 8),
          Text(value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: color)),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  final VoidCallback onInventory;
  final VoidCallback onTransfer;
  final VoidCallback onAdjustment;

  const _QuickActions({
    required this.onInventory,
    required this.onTransfer,
    required this.onAdjustment,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('ทำรายการ', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: onInventory,
                icon: const Icon(Icons.inventory_2),
                label: const Text('คลังสินค้า'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: onTransfer,
                icon: const Icon(Icons.swap_horiz),
                label: const Text('โอนย้าย'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: onAdjustment,
                icon: const Icon(Icons.tune),
                label: const Text('ปรับสต็อก'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _AlertSeverityChip extends StatelessWidget {
  final String severity;

  const _AlertSeverityChip({required this.severity});

  @override
  Widget build(BuildContext context) {
    Color color = Colors.grey;
    switch (severity) {
      case 'low': color = Colors.blue;
      case 'medium': color = Colors.orange;
      case 'high': color = Colors.red;
      case 'critical': color = Colors.purple;
    }
    return Chip(
      label: Text(
        severity == 'low' ? 'ต่ำ' : severity == 'medium' ? 'ปานกลาง' : severity == 'high' ? 'สูง' : 'วิกฤต',
        style: const TextStyle(fontSize: 11),
      ),
      backgroundColor: color.withValues(alpha: 0.15),
      side: BorderSide(color: color.withValues(alpha: 0.5)),
    );
  }
}
