import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../data/models/kpi_models.dart';

class KpiTrendLine extends StatelessWidget {
  final List<KpiActual> data;
  final String title;

  const KpiTrendLine({
    super.key,
    required this.data,
    this.title = 'Achievement Rate Trend',
  });

  Color _lineColor(double rate) {
    if (rate >= 100) return const Color(0xFF4CAF50);
    if (rate >= 80) return const Color(0xFFFFA726);
    return const Color(0xFFEF5350);
  }

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return Card(
        child: SizedBox(
          height: 260,
          child: Center(
            child: Text(
              'ไม่มีข้อมูล',
              style: TextStyle(color: Colors.grey[500]),
            ),
          ),
        ),
      );
    }

    final sorted = data.toList()..sort((a, b) => a.periodStart.compareTo(b.periodStart));
    final displayData = sorted.length > 30 ? sorted.sublist(sorted.length - 30) : sorted;

    final spots = displayData.asMap().entries.map((entry) {
      return FlSpot(
        entry.key.toDouble(),
        entry.value.achievementRate.clamp(0, 150),
      );
    }).toList();

    final avgRate = displayData.isNotEmpty
        ? displayData.map((e) => e.achievementRate).reduce((a, b) => a + b) / displayData.length
        : 0;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _lineColor(avgRate).withAlpha(30),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'Avg ${avgRate.toStringAsFixed(1)}%',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _lineColor(avgRate),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 220,
              child: LineChart(
                LineChartData(
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: 25,
                    getDrawingHorizontalLine: (value) {
                      return FlLine(
                        color: Colors.grey[200],
                        strokeWidth: 1,
                      );
                    },
                  ),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 40,
                        interval: 25,
                        getTitlesWidget: (value, meta) {
                          return Text(
                            '${value.toInt()}%',
                            style: const TextStyle(fontSize: 10, color: Colors.grey),
                          );
                        },
                      ),
                    ),
                    bottomTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  minY: 0,
                  maxY: 150,
                  lineBarsData: [
                    LineChartBarData(
                      spots: spots,
                      isCurved: true,
                      curveSmoothness: 0.35,
                      color: const Color(0xFF2196F3),
                      barWidth: 3,
                      dotData: FlDotData(
                        show: true,
                        getDotPainter: (spot, percent, bar, index) {
                          final rate = spot.y;
                          return FlDotCirclePainter(
                            radius: 4,
                            color: _lineColor(rate),
                            strokeWidth: 2,
                            strokeColor: Colors.white,
                          );
                        },
                      ),
                      belowBarData: BarAreaData(
                        show: true,
                        color: const Color(0xFF2196F3).withAlpha(20),
                      ),
                    ),
                  ],
                  extraLinesData: ExtraLinesData(
                    horizontalLines: [
                      HorizontalLine(
                        y: 100,
                        color: const Color(0xFF4CAF50),
                        strokeWidth: 1,
                        dashArray: [5, 5],
                        label: HorizontalLineLabel(
                          show: true,
                          labelResolver: (line) => '100%',
                          style: const TextStyle(
                            fontSize: 10,
                            color: Color(0xFF4CAF50),
                          ),
                        ),
                      ),
                      HorizontalLine(
                        y: 80,
                        color: const Color(0xFFFFA726),
                        strokeWidth: 1,
                        dashArray: [5, 5],
                        label: HorizontalLineLabel(
                          show: true,
                          labelResolver: (line) => '80%',
                          style: const TextStyle(
                            fontSize: 10,
                            color: Color(0xFFFFA726),
                          ),
                        ),
                      ),
                    ],
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
