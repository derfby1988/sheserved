import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../../../config/app_config.dart';
import '../../../../services/platform_service.dart';

class SystemMonitorService {
  static SystemMonitorService? _instance;
  final String _baseUrl;

  SystemMonitorService._(this._baseUrl);

  factory SystemMonitorService({String? baseUrl}) {
    _instance ??= SystemMonitorService._(baseUrl ?? AppConfig.localApiUrl);
    return _instance!;
  }

  static void reset() {
    _instance = null;
  }

  Future<Map<String, String>> get _headers async {
    return const {'Content-Type': 'application/json', 'Accept': 'application/json'};
  }

  Future<Map<String, dynamic>> _getJson(String endpoint) async {
    final response = await http.get(
      Uri.parse('$_baseUrl$endpoint'),
      headers: await _headers,
    );

    if (response.statusCode != 200) {
      throw Exception('GET $endpoint failed: ${response.statusCode}');
    }

    final decoded = json.decode(response.body);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }

    return <String, dynamic>{'data': decoded};
  }

  Future<Map<String, dynamic>> fetchSystemHealth() async {
    try {
      return await _getJson('/health');
    } catch (e) {
      debugPrint('SystemMonitorService: failed to fetch /health: $e');
      return {
        'status': 'error',
        'error': e.toString(),
      };
    }
  }

  Future<Map<String, dynamic>> fetchQueueHealth() async {
    try {
      return await _getJson('/health/queues');
    } catch (e) {
      debugPrint('SystemMonitorService: failed to fetch /health/queues: $e');
      return {
        'healthy': false,
        'error': e.toString(),
        'queues': <dynamic>[],
      };
    }
  }

  Future<List<Map<String, dynamic>>> fetchPlatformMetrics() async {
    try {
      final data = await PlatformService.getMetrics();
      return data;
    } catch (e) {
      debugPrint('SystemMonitorService: failed to fetch platform metrics: $e');
      return <Map<String, dynamic>>[];
    }
  }

  Map<String, dynamic> buildCostGuardrailSummary({
    required Map<String, dynamic> systemHealth,
    required Map<String, dynamic> queueHealth,
    required List<Map<String, dynamic>> metrics,
  }) {
    final queues = List<Map<String, dynamic>>.from(queueHealth['queues'] ?? const []);
    final failingQueues = queues.where((queue) {
      final healthy = queue['healthy'];
      return healthy == false;
    }).toList();

    final totalRequests = metrics.fold<int>(0, (sum, metric) {
      final count = int.tryParse(metric['count']?.toString() ?? '0') ?? 0;
      return sum + count;
    });

    final webMapMetrics = metrics.where((metric) {
      final platform = metric['platform']?.toString().toLowerCase() ?? '';
      final metricName = metric['metric_name']?.toString().toLowerCase() ?? '';
      return platform == 'web' && metricName.startsWith('map_load_');
    }).toList();

    final estimatedMapCost = webMapMetrics.fold<double>(0.0, (sum, metric) {
      final count = int.tryParse(metric['count']?.toString() ?? '0') ?? 0;
      return sum + (count / 1000.0) * 7.0;
    });

    final queueAlerts = <Map<String, dynamic>>[];
    for (final queue in queues) {
      final name = queue['name']?.toString() ?? queue['queueName']?.toString() ?? 'unknown-queue';
      final healthy = queue['healthy'] == true;
      final waiting = int.tryParse(queue['waiting']?.toString() ?? '0') ?? 0;
      final failed = int.tryParse(queue['failed']?.toString() ?? '0') ?? 0;
      final thresholds = queue['thresholds'];
      final thresholdMap = thresholds is Map ? Map<String, dynamic>.from(thresholds) : <String, dynamic>{};
      final maxWaiting = int.tryParse(thresholdMap['maxWaiting']?.toString() ?? '0') ?? 0;
      final maxFailed = int.tryParse(thresholdMap['maxFailed']?.toString() ?? '0') ?? 0;

      final queueSeverity = _deriveSeverity(
        current: waiting,
        warningThreshold: maxWaiting <= 0 ? 0 : (maxWaiting * 0.8).round(),
        criticalThreshold: maxWaiting,
      );
      final failedSeverity = _deriveSeverity(
        current: failed,
        warningThreshold: maxFailed <= 0 ? 0 : (maxFailed * 0.8).round(),
        criticalThreshold: maxFailed,
      );

      if (!healthy || queueSeverity != 'info' || failedSeverity != 'info') {
        queueAlerts.add({
          'type': 'queue',
          'name': name,
          'severity': _pickHigherSeverity(queueSeverity, failedSeverity, healthy ? 'info' : 'critical'),
          'message': failed > 0
              ? '$name มี failed jobs $failed รายการ'
              : '$name backlog อยู่ที่ $waiting / ${maxWaiting > 0 ? maxWaiting : '-'}',
        });
      }
    }

    const mapCostWarning = 20.0;
    const mapCostCritical = 50.0;
    final usageAlerts = <Map<String, dynamic>>[];
    if (estimatedMapCost >= mapCostWarning) {
      usageAlerts.add({
        'type': 'usage',
        'name': 'web_map_cost',
        'severity': estimatedMapCost >= mapCostCritical ? 'critical' : 'warning',
        'message': 'ค่าใช้จ่าย Web Map โดยประมาณอยู่ที่ \$${estimatedMapCost.toStringAsFixed(2)}',
      });
    }

    final alerts = [...queueAlerts, ...usageAlerts]
      ..sort((a, b) {
        const order = {'critical': 0, 'warning': 1, 'info': 2};
        return (order[a['severity']] ?? 2).compareTo(order[b['severity']] ?? 2);
      });

    return {
      'systemHealthy': systemHealth['status'] == 'ok',
      'queueHealthy': queueHealth['healthy'] == true,
      'queueCount': queues.length,
      'failingQueueCount': failingQueues.length,
      'failedJobsTotal': queues.fold<int>(0, (sum, queue) {
        return sum + (int.tryParse(queue['failed']?.toString() ?? '0') ?? 0);
      }),
      'waitingJobsTotal': queues.fold<int>(0, (sum, queue) {
        return sum + (int.tryParse(queue['waiting']?.toString() ?? '0') ?? 0);
      }),
      'completedJobsTotal': queues.fold<int>(0, (sum, queue) {
        return sum + (int.tryParse(queue['completed']?.toString() ?? '0') ?? 0);
      }),
      'platformMetricCount': metrics.length,
      'totalRequests': totalRequests,
      'estimatedMapCost': estimatedMapCost,
      'alerts': alerts,
      'criticalAlertCount': alerts.where((alert) => alert['severity'] == 'critical').length,
      'warningAlertCount': alerts.where((alert) => alert['severity'] == 'warning').length,
      'recommendedAction': failingQueues.isNotEmpty || queueHealth['healthy'] != true
          ? 'ตรวจสอบ failed queues และลดโหลดก่อน'
          : estimatedMapCost > 0
              ? 'พิจารณาปิด Web Map ที่ไม่จำเป็นเพื่อลดค่าใช้จ่าย'
              : 'สถานะปกติ',
    };
  }

  String _deriveSeverity({required int current, required int warningThreshold, required int criticalThreshold}) {
    if (criticalThreshold > 0 && current >= criticalThreshold) {
      return 'critical';
    }
    if (warningThreshold > 0 && current >= warningThreshold) {
      return 'warning';
    }
    return 'info';
  }

  String _pickHigherSeverity(String first, String second, String third) {
    const order = {'critical': 0, 'warning': 1, 'info': 2};
    final values = [first, second, third];
    values.sort((a, b) => (order[a] ?? 2).compareTo(order[b] ?? 2));
    return values.first;
  }
}
