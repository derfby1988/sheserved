import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../utils/chart_metric_helpers.dart';

class PointValueBubble extends StatelessWidget {
  final String value;
  final String dateText;
  final Color color;

  const PointValueBubble({
    super.key,
    required this.value,
    required this.dateText,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.18),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            dateText,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 8,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class MiniStatChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const MiniStatChip({
    super.key,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: color,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

LineChartData buildMetricLineChartData(
  List<double> values,
  Color color,
  double minY,
  double maxY,
) {
  final spots = buildSpots(values);
  final range = (maxY - minY).abs();

  return LineChartData(
    minX: 0,
    maxX: (spots.length - 1).toDouble(),
    minY: minY,
    maxY: maxY,
    gridData: FlGridData(
      show: true,
      drawVerticalLine: false,
      horizontalInterval: range < 0.001 ? 1 : range / 3,
      getDrawingHorizontalLine: (value) => FlLine(
        color: color.withOpacity(0.08),
        strokeWidth: 1,
      ),
    ),
    titlesData: const FlTitlesData(show: false),
    borderData: FlBorderData(show: false),
    lineTouchData: LineTouchData(enabled: false),
    lineBarsData: [
      LineChartBarData(
        spots: spots,
        isCurved: true,
        curveSmoothness: 0.32,
        color: color,
        barWidth: 3.5,
        isStrokeCapRound: true,
        dotData: FlDotData(
          show: true,
          getDotPainter: (spot, percent, barData, index) => FlDotCirclePainter(
            radius: 3.5,
            color: Colors.white,
            strokeColor: color,
            strokeWidth: 2,
          ),
        ),
        belowBarData: BarAreaData(
          show: true,
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              color.withOpacity(0.30),
              color.withOpacity(0.03),
            ],
          ),
        ),
      ),
    ],
  );
}

class MetricPointLabels extends StatelessWidget {
  final List<Map<String, dynamic>> points;
  final Color color;
  final double minY;
  final double maxY;

  const MetricPointLabels({
    super.key,
    required this.points,
    required this.color,
    required this.minY,
    required this.maxY,
  });

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) return const SizedBox.shrink();

    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final chartWidth = constraints.maxWidth;
          const topPadding = 18.0;
          const bottomPadding = 18.0;
          final chartHeight = math.max(1.0, constraints.maxHeight - topPadding - bottomPadding);
          final usableRange = (maxY - minY).abs();
          final step = points.length == 1 ? 0.0 : chartWidth / (points.length - 1);

          return Stack(
            clipBehavior: Clip.none,
            children: [
              for (var i = 0; i < points.length; i++)
                Positioned(
                  left: points.length == 1 ? chartWidth / 2 - 18 : (step * i) - 20,
                  top: topPadding +
                      ((maxY - (points[i]['value'] as double)) / (usableRange == 0 ? 1 : usableRange)) *
                          chartHeight -
                      28,
                  child: PointValueBubble(
                    value: formatMetricValue(points[i]['value']),
                    dateText: formatMetricDate(points[i]['measuredAt']),
                    color: color,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class MetricGroupCard extends StatelessWidget {
  final String metricType;
  final dynamic entries;

  const MetricGroupCard({
    super.key,
    required this.metricType,
    required this.entries,
  });

  @override
  Widget build(BuildContext context) {
    final list = (entries as List?)?.cast<Map<String, dynamic>>() ?? [];
    if (list.isEmpty) return const SizedBox.shrink();
    final sortedList = List<Map<String, dynamic>>.from(list)
      ..sort((a, b) {
        final aTime = DateTime.tryParse(a['measured_at']?.toString() ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final bTime = DateTime.tryParse(b['measured_at']?.toString() ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0);
        return aTime.compareTo(bTime);
      });
    final displayName =
        metricNameTh[metricType] ?? metricType.replaceAll('_', ' ');
    final metricColor = metricChartColor(metricType);
    final chartPoints = sortedList
        .map(
          (item) => <String, dynamic>{
            'value': double.tryParse(item['value']?.toString() ?? '') ?? 0.0,
            'measuredAt': item['measured_at'],
          },
        )
        .toList();

    if (chartPoints.isEmpty) return const SizedBox.shrink();

    final chartValues = chartPoints.map((e) => e['value'] as double).toList();

    final latest = sortedList.last;
    final latestValue = formatMetricValue(latest['value']);
    final latestUnit = (latest['unit'] ?? '').toString().trim();
    final latestTime = formatMetricDate(latest['measured_at']);
    final minValue = chartValues.reduce(math.min);
    final maxValue = chartValues.reduce(math.max);
    final avgValue = chartValues.reduce((a, b) => a + b) / chartValues.length;
    final range = (maxValue - minValue).abs();
    final padding = range < 0.001 ? 1.0 : range * 0.22;
    final minY = minValue - padding;
    final maxY = maxValue + padding;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: metricColor.withOpacity(0.12)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
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
                  color: metricColor.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.show_chart_rounded, size: 18, color: metricColor),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'แนวโน้ม 10 รายการล่าสุด',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '$latestValue${latestUnit.isNotEmpty ? ' $latestUnit' : ''}',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: metricColor,
                    ),
                  ),
                  Text(
                    latestTime,
                    style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 6),
          Container(
            height: 180,
            padding: const EdgeInsets.fromLTRB(4, 10, 4, 6),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  metricColor.withOpacity(0.06),
                  Colors.white,
                ],
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Stack(
              children: [
                Positioned.fill(
                  child: LineChart(
                    buildMetricLineChartData(
                      chartValues,
                      metricColor,
                      minY,
                      maxY,
                    ),
                  ),
                ),
                Positioned.fill(
                  child: MetricPointLabels(
                    points: chartPoints,
                    color: metricColor,
                    minY: minY,
                    maxY: maxY,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: MiniStatChip(
                  label: 'ต่ำสุด',
                  value: formatMetricValue(minValue),
                  color: metricColor,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: MiniStatChip(
                  label: 'เฉลี่ย',
                  value: formatMetricValue(avgValue),
                  color: metricColor,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: MiniStatChip(
                  label: 'สูงสุด',
                  value: formatMetricValue(maxValue),
                  color: metricColor,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
