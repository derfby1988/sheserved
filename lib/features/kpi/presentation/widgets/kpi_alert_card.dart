import 'package:flutter/material.dart';
import '../../data/models/kpi_models.dart';

class KpiAlertCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final double achievementRate;
  final double warningThreshold;
  final double criticalThreshold;
  final VoidCallback? onTap;

  const KpiAlertCard({
    super.key,
    required this.title,
    this.subtitle,
    required this.achievementRate,
    this.warningThreshold = 80,
    this.criticalThreshold = 60,
    this.onTap,
  });

  ({Color color, IconData icon, String label, Color bgColor}) _getStatus() {
    if (achievementRate >= 100) {
      return (
        color: const Color(0xFF4CAF50),
        icon: Icons.check_circle,
        label: 'On Target',
        bgColor: const Color(0xFFE8F5E9),
      );
    }
    if (achievementRate >= warningThreshold) {
      return (
        color: const Color(0xFFFFA726),
        icon: Icons.warning_amber,
        label: 'Warning',
        bgColor: const Color(0xFFFFF3E0),
      );
    }
    if (achievementRate >= criticalThreshold) {
      return (
        color: const Color(0xFFFF7043),
        icon: Icons.notification_important,
        label: 'Critical',
        bgColor: const Color(0xFFFBE9E7),
      );
    }
    return (
      color: const Color(0xFFEF5350),
      icon: Icons.error,
      label: 'Danger',
      bgColor: const Color(0xFFFFEBEE),
    );
  }

  @override
  Widget build(BuildContext context) {
    final status = _getStatus();

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: status.bgColor,
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: status.color.withAlpha(30),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  status.icon,
                  color: status.color,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: Colors.grey[800],
                          ),
                    ),
                    if (subtitle != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          subtitle!,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Colors.grey[600],
                              ),
                        ),
                      ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${achievementRate.toStringAsFixed(1)}%',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: status.color,
                        ),
                  ),
                  const SizedBox(height: 2),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: status.color.withAlpha(30),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      status.label,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: status.color,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
