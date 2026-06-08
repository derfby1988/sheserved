import 'package:flutter/material.dart';

import '../../../../config/app_config.dart';
import '../../../../config/sync_config.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../../services/platform_service.dart';
import '../../../../shared/widgets/tlz_app_top_bar.dart';
import '../../../../shared/widgets/tlz_drawer.dart';
import '../../../../shared/widgets/tlz_hamburger_menu.dart';
import '../../data/services/system_monitor_service.dart';

class SystemMonitorPage extends StatefulWidget {
  const SystemMonitorPage({super.key});

  @override
  State<SystemMonitorPage> createState() => _SystemMonitorPageState();
}

class _SystemMonitorPageState extends State<SystemMonitorPage> {
  final SystemMonitorService _service = SystemMonitorService();

  Map<String, dynamic> _systemHealth = {};
  Map<String, dynamic> _queueHealth = {};
  List<Map<String, dynamic>> _platformMetrics = [];
  Map<String, dynamic> _summary = {};
  bool _isLoading = true;
  String? _errorMessage;
  DateTime? _lastUpdated;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final results = await Future.wait([
        _service.fetchSystemHealth(),
        _service.fetchQueueHealth(),
        _service.fetchPlatformMetrics(),
      ]);

      final systemHealth = Map<String, dynamic>.from(results[0] as Map);
      final queueHealth = Map<String, dynamic>.from(results[1] as Map);
      final platformMetrics = List<Map<String, dynamic>>.from(results[2] as List);

      final summary = _service.buildCostGuardrailSummary(
        systemHealth: systemHealth,
        queueHealth: queueHealth,
        metrics: platformMetrics,
      );

      if (!mounted) return;
      setState(() {
        _systemHealth = systemHealth;
        _queueHealth = queueHealth;
        _platformMetrics = platformMetrics;
        _summary = summary;
        _lastUpdated = DateTime.now();
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  bool get _overallHealthy =>
      _summary['systemHealthy'] == true && _summary['queueHealthy'] == true;

  List<Map<String, dynamic>> get _queues {
    final raw = _queueHealth['queues'];
    if (raw is List) {
      return raw.map((item) => Map<String, dynamic>.from(item as Map)).toList();
    }
    return [];
  }

  int _toInt(dynamic value) => int.tryParse(value?.toString() ?? '0') ?? 0;

  double _toDouble(dynamic value) => double.tryParse(value?.toString() ?? '0') ?? 0.0;

  String _formatDateTime(DateTime? value) {
    if (value == null) return '-';
    final local = value.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} '
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}:${local.second.toString().padLeft(2, '0')}';
  }

  Color _statusColor(bool healthy) => healthy ? AppColors.success : AppColors.error;

  String _statusLabel(bool healthy) => healthy ? 'Healthy' : 'At Risk';

  Map<String, dynamic> _getThresholds() {
    final thresholds = _queueHealth['thresholds'];
    if (thresholds is Map) {
      return Map<String, dynamic>.from(thresholds);
    }
    return {};
  }

