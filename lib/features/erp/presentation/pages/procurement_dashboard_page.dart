import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../widgets/glass_card.dart';

class ProcurementDashboardPage extends ConsumerStatefulWidget {
  final String professionId;
  final String? branchId;

  const ProcurementDashboardPage({
    super.key,
    required this.professionId,
    this.branchId,
  });

  @override
  ConsumerState<ProcurementDashboardPage> createState() =>
      _ProcurementDashboardPageState();
}

class _ProcurementDashboardPageState
    extends ConsumerState<ProcurementDashboardPage> {
  Map<String, dynamic>? _metrics;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadMetrics());
  }

  Future<void> _loadMetrics() async {
    setState(() => _isLoading = true);
    try {
      final response = await _fetchMetrics();
      if (mounted) setState(() => _metrics = response);
    } catch (e) {
      debugPrint('Dashboard metrics error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<Map<String, dynamic>> _fetchMetrics() async {
    final client = Supabase.instance.client;
    final response = await client.rpc(
      'get_procurement_dashboard_metrics',
      params: {
        'p_profession_id': widget.professionId,
        'p_branch_id': widget.branchId,
      },
    );
    return response as Map<String, dynamic>;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('แดชบอร์ดจัดซื้อ / Procurement Dashboard'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _loadMetrics,
          ),
        ],
      ),
      body: _isLoading && _metrics == null
          ? const Center(child: CircularProgressIndicator())
          : _metrics == null
              ? _buildErrorState()
              : RefreshIndicator(
                  onRefresh: _loadMetrics,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildKpiCards(),
                        const SizedBox(height: 24),
                        _buildMonthlyChart(),
                        const SizedBox(height: 24),
                        _buildTopProducts(),
                      ],
                    ),
                  ),
                ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            'ไม่สามารถโหลดข้อมูลได้',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Colors.grey[600],
                ),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _loadMetrics,
            child: const Text('ลองใหม่'),
          ),
        ],
      ),
    );
  }

  Widget _buildKpiCards() {
    final poTotal = (_metrics!['po_total_amount'] as num?)?.toDouble() ?? 0;
    final poCount = _metrics!['po_count'] as int? ?? 0;
    final prPending = _metrics!['pr_pending_approval'] as int? ?? 0;
    final grCount = _metrics!['gr_count'] as int? ?? 0;
    final boOpen = _metrics!['back_order_open'] as int? ?? 0;
    final invMatched = _metrics!['invoice_matched'] as int? ?? 0;
    final invMismatch = _metrics!['invoice_mismatch'] as int? ?? 0;
    final invPending = _metrics!['invoice_pending'] as int? ?? 0;
    final reorderPending = _metrics!['reorder_pending'] as int? ?? 0;

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _kpiCard('ยอดสั่งซื้อรวม', '฿${poTotal.toStringAsFixed(2)}', Icons.shopping_cart, Colors.blue),
        _kpiCard('จำนวน PO', '$poCount ใบ', Icons.receipt_long, Colors.indigo),
        _kpiCard('PR รออนุมัติ', '$prPending ใบ', Icons.pending_actions, Colors.orange),
        _kpiCard('รับของ (GR)', '$grCount ครั้ง', Icons.inventory, Colors.green),
        _kpiCard('Back Order', '$boOpen รายการ', Icons.warning, Colors.red),
        _kpiCard('Invoice ตรง', '$invMatched ใบ', Icons.verified, Colors.teal),
        _kpiCard('Invoice ไม่ตรง', '$invMismatch ใบ', Icons.error, Colors.redAccent),
        _kpiCard('Invoice รอตรวจ', '$invPending ใบ', Icons.hourglass_empty, Colors.amber),
        _kpiCard('Reorder รอยืนยัน', '$reorderPending รายการ', Icons.radar, Colors.purple),
      ],
    );
  }

  Widget _kpiCard(String label, String value, IconData icon, Color color) {
    return SizedBox(
      width: (MediaQuery.of(context).size.width - 48) / 2,
      child: GlassCard(
        section: GlassSection.card,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, color: color, size: 24),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                value,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMonthlyChart() {
    final monthly = _metrics!['monthly_po_totals'] as List? ?? [];
    if (monthly.isEmpty) {
      return GlassCard(
        section: GlassSection.card,
        child: const Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: Text('ไม่มีข้อมูลยอดสั่งซื้อรายเดือน')),
        ),
      );
    }

    final spots = <BarChartGroupData>[];
    for (var i = 0; i < monthly.length; i++) {
      final item = monthly[i] as Map<String, dynamic>;
      final total = (item['total'] as num?)?.toDouble() ?? 0;
      spots.add(
        BarChartGroupData(
          x: i,
          barRods: [
            BarChartRodData(
              toY: total,
              color: Theme.of(context).colorScheme.primary,
              width: 32,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
            ),
          ],
        ),
      );
    }

    return GlassCard(
      section: GlassSection.card,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'ยอดสั่งซื้อรายเดือน (6 เดือนล่าสุด)',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 200,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  barGroups: spots,
                  titlesData: FlTitlesData(
                    leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          final idx = value.toInt();
                          if (idx < 0 || idx >= monthly.length) return const SizedBox();
                          final item = monthly[idx] as Map<String, dynamic>;
                          final month = item['month'] as String? ?? '';
                          return Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              month.substring(5),
                              style: const TextStyle(fontSize: 10),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  gridData: const FlGridData(show: false),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopProducts() {
    final products = _metrics!['top_products'] as List? ?? [];
    if (products.isEmpty) {
      return GlassCard(
        section: GlassSection.card,
        child: const Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: Text('ไม่มีข้อมูลสินค้าที่สั่งซื้อบ่อย')),
        ),
      );
    }

    return GlassCard(
      section: GlassSection.card,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Top 10 สินค้าที่สั่งซื้อบ่อย',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            ...products.map((item) {
              final p = item as Map<String, dynamic>;
              final name = p['product_name'] as String? ?? 'ไม่ทราบ';
              final qty = p['total_qty'] as int? ?? 0;
              final amount = (p['total_amount'] as num?)?.toDouble() ?? 0;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: Text(name, style: const TextStyle(fontSize: 13)),
                    ),
                    Text(
                      '$qty หน่วย',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '฿${amount.toStringAsFixed(0)}',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}
