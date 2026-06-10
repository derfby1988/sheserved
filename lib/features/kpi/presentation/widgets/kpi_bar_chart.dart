import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../data/models/kpi_models.dart';

class KpiBarChart extends StatelessWidget {
  final List<KpiActual> data;
  final String targetType;

  const KpiBarChart({
    super.key,
    required this.data,
    required this.targetType,
  });

  Color _barColor(double achievementRate) {
    if (achievementRate >= 100) return const Color(0xFF4CAF50);
    if (achievementRate >= 80) return const Color(0xFFFFA726);
    if (achievementRate >= 60) return const Color(0xFFFF7043);
    return const Color(0xFFEF5350);
  }

  String _formatDate(DateTime date, String periodType) {
    switch (periodType) {
      case 'daily':
        return '${date.day}/${date.month}';
      case 'weekly':
        return 'W${date.day}/${date.month}';
      case 'monthly':
        return '${date.month}/${date.year.toString().substring(2)}';
      case 'quarterly':
        final q = ((date.month - 1) ~/ 3) + 1;
        return 'Q$q ${date.year}';
      case 'yearly':
        return '${date.year}';
      default:
        return '${date.day}/${date.month}';
    }
  }

  String _formatValue(double value) {
    if (value >= 1000000) return '${(value / 1000000).toStringAsFixed(1)}M';
    if (value >= 1000) return '${(value / 1000).toStringAsFixed(1)}K';
    return value.toStringAsFixed(0);
  }

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return Card(
        child: SizedBox(
          height: 280,
          child: Center(
            child: Text(
              'ไม่มีข้อมูล',
              style: TextStyle(color: Colors.grey[500]),
            ),
          ),
        ),
      );
    }

    // เรียงจากเก่าไปใหม่ แล้วเอา max 10 ช่วงล่าสุด
    final sorted = data.toList()..sort((a, b) => a.periodStart.compareTo(b.periodStart));
    final displayData = sorted.length > 10 ? sorted.sublist(sorted.length - 10) : sorted;

    final barGroups = displayData.asMap().entries.map((entry) {
      final index = entry.key;
      final item = entry.value;
      final maxVal = item.actualAmount > item.targetAmount
          ? item.actualAmount
          : item.targetAmount;
      final normalizedHeight = maxVal > 0
          ? (item.actualAmount / maxVal * 100).clamp(5, 100)
          : 5;

      return BarChartGroupData(
        x: index,
        barRods: [
          BarChartRodData(
            toY: item.actualAmount,
            color: _barColor(item.achievementRate),
            width: 16,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
          ),
        ],
        showingTooltipIndicators: [],
      );
    }).toList();

    final maxY = displayData
        .map((e) => e.actualAmount > e.targetAmount ? e.actualAmount : e.targetAmount)
        .fold(0.0, (a, b) => a > b ? a : b);

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Actual vs Target — $targetType',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 240,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY: maxY * 1.2,
                  barGroups: barGroups,
                  gridData: const FlGridData(show: false),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 50,
                        getTitlesWidget: (value, meta) {
                          return Text(
                            _formatValue(value),
                            style: const TextStyle(fontSize: 10, color: Colors.grey),
                          );
                        },
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          final idx = value.toInt();
                          if (idx < 0 || idx >= displayData.length) return const SizedBox.shrink();
                          return Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              _formatDate(displayData[idx].periodStart, displayData.first.periodType),
                              style: const TextStyle(fontSize: 10, color: Colors.grey),
                            ),
                          );
                        },
                      ),
                    ),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  borderData: FlBorderData(show: false),
                  barTouchData: BarTouchData(
                    enabled: true,
                    touchTooltipData: BarTouchTooltipData(
                      getTooltipItem: (group, groupIndex, rod, rodIndex) {
                        final item = displayData[group.x];
                        return BarTooltipItem(
                          '${item.achievementRate.toStringAsFixed(1)}%\n',
                          const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                          children: [
                            TextSpan(
                              text: 'Actual: ${_formatValue(item.actualAmount)}\n',
                              style: const TextStyle(fontSize: 12),
                            ),
                            TextSpan(
                              text: 'Target: ${_formatValue(item.targetAmount)}',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