  @override
  Widget build(BuildContext context) {
    final thresholds = _getThresholds();
    final queueThresholdWaiting = _toInt(thresholds['maxWaiting']);
    final queueThresholdFailed = _toInt(thresholds['maxFailed']);

    return Scaffold(
      backgroundColor: AppColors.background,
      drawer: const TlzDrawer(),
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight + 16),
        child: Container(
          color: AppColors.primary,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: TlzAppTopBar.onPrimary(
                leading: const TlzHamburgerMenu(),
                searchHintText: 'ค้นหาสถานะระบบ, queue, cost guardrail...',
                actions: [
                  IconButton(
                    onPressed: _isLoading ? null : _loadData,
                    icon: const Icon(Icons.refresh, color: Colors.white),
                    tooltip: 'รีเฟรชข้อมูล',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _loadData,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
          padding: const EdgeInsets.all(16),
          children: [
            _buildHeroCard(),
            const SizedBox(height: 16),
            _buildAlertSummary(),
            const SizedBox(height: 16),
            _buildQuickStats(),
            const SizedBox(height: 16),
            _buildSystemHealthCard(),
            const SizedBox(height: 16),
            _buildQueueOverviewCard(queueThresholdWaiting, queueThresholdFailed),
            const SizedBox(height: 16),
            _buildQueueList(),
            const SizedBox(height: 16),
            _buildUsageAndCostCard(),
            const SizedBox(height: 16),
            _buildCostPreventionControls(),
            const SizedBox(height: 16),
            _buildRecommendationsCard(),
            if (_errorMessage != null) ...[
              const SizedBox(height: 16),
              _buildErrorCard(),
            ],
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildHeroCard() {
    final healthy = _overallHealthy;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: healthy
              ? [AppColors.primaryDark, AppColors.primary]
              : [AppColors.error, AppColors.warning],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.12),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  healthy ? Icons.shield_outlined : Icons.warning_amber_rounded,
                  color: Colors.white,
                  size: 28,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'System Monitor',
                      style: AppTextStyles.heading3.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'เฝ้าดู health, queue backlog และสัญญาณค่าใช้จ่ายแบบ real-time',
                      style: AppTextStyles.bodySmall.copyWith(color: Colors.white.withOpacity(0.9)),
                    ),
                  ],
                ),
              ),
              _buildStatusChip(healthy),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _buildHeroMetric(
                  icon: Icons.people_alt_outlined,
                  label: 'Connected Users',
                  value: '${_toInt(_systemHealth['connectedUsers'])}',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildHeroMetric(
                  icon: Icons.access_time,
                  label: 'Last Updated',
                  value: _formatDateTime(_lastUpdated),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _heroCounterChip(
                label: 'Critical',
                value: _toInt(_summary['criticalAlertCount']),
                color: AppColors.error,
              ),
              const SizedBox(width: 10),
              _heroCounterChip(
                label: 'Warning',
                value: _toInt(_summary['warningAlertCount']),
                color: AppColors.warning,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _heroCounterChip({required String label, required int value, required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withOpacity(0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text(
            '$label: $value',
            style: AppTextStyles.labelSmall.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAlertSummary() {
    final alerts = List<Map<String, dynamic>>.from(_summary['alerts'] ?? const []);
    if (alerts.isEmpty) {
      return _statusBanner(true, 'ยังไม่พบ alert เกิน threshold ในตอนนี้');
    }

    final criticalAlerts = alerts.where((alert) => alert['severity'] == 'critical').toList();
    final warningAlerts = alerts.where((alert) => alert['severity'] == 'warning').toList();

    return Column(
      children: [
        if (criticalAlerts.isNotEmpty)
          _alertCard(
            title: 'Critical Alerts',
            subtitle: 'ต้องจัดการทันที',
            color: AppColors.error,
            icon: Icons.dangerous_outlined,
            alerts: criticalAlerts,
          ),
        if (criticalAlerts.isNotEmpty && warningAlerts.isNotEmpty) const SizedBox(height: 12),
        if (warningAlerts.isNotEmpty)
          _alertCard(
            title: 'Warning Alerts',
            subtitle: 'ควรแก้ก่อนโตเป็น critical',
            color: AppColors.warning,
            icon: Icons.warning_amber_rounded,
            alerts: warningAlerts,
          ),
      ],
    );
  }

  Widget _alertCard({
    required String title,
    required String subtitle,
    required Color color,
    required IconData icon,
    required List<Map<String, dynamic>> alerts,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.09),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppTextStyles.heading5.copyWith(
                        fontWeight: FontWeight.w700,
                        color: color,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.16),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${alerts.length}',
                  style: AppTextStyles.labelLarge.copyWith(
                    color: color,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...alerts.map(
            (alert) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.radio_button_checked, size: 12, color: color),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '${alert['name']?.toString() ?? 'unknown'}: ${alert['message']?.toString() ?? '-'}',
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
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

  Widget _buildHeroMetric({required IconData icon, required String label, required String value}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.14),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Colors.white, size: 20),
          const SizedBox(height: 10),
          Text(
            value,
            style: AppTextStyles.heading5.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: AppTextStyles.bodySmall.copyWith(color: Colors.white.withOpacity(0.82)),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusChip(bool healthy) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.18),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            healthy ? Icons.check_circle : Icons.report_problem,
            color: Colors.white,
            size: 18,
          ),
          const SizedBox(width: 6),
          Text(
            _statusLabel(healthy),
            style: AppTextStyles.labelLarge.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickStats() {
    final cards = [
      _smallStatCard(
        'Queues',
        '${_summary['queueCount'] ?? _queues.length}',
        Icons.view_agenda_outlined,
        AppColors.info,
      ),
      _smallStatCard(
        'Waiting',
        '${_summary['waitingJobsTotal'] ?? 0}',
        Icons.hourglass_bottom_outlined,
        AppColors.warning,
      ),
      _smallStatCard(
        'Failed',
        '${_summary['failedJobsTotal'] ?? 0}',
        Icons.error_outline,
        AppColors.error,
      ),
      _smallStatCard(
        'Platform Metrics',
        '${_summary['platformMetricCount'] ?? _platformMetrics.length}',
        Icons.query_stats_outlined,
        AppColors.success,
      ),
    ];

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: cards,
    );
  }

  Widget _smallStatCard(String label, String value, IconData icon, Color color) {
    return Container(
      width: (MediaQuery.of(context).size.width - 44) / 2,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.divider),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: AppTextStyles.heading5.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  label,
                  style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSystemHealthCard() {
    final middleware = _systemHealth['middleware'];
    final middlewareMap = middleware is Map ? Map<String, dynamic>.from(middleware) : <String, dynamic>{};
    final database = _systemHealth['database']?.toString() ?? '-';
    final redis = _systemHealth['redis']?.toString() ?? '-';

    return _sectionCard(
      title: 'System Health',
      subtitle: 'สถานะพื้นฐานของ backend, database และ redis',
      icon: Icons.health_and_safety_outlined,
      child: Column(
        children: [
          _infoRow('Backend', _systemHealth['status']?.toString() ?? 'unknown', _systemHealth['status'] == 'ok'),
          _infoRow('Database', database, database == 'connected'),
          _infoRow('Redis', redis, redis == 'connected'),
          _infoRow('Rate Limiter', middlewareMap['rateLimiter']?.toString() ?? '-', true),
          _infoRow('Idempotency', middlewareMap['idempotency']?.toString() ?? '-', true),
          _infoRow('Cache-Aside', middlewareMap['cacheAside']?.toString() ?? '-', true),
        ],
      ),
    );
  }

  Widget _buildQueueOverviewCard(int waitingLimit, int failedLimit) {
    final waiting = _toInt(_summary['waitingJobsTotal']);
    final failed = _toInt(_summary['failedJobsTotal']);

    return _sectionCard(
      title: 'Queue Overview',
      subtitle: 'เปรียบเทียบ backlog กับ threshold ที่ใช้เฝ้าระวัง',
      icon: Icons.queue_play_next_outlined,
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: _thresholdCard('Waiting', waiting, waitingLimit, AppColors.warning)),
              const SizedBox(width: 12),
              Expanded(child: _thresholdCard('Failed', failed, failedLimit, AppColors.error)),
            ],
          ),
          const SizedBox(height: 16),
          _statusBanner(
            _summary['queueHealthy'] == true,
            _summary['queueHealthy'] == true
                ? 'Queue อยู่ในระดับปลอดภัย'
                : 'Queue มีความเสี่ยง ควร inspect failed jobs และ backlog ทันที',
          ),
        ],
      ),
    );
  }

  Widget _thresholdCard(String label, int value, int limit, Color color) {
    final ratio = limit <= 0 ? 0.0 : (value / limit).clamp(0.0, 1.0);
    final overLimit = limit > 0 && value > limit;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text(
            '$value${limit > 0 ? ' / $limit' : ''}',
            style: AppTextStyles.heading5.copyWith(
              fontWeight: FontWeight.w700,
              color: overLimit ? AppColors.error : AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: limit > 0 ? ratio : null,
              minHeight: 8,
              backgroundColor: color.withOpacity(0.12),
              valueColor: AlwaysStoppedAnimation<Color>(overLimit ? AppColors.error : color),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQueueList() {
    return _sectionCard(
      title: 'Queue Details',
      subtitle: 'ตรวจสุขภาพรายคิวแบบเจาะลึก',
      icon: Icons.list_alt_outlined,
      child: _queues.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                _isLoading ? 'กำลังดึงข้อมูล queue...' : 'ยังไม่มีข้อมูล queue',
                style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary),
              ),
            )
          : Column(
              children: _queues.map((queue) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _buildQueueCard(queue),
              )).toList(),
            ),
    );
  }

  Widget _buildQueueCard(Map<String, dynamic> queue) {
    final name = queue['name']?.toString() ?? queue['queueName']?.toString() ?? 'unknown-queue';
    final healthy = queue['healthy'] == true;
    final waiting = _toInt(queue['waiting']);
    final active = _toInt(queue['active']);
    final completed = _toInt(queue['completed']);
    final failed = _toInt(queue['failed']);
    final latencyMs = _toDouble(queue['latencyMs']);
    final thresholds = queue['thresholds'];
    final thresholdMap = thresholds is Map ? Map<String, dynamic>.from(thresholds) : <String, dynamic>{};
    final maxWaiting = _toInt(thresholdMap['maxWaiting']);
    final maxFailed = _toInt(thresholdMap['maxFailed']);
    final waitingRatio = maxWaiting <= 0 ? 0.0 : (waiting / maxWaiting).clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: healthy ? AppColors.divider : AppColors.error.withOpacity(0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  name,
                  style: AppTextStyles.heading5.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              _queueBadge(healthy),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _miniMetricChip('waiting', '$waiting', Icons.schedule_outlined, AppColors.warning),
              _miniMetricChip('active', '$active', Icons.play_circle_outline, AppColors.info),
              _miniMetricChip('completed', '$completed', Icons.check_circle_outline, AppColors.success),
              _miniMetricChip('failed', '$failed', Icons.error_outline, AppColors.error),
              _miniMetricChip('latency', '${latencyMs.toStringAsFixed(0)} ms', Icons.speed, AppColors.primaryDark),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: maxWaiting > 0 ? waitingRatio : null,
              minHeight: 8,
              backgroundColor: AppColors.warning.withOpacity(0.12),
              valueColor: AlwaysStoppedAnimation<Color>(healthy ? AppColors.warning : AppColors.error),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Threshold: waiting ${maxWaiting > 0 ? maxWaiting : '-'} / failed ${maxFailed > 0 ? maxFailed : '-'}',
                  style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
                ),
              ),
              Text(
                'Last completed: ${queue['lastCompletedAt'] ?? '-'}',
                style: AppTextStyles.bodySmall.copyWith(color: AppColors.textHint),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Last failed: ${queue['lastFailedAt'] ?? '-'}',
            style: AppTextStyles.bodySmall.copyWith(color: AppColors.textHint),
          ),
        ],
      ),
    );
  }

