import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/dashboard_theme.dart';
import '../providers/phase_three_provider.dart';
import '../widgets/glass_card.dart';

class DashboardAnalyticsPage extends ConsumerStatefulWidget {
  final String professionId;

  const DashboardAnalyticsPage({
    Key? key,
    required this.professionId,
  }) : super(key: key);

  @override
  ConsumerState<DashboardAnalyticsPage> createState() => _DashboardAnalyticsPageState();
}

class _DashboardAnalyticsPageState extends ConsumerState<DashboardAnalyticsPage> {
  String _selectedType = 'daily';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  void _loadData() {
    Future.microtask(() {
      ref.read(phaseThreeProvider.notifier).loadSnapshots(
        widget.professionId,
        type: _selectedType,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(phaseThreeProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('วิเคราะห์ข้อมูล / Analytics'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: state.isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildPeriodSelector(),
                const SizedBox(height: 20),
                _buildKpiCards(state),
                const SizedBox(height: 20),
                _buildSnapshotsList(state),
              ],
            ),
    );
  }

  Widget _buildPeriodSelector() {
    final types = [
      _PeriodOption('daily', 'รายวัน'),
      _PeriodOption('weekly', 'รายสัปดาห์'),
      _PeriodOption('monthly', 'รายเดือน'),
    ];

    return GlassCard(
      section: GlassSection.card,
      borderRadius: 12,
      padding: const EdgeInsets.all(12),
      child: Row(
        children: types.map((t) {
          final isSelected = _selectedType == t.value;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: ElevatedButton(
                onPressed: () {
                  setState(() => _selectedType = t.value);
                  _loadData();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: isSelected ? null : Colors.grey.withOpacity(0.3),
                ),
                child: Text(t.label),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildKpiCards(PhaseThreeState state) {
    // Calculate from latest snapshot or show defaults
    final latest = state.snapshots.isNotEmpty ? state.snapshots.first : null;
    final revenue = latest?.getMetric('revenue') ?? 0;
    final orders = latest?.getMetric('orders') ?? 0;
    final customers = latest?.getMetric('customers') ?? 0;

    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 3,
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      childAspectRatio: 1.1,
      children: [
        _KpiCard(title: 'รายได้', value: '฿${revenue.toStringAsFixed(0)}', icon: Icons.paid, color: Colors.green),
        _KpiCard(title: 'ออเดอร์', value: orders.toStringAsFixed(0), icon: Icons.shopping_bag, color: Colors.blue),
        _KpiCard(title: 'ลูกค้า', value: customers.toStringAsFixed(0), icon: Icons.people, color: Colors.orange),
      ],
    );
  }

  Widget _buildSnapshotsList(PhaseThreeState state) {
    if (state.snapshots.isEmpty) {
      return const Center(
        child: Text(
          'ยังไม่มีข้อมูล snapshot',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    return GlassCard(
      section: GlassSection.card,
      borderRadius: 16,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'ประวัติ Snapshot',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          ...state.snapshots.take(5).map((s) => _SnapshotRow(snapshot: s)),
        ],
      ),
    );
  }
}

class _PeriodOption {
  final String value;
  final String label;
  _PeriodOption(this.value, this.label);
}

class _KpiCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const _KpiCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      section: GlassSection.card,
      borderRadius: 16,
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(title, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        ],
      ),
    );
  }
}

class _SnapshotRow extends StatelessWidget {
  final dynamic snapshot;

  const _SnapshotRow({required this.snapshot});

  @override
  Widget build(BuildContext context) {
    final revenue = snapshot.getMetric('revenue') ?? 0;
    final orders = snapshot.getMetric('orders') ?? 0;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${snapshot.snapshotDate.toString().substring(0, 10)}',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          Text('฿${revenue.toStringAsFixed(0)}'),
          const SizedBox(width: 16),
          Text('${orders.toStringAsFixed(0)} ออเดอร์'),
        ],
      ),
    );
  }
}
