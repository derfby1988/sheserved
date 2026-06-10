import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../providers/kpi_provider.dart';
import '../widgets/kpi_gauge.dart';
import '../widgets/kpi_bar_chart.dart';
import '../widgets/kpi_trend_line.dart';
import '../widgets/kpi_alert_card.dart';
import '../widgets/kpi_alert_banner.dart';
import '../widgets/kpi_period_selector.dart';
import 'kpi_refresh_history_page.dart';

class KpiDashboardPage extends ConsumerStatefulWidget {
  const KpiDashboardPage({super.key});

  @override
  ConsumerState<KpiDashboardPage> createState() => _KpiDashboardPageState();
}

class _KpiDashboardPageState extends ConsumerState<KpiDashboardPage> {
  RealtimeChannel? _channel;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadData();
      _subscribeRealtime();
    });
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    super.dispose();
  }

  /// Subscribe to kpi_actuals changes via Supabase Realtime (free, no-cost)
  void _subscribeRealtime() {
    final professionId = ref.read(kpiProvider).selectedProfessionId;
    if (professionId == null || professionId.isEmpty) return;

    _channel = Supabase.instance.client
        .channel('kpi_actuals_changes')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'kpi_actuals',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'profession_id',
            value: professionId,
          ),
          callback: (payload) {
            debugPrint('[KPI Realtime] Change detected: ${payload.eventType}');
            // Auto-reload dashboard when actuals change
            if (mounted) {
              _loadData();
            }
          },
        )
        .subscribe();
  }

  Future<void> _loadData() async {
    final notifier = ref.read(kpiProvider.notifier);
    // TODO: ดึง profession_id จาก user context หรือ provider
    // สำหรับตอนนี้ให้ผู้ใช้ตั้งค่าผ่าน filter หรือ mock ไว้ก่อน
    await notifier.loadDashboardData();
  }

  Future<void> _onRefresh() async {
    await ref.read(kpiProvider.notifier).refreshActuals();

    if (mounted) {
      final state = ref.read(kpiProvider);
      if (state.errorMessage == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('รีเฟรชข้อมูลสำเร็จ'),
            backgroundColor: Color(0xFF4CAF50),
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(kpiProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('KPI Dashboard'),
        elevation: 0,
        actions: [
          if (state.isRefreshing)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _onRefresh,
              tooltip: 'รีเฟรชข้อมูล',
            ),
          IconButton(
            icon: const Icon(Icons.history),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const KpiRefreshHistoryPage(),
                ),
              );
            },
            tooltip: 'ประวัติการรีเฟรช',
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.pushNamed(context, '/kpi/target/form');
            },
            tooltip: 'จัดการเป้าหมาย',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _onRefresh,
        child: state.isLoading && state.kpiActuals.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Error Banner
                    if (state.errorMessage != null)
                      Container(
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: Colors.red[50],
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.red[200]!),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.error_outline, color: Colors.red[600]),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                state.errorMessage!,
                                style: TextStyle(color: Colors.red[700]),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close, size: 18),
                              onPressed: () {
                                ref.read(kpiProvider.notifier);
                                // Clear error by loading again
                              },
                            ),
                          ],
                        ),
                      ),

                    // Alert Banner (In-app notification, no-cost)
                    KpiAlertBanner(
                      actuals: state.kpiActuals,
                      thresholds: state.alertThresholds,
                      onViewDetails: () {
                        // Scroll to detail section or navigate
                      },
                    ),

                    // Refresh Result Banner
                    if (state.lastRefreshResult != null &&
                        !state.isRefreshing)
                      Container(
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: Colors.green[50],
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.green[200]!),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.check_circle,
                                color: Colors.green[600]),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'รีเฟรชสำเร็จ: แทรก ${state.lastRefreshResult!['inserted']} รายการ, อัปเดต ${state.lastRefreshResult!['updated']} รายการ',
                                style: TextStyle(color: Colors.green[700]),
                              ),
                            ),
                          ],
                        ),
                      ),

                    // Period & Target Selector
                    KpiPeriodSelector(
                      selectedPeriod: state.selectedPeriodType,
                      onPeriodChanged: (period) {
                        ref
                            .read(kpiProvider.notifier)
                            .setFilters(periodType: period);
                        _loadData();
                      },
                      selectedTargetType: state.selectedTargetType,
                      onTargetTypeChanged: (type) {
                        ref
                            .read(kpiProvider.notifier)
                            .setFilters(targetType: type);
                        _loadData();
                      },
                    ),
                    const SizedBox(height: 16),

                    // Main Gauge
                    if (state.dashboardSummary != null)
                      KpiGauge(
                        achievementRate: state.dashboardSummary!.overallAchievementRate,
                        actualAmount: state.dashboardSummary!.totalActual,
                        targetAmount: state.dashboardSummary!.totalTarget,
                        title: _getTargetTypeLabel(state.selectedTargetType),
                        subtitle:
                            '${_formatPeriodLabel(state.selectedPeriodType)} — ${state.dashboardSummary!.recordCount} records',
                      ),
                    const SizedBox(height: 16),

                    // Alert Card
                    if (state.dashboardSummary != null)
                      KpiAlertCard(
                        title: _getTargetTypeLabel(state.selectedTargetType),
                        subtitle:
                            '${_formatPeriodLabel(state.selectedPeriodType)} ${DateTime.now().year}',
                        achievementRate:
                            state.dashboardSummary!.overallAchievementRate,
                        warningThreshold: state.alertThresholds.isNotEmpty
                            ? state.alertThresholds
                                .firstWhere(
                                  (t) => t.targetType == state.selectedTargetType,
                                  orElse: () => state.alertThresholds.first,
                                )
                                .warningThresholdPct
                            : 80,
                        criticalThreshold: state.alertThresholds.isNotEmpty
                            ? state.alertThresholds
                                .firstWhere(
                                  (t) => t.targetType == state.selectedTargetType,
                                  orElse: () => state.alertThresholds.first,
                                )
                                .criticalThresholdPct
                            : 60,
                      ),
                    const SizedBox(height: 16),

                    // Trend Line
                    KpiTrendLine(
                      data: state.kpiActuals,
                      title:
                          'Achievement Rate Trend — ${_getTargetTypeLabel(state.selectedTargetType)}',
                    ),
                    const SizedBox(height: 16),

                    // Bar Chart
                    KpiBarChart(
                      data: state.kpiActuals,
                      targetType: _getTargetTypeLabel(state.selectedTargetType),
                    ),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
      ),
    );
  }

  String _getTargetTypeLabel(String type) {
    switch (type) {
      case 'revenue':
        return 'ยอดขาย';
      case 'net_profit':
        return 'กำไรสุทธิ';
      case 'consultations':
        return 'การปรึกษา';
      case 'appointments':
        return 'นัดหมาย';
      default:
        return type;
    }
  }

  String _formatPeriodLabel(String period) {
    switch (period) {
      case 'daily':
        return 'รายวัน';
      case 'weekly':
        return 'รายสัปดาห์';
      case 'monthly':
        return 'รายเดือน';
      case 'quarterly':
        return 'รายไตรมาส';
      case 'yearly':
        return 'รายปี';
      default:
        return period;
    }
  }
}