  Widget _queueBadge(bool healthy) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: (healthy ? AppColors.success : AppColors.error).withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        healthy ? 'HEALTHY' : 'UNHEALTHY',
        style: AppTextStyles.labelSmall.copyWith(
          color: healthy ? AppColors.success : AppColors.error,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _miniMetricChip(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            '$label: $value',
            style: AppTextStyles.labelSmall.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUsageAndCostCard() {
    final estimatedMapCost = _toDouble(_summary['estimatedMapCost']);
    final totalRequests = _toInt(_summary['totalRequests']);

    final metrics = _platformMetrics.take(6).toList();

    return _sectionCard(
      title: 'Usage & Cost Guardrails',
      subtitle: 'ตัวชี้วัดที่ช่วยคุมค่าใช้จ่ายก่อนจะโตเกิน budget',
      icon: Icons.payments_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _costCard(
                  'Estimated Web Map Cost',
                  '\$${estimatedMapCost.toStringAsFixed(2)}',
                  Icons.map_outlined,
                  estimatedMapCost > 0 ? AppColors.warning : AppColors.success,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _costCard(
                  'Total Metrics Events',
                  '$totalRequests',
                  Icons.analytics_outlined,
                  AppColors.info,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'Cost-related settings',
            style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          _configRow('Database mode', AppConfig.databaseMode.name),
          _configRow('Console OTP (no SMS cost)', AppConfig.useConsoleOtp ? 'Enabled' : 'Disabled'),
          _configRow('AI mode', AppConfig.vegaAiMode.name),
          _configRow('AI kill switch', AppConfig.vegaAiKillSwitch ? 'ON' : 'OFF'),
          _configRow('Push notifications', AppConfig.enablePushNotifications ? 'Enabled' : 'Disabled'),
          _configRow('Web map switch', PlatformService.isWebMapEnabled ? 'Enabled' : 'Disabled'),
          _configRow('Video quota / day', '${SyncConfig.dailyVideoUploadQuota} uploads'),
          _configRow('Video file size cap', '${SyncConfig.maxVideoFileSizeMB} MB'),
          _configRow('Video cooldown', '${SyncConfig.videoUploadCooldownSeconds} sec'),
          _configRow('Emergency recording cap', '${SyncConfig.maxEmergencyRecordingSeconds} sec'),
          if (metrics.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              'Top platform metrics',
              style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            ...metrics.map((metric) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _metricRow(metric),
            )),
          ],
        ],
      ),
    );
  }

  Widget _costCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withOpacity(0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color),
          const SizedBox(height: 10),
          Text(
            value,
            style: AppTextStyles.heading5.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _configRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 3,
            child: Text(
              value,
              style: AppTextStyles.bodySmall.copyWith(fontWeight: FontWeight.w600),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  Widget _metricRow(Map<String, dynamic> metric) {
    final platform = metric['platform']?.toString().toUpperCase() ?? 'UNKNOWN';
    final metricName = metric['metric_name']?.toString() ?? 'unknown';
    final count = _toInt(metric['count']);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.tune, size: 16, color: AppColors.primaryDark),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(metricName, style: AppTextStyles.bodySmall.copyWith(fontWeight: FontWeight.w600)),
                Text(platform, style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary)),
              ],
            ),
          ),
          Text(
            '$count',
            style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  Widget _buildCostPreventionControls() {
    return _sectionCard(
      title: 'Control Center',
      subtitle: 'ทางลัดไปยังหน้าควบคุมที่ช่วยลดค่าใช้จ่ายตามการใช้งาน',
      icon: Icons.admin_panel_settings_outlined,
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          _actionButton(
            label: 'Platform Settings',
            icon: Icons.settings_applications_outlined,
            onPressed: () => Navigator.pushNamed(context, '/admin/platform-settings'),
          ),
          _actionButton(
            label: 'Video Controls',
            icon: Icons.video_settings_outlined,
            onPressed: () => Navigator.pushNamed(context, '/admin/video-control'),
          ),
          _actionButton(
            label: 'Sync Settings',
            icon: Icons.sync,
            onPressed: () => Navigator.pushNamed(context, '/settings/sync'),
          ),
          _actionButton(
            label: 'Queue Health',
            icon: Icons.health_and_safety_outlined,
            onPressed: _loadData,
          ),
        ],
      ),
    );
  }

  Widget _actionButton({required String label, required IconData icon, required VoidCallback onPressed}) {
    return SizedBox(
      width: MediaQuery.of(context).size.width > 700 ? 220 : double.infinity,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          foregroundColor: AppColors.primaryDark,
          side: BorderSide(color: AppColors.primary.withOpacity(0.35)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
    );
  }

  Widget _buildRecommendationsCard() {
    final recommendations = <String>[];

    if (_summary['queueHealthy'] != true) {
      recommendations.add('ตรวจ failed jobs และ requeue jobs ที่จำเป็นก่อน backlog โตขึ้น');
    }
    if (_toDouble(_summary['estimatedMapCost']) > 0) {
      recommendations.add('ลดการใช้ Web Map ที่ไม่จำเป็น หรือปิดในหน้า Platform Settings');
    }
    if (AppConfig.vegaAiMode == VegaAiMode.live && !AppConfig.vegaAiKillSwitch) {
      recommendations.add('ใช้ AI kill-switch เมื่อมี burst usage หรือค่าใช้จ่ายเกิน budget');
    }
    if (SyncConfig.dailyVideoUploadQuota > 50) {
      recommendations.add('ถ้าผู้ใช้เพิ่มขึ้นมาก ให้ลด video quota ต่อวันลงเพื่อคุม CPU/IO');
    }
    if (recommendations.isEmpty) {
      recommendations.add('สถานะระบบปกติ: รักษา config ปัจจุบันและตรวจ queue health เป็นระยะ');
    }

    return _sectionCard(
      title: 'Recommended Actions',
      subtitle: 'ข้อแนะนำเพื่อป้องกันการใช้ทรัพยากรเกินจำเป็น',
      icon: Icons.recommend_outlined,
      child: Column(
        children: recommendations
            .map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 2),
                      child: Icon(Icons.check_circle, size: 18, color: AppColors.success),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        item,
                        style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textPrimary),
                      ),
                    ),
                  ],
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _buildErrorCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.error.withOpacity(0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.error.withOpacity(0.18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, color: AppColors.error),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'ไม่สามารถโหลดข้อมูลบางส่วนได้: $_errorMessage',
              style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.divider),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: AppColors.primaryDark, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppTextStyles.heading5.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value, bool healthy) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
            ),
          ),
          Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.centerRight,
              child: _queueBadge(healthy),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 3,
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: AppTextStyles.bodySmall.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusBanner(bool healthy, String message) {
    final color = healthy ? AppColors.success : AppColors.error;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.15)),
      ),
      child: Row(
        children: [
          Icon(healthy ? Icons.verified_outlined : Icons.warning_amber_rounded, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
