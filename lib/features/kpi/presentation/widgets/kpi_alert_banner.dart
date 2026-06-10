import 'package:flutter/material.dart';
import '../../data/models/kpi_models.dart';

/// In-app alert banner — แสดง critical alerts จาก kpi_actuals
/// ไม่มีค่าใช้จ่าย (pull from Supabase โดยตรง ไม่ใช้ push notification)
class KpiAlertBanner extends StatelessWidget {
  final List<KpiActual> actuals;
  final List<KpiAlertThreshold> thresholds;
  final VoidCallback? onDismiss;
  final VoidCallback? onViewDetails;

  const KpiAlertBanner({
    super.key,
    required this.actuals,
    required this.thresholds,
    this.onDismiss,
    this.onViewDetails,
  });

  /// หา actuals ที่ achievement_rate ต่ำกว่า critical threshold
  List<_AlertItem> _buildAlerts() {
    final alerts = <_AlertItem>[];

    for (final actual in actuals) {
      final threshold = thresholds.firstWhere(
        (t) => t.targetType == actual.targetType,
        orElse: () => KpiAlertThreshold(
          id: '',
          professionId: actual.professionId,
          targetType: actual.targetType,
          warningThresholdPct: 80,
          criticalThresholdPct: 60,
          alertEnabled: true,
          notifyRoles: const ['owner', 'manager'],
        ),
      );

      if (!threshold.alertEnabled) continue;

      if (actual.achievementRate < threshold.criticalThresholdPct) {
        alerts.add(_AlertItem(
          actual: actual,
          level: AlertLevel.danger,
          message:
              '${_targetTypeLabel(actual.targetType)} ต่ำกว่าเกณฑ์วิกฤต (${actual.achievementRate.toStringAsFixed(1)}%)',
        ));
      } else if (actual.achievementRate < threshold.warningThresholdPct) {
        alerts.add(_AlertItem(
          actual: actual,
          level: AlertLevel.warning,
          message:
              '${_targetTypeLabel(actual.targetType)} ต่ำกว่าเกณฑ์เตือน (${actual.achievementRate.toStringAsFixed(1)}%)',
        ));
      }
    }

    return alerts;
  }

  String _targetTypeLabel(String type) {
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

  Color _levelColor(AlertLevel level) {
    switch (level) {
      case AlertLevel.warning:
        return const Color(0xFFFFA726);
      case AlertLevel.critical:
      case AlertLevel.danger:
        return const Color(0xFFEF5350);
      default:
        return const Color(0xFF4CAF50);
    }
  }

  Color _levelBgColor(AlertLevel level) {
    switch (level) {
      case AlertLevel.warning:
        return const Color(0xFFFFF3E0);
      case AlertLevel.critical:
      case AlertLevel.danger:
        return const Color(0xFFFFEBEE);
      default:
        return const Color(0xFFE8F5E9);
    }
  }

  IconData _levelIcon(AlertLevel level) {
    switch (level) {
      case AlertLevel.warning:
        return Icons.warning_amber;
      case AlertLevel.critical:
      case AlertLevel.danger:
        return Icons.error_outline;
      default:
        return Icons.check_circle;
    }
  }

  @override
  Widget build(BuildContext context) {
    final alerts = _buildAlerts();
    if (alerts.isEmpty) return const SizedBox.shrink();

    // แสดงแค่ alert แรก (critical ก่อน แล้ว warning)
    final alert = alerts.first;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _levelBgColor(alert.level),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _levelColor(alert.level).withAlpha(50),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: _levelColor(alert.level).withAlpha(30),
              shape: BoxShape.circle,
            ),
            child: Icon(
              _levelIcon(alert.level),
              color: _levelColor(alert.level),
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  alert.level == AlertLevel.danger ? 'แจ้งเตือนวิกฤต' : 'แจ้งเตือน',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _levelColor(alert.level),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  alert.message,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey[800],
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${alert.actual.actualAmount.toStringAsFixed(0)} / ${alert.actual.targetAmount.toStringAsFixed(0)} (${alert.actual.periodType})',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
          if (onViewDetails != null)
            TextButton(
              onPressed: onViewDetails,
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: const Size(48, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                'ดูรายละเอียด',
                style: TextStyle(
                  fontSize: 12,
                  color: _levelColor(alert.level),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          if (onDismiss != null)
            IconButton(
              icon: const Icon(Icons.close, size: 18),
              onPressed: onDismiss,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
        ],
      ),
    );
  }
}

class _AlertItem {
  final KpiActual actual;
  final AlertLevel level;
  final String message;

  _AlertItem({
    required this.actual,
    required this.level,
    required this.message,
  });
}
