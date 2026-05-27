import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../../utils/chart_metric_helpers.dart';
import 'metric_group_card.dart';

LineChartData buildWeightHistoryChartData(
  List<Map<String, dynamic>> chartPoints,
  Color color,
  double minY,
  double maxY,
) {
  final spots = chartPoints.length == 1
      ? [
          FlSpot(0, chartPoints.first['value'] as double),
          FlSpot(1, chartPoints.first['value'] as double),
        ]
      : [
          for (var i = 0; i < chartPoints.length; i++)
            FlSpot(i.toDouble(), chartPoints[i]['value'] as double),
        ];
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
      getDrawingHorizontalLine: (_) => FlLine(
        color: color.withOpacity(0.08),
        strokeWidth: 1,
      ),
    ),
    titlesData: const FlTitlesData(show: false),
    borderData: FlBorderData(show: false),
    lineTouchData: LineTouchData(
      enabled: true,
      handleBuiltInTouches: true,
      touchTooltipData: LineTouchTooltipData(
        getTooltipColor: (_) => color.withOpacity(0.95),
        tooltipRoundedRadius: 14.0,
        tooltipPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        fitInsideHorizontally: true,
        fitInsideVertically: true,
        getTooltipItems: (touchedSpots) {
          return touchedSpots.map((spot) {
            final index = spot.spotIndex.clamp(0, chartPoints.length - 1) as int;
            final point = chartPoints[index];
            final value = formatMetricValue(point['value']);
            final dateText = formatMetricDate(point['measuredAt']);
            return LineTooltipItem(
              '$value กก.\n$dateText',
              const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            );
          }).toList();
        },
      ),
    ),
    lineBarsData: [
      LineChartBarData(
        spots: spots,
        isCurved: true,
        curveSmoothness: 0.28,
        color: color,
        barWidth: 3.2,
        isStrokeCapRound: true,
        dotData: FlDotData(
          show: true,
          getDotPainter: (_, __, ___, ____) => FlDotCirclePainter(
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
            colors: [color.withOpacity(0.28), color.withOpacity(0.03)],
          ),
        ),
      ),
    ],
  );
}

class WeightPointLabels extends StatelessWidget {
  final List<Map<String, dynamic>> points;
  final Color color;
  final double minY;
  final double maxY;

  const WeightPointLabels({
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
                  left: points.length == 1 ? chartWidth / 2 - 20 : (step * i) - 20,
                  top: topPadding +
                      ((maxY - (points[i]['value'] as double)) / (usableRange == 0 ? 1 : usableRange)) *
                          chartHeight -
                      28,
                  child: PointValueBubble(
                    value: '${formatMetricValue(points[i]['value'])} กก.',
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

class WeightHistoryCard extends StatelessWidget {
  final List<Map<String, dynamic>> weightHistory;

  const WeightHistoryCard({super.key, required this.weightHistory});

  @override
  Widget build(BuildContext context) {
    final points = List<Map<String, dynamic>>.from(weightHistory)
      ..sort((a, b) {
        final aDate = DateTime.tryParse(a['measured_at']?.toString() ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final bDate = DateTime.tryParse(b['measured_at']?.toString() ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0);
        return aDate.compareTo(bDate);
      });

    final chartPoints = points
        .map(
          (item) => <String, dynamic>{
            'value': double.tryParse(item['value']?.toString() ?? '') ?? 0.0,
            'measuredAt':
                DateTime.tryParse(item['measured_at']?.toString() ?? '') ??
                DateTime.now(),
          },
        )
        .toList();

    if (chartPoints.isEmpty) return const SizedBox.shrink();

    final values = chartPoints.map((e) => e['value'] as double).toList();
    final latest = chartPoints.last;
    var maxVal = values.reduce(math.max);
    var minVal = values.reduce(math.min);
    if (maxVal == minVal) {
      maxVal += 1;
      minVal -= 1;
    }

    final range = (maxVal - minVal).abs();
    final padding = range < 0.001 ? 1.0 : range * 0.22;
    final minY = minVal - padding;
    final maxY = maxVal + padding;
    const chartColor = Color(0xFF5B9A8B);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: chartColor.withOpacity(0.12)),
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
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: chartColor.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.monitor_weight_outlined,
                  size: 18,
                  color: chartColor,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'กราฟน้ำหนัก',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'แนวโน้ม 10 รายการล่าสุด',
                      style: TextStyle(fontSize: 11, color: Colors.black54),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${formatMetricValue(latest['value'])} กก.',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: chartColor,
                    ),
                  ),
                  Text(
                    DateFormat('dd MMM HH:mm')
                        .format((latest['measuredAt'] as DateTime).toLocal()),
                    style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 210,
            child: Stack(
              children: [
                Positioned.fill(
                  child: LineChart(
                    buildWeightHistoryChartData(chartPoints, chartColor, minY, maxY),
                  ),
                ),
                Positioned.fill(
                  child: WeightPointLabels(
                    points: chartPoints,
                    color: chartColor,
                    minY: minY,
                    maxY: maxY,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
