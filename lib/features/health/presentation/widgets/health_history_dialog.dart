import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../data/models/health_data_change_log.dart';

class HealthHistoryDialog extends StatefulWidget {
  final String title;
  final String fieldType;
  final List<HealthDataChangeLog> historyLogs;

  const HealthHistoryDialog({
    Key? key,
    required this.title,
    required this.fieldType,
    required this.historyLogs,
  }) : super(key: key);

  @override
  State<HealthHistoryDialog> createState() => _HealthHistoryDialogState();
}

class _HealthHistoryDialogState extends State<HealthHistoryDialog> {
  final ScrollController _scrollController = ScrollController();
  int _currentPage = 0;
  static const int _pageSize = 3;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  String _formatValue(String? value) {
    if (value == null || value.trim() == "" || value == "-") return "-";

    // For numeric fields, format to 1 decimal place if it's a number
    if (['weight', 'height', 'bmi'].contains(widget.fieldType)) {
      // Handle cases like "70.5 kg" or just "70.5"
      final parts = value.split(' ');
      final String numericPart = parts.first;
      final String? unitPart = parts.length > 1 ? parts.last : null;

      final double? numericValue = double.tryParse(numericPart);
      if (numericValue != null) {
        final formatted = numericValue.toStringAsFixed(1);
        return unitPart != null ? '$formatted $unitPart' : formatted;
      }
    }

    return value;
  }

  String _formatWeightDate(DateTime date) {
    return DateFormat('dd MMM HH:mm').format(date.toLocal());
  }

  @override
  Widget build(BuildContext context) {
    // Sort logs by timestamp descending (latest first)
    final allLogs = List<HealthDataChangeLog>.from(widget.historyLogs)
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

    final int totalPages = (allLogs.length / _pageSize).ceil();
    final int startIndex = _currentPage * _pageSize;
    final int endIndex = (startIndex + _pageSize < allLogs.length)
        ? startIndex + _pageSize
        : allLogs.length;

    final pagedLogs = allLogs.isEmpty
        ? <HealthDataChangeLog>[]
        : allLogs.sublist(startIndex, endIndex);

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            constraints: const BoxConstraints(maxHeight: 550),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.95),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: Colors.white.withOpacity(0.5),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Title
                Text(
                  widget.title,
                  style: AppTextStyles.heading3.copyWith(
                    color: const Color(0xFF5B9A8B),
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),

                // Trend Graph
                if (allLogs.isNotEmpty && widget.fieldType == 'weight') ...[
                  _buildTrendGraph(allLogs),
                  const SizedBox(height: 16),
                ],

                // Header Row
                Container(
                  padding: const EdgeInsets.symmetric(
                    vertical: 8,
                    horizontal: 12,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF679E83).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      _buildHeaderCell('ลำดับ', flex: 1),
                      _buildHeaderCell('วันที่', flex: 2),
                      _buildHeaderCell('ข้อมูล', flex: 3),
                      _buildHeaderCell('ผู้เปลี่ยน', flex: 2),
                    ],
                  ),
                ),
                const SizedBox(height: 8),

                // Data List
                Flexible(
                  child: pagedLogs.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(32.0),
                          child: Text(
                            'ไม่พบประวัติการเปลี่ยนแปลง',
                            style: AppTextStyles.bodyMedium.copyWith(
                              color: AppColors.textHint,
                            ),
                          ),
                        )
                      : Scrollbar(
                          controller: _scrollController,
                          thumbVisibility: pagedLogs.length > 3,
                          thickness: 6,
                          radius: const Radius.circular(3),
                          child: ListView.separated(
                            controller: _scrollController,
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: pagedLogs.length,
                            separatorBuilder: (context, index) =>
                                const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final log = pagedLogs[index];
                              final sequenceNum =
                                  allLogs.length - (startIndex + index);
                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                  horizontal: 8,
                                ),
                                child: Row(
                                  children: [
                                    _buildDataCell(
                                      '$sequenceNum',
                                      flex: 1,
                                      isBold: true,
                                    ),
                                    _buildDataCell(
                                      _formatDate(log.timestamp),
                                      flex: 2,
                                    ),
                                    _buildDataCell(
                                      '${_formatValue(log.oldValue)} -> ${_formatValue(log.newValue)}',
                                      flex: 3,
                                    ),
                                    _buildDataCell(
                                      log.editorName ?? 'Unknown',
                                      flex: 2,
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                ),

                if (totalPages > 1) ...[
                  const SizedBox(height: 16),
                  _buildPaginationControls(totalPages),
                ],

                const SizedBox(height: 24),

                // Action Buttons
                Row(
                  children: [
                    // Fill More Data Button
                    Expanded(
                      child: Container(
                        height: 48,
                        child: OutlinedButton(
                          onPressed: () {
                            Navigator.of(context).pop(); // Close dialog first
                            Navigator.pushNamed(context, '/health-data-entry');
                          },
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(
                              color: Color(0xFF679E83),
                              width: 1.5,
                            ),
                            backgroundColor: const Color(0xFFE8F3F1),
                            foregroundColor: const Color(0xFF679E83),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(24),
                            ),
                            padding: EdgeInsets.zero,
                          ),
                          child: const Text(
                            'กรอกข้อมูลเพิ่ม',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Close Button
                    Expanded(
                      child: Container(
                        height: 48,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF87B17F), Color(0xFF007FAD)],
                          ),
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF007FAD).withOpacity(0.3),
                              blurRadius: 8,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: ElevatedButton(
                          onPressed: () => Navigator.of(context).pop(),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            shadowColor: Colors.transparent,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(24),
                            ),
                            padding: EdgeInsets.zero,
                          ),
                          child: const Text(
                            'ปิด',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPaginationControls(int totalPages) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildPageButton(
          icon: Icons.first_page,
          onPressed: _currentPage > 0
              ? () => setState(() => _currentPage = 0)
              : null,
        ),
        _buildPageButton(
          icon: Icons.chevron_left,
          onPressed: _currentPage > 0
              ? () => setState(() => _currentPage--)
              : null,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'หน้า ${_currentPage + 1} / $totalPages',
            style: AppTextStyles.bodySmall.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        _buildPageButton(
          icon: Icons.chevron_right,
          onPressed: _currentPage < totalPages - 1
              ? () => setState(() => _currentPage++)
              : null,
        ),
        _buildPageButton(
          icon: Icons.last_page,
          onPressed: _currentPage < totalPages - 1
              ? () => setState(() => _currentPage = totalPages - 1)
              : null,
        ),
      ],
    );
  }

  Widget _buildPageButton({required IconData icon, VoidCallback? onPressed}) {
    return IconButton(
      icon: Icon(icon),
      onPressed: onPressed,
      color: const Color(0xFF5B9A8B),
      disabledColor: Colors.grey.withOpacity(0.3),
      iconSize: 24,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(),
    );
  }

  Widget _buildTrendGraph(List<HealthDataChangeLog> logs) {
    if (widget.fieldType != 'weight') return const SizedBox.shrink();

    final graphLogs = logs.take(10).toList().reversed.toList();
    final points = graphLogs
        .map(
          (log) => {
            'value': double.tryParse(log.newValue.split(' ').first) ?? 0.0,
            'timestamp': log.timestamp,
          },
        )
        .toList();

    if (points.isEmpty) return const SizedBox.shrink();

    final values = points.map((e) => e['value'] as double).toList();
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
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: chartColor.withOpacity(0.12)),
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
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'กราฟน้ำหนัก',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
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
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 190,
            child: Stack(
              children: [
                Positioned.fill(
                  child: LineChart(
                    _buildWeightChartData(
                      values,
                      points,
                      chartColor,
                      minY,
                      maxY,
                    ),
                  ),
                ),
                Positioned.fill(
                  child: _buildWeightPointLabels(points, chartColor, minY, maxY),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  LineChartData _buildWeightChartData(
    List<double> values,
    List<Map<String, dynamic>> points,
    Color color,
    double minY,
    double maxY,
  ) {
    final spots = values.length == 1
        ? [FlSpot(0, values.first), FlSpot(1, values.first)]
        : [for (var i = 0; i < values.length; i++) FlSpot(i.toDouble(), values[i])];
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
              final index = spot.spotIndex.clamp(0, points.length - 1) as int;
              final point = points[index];
              final value = _formatValue('${point['value']}');
              final dateText = _formatWeightDate(point['timestamp'] as DateTime);
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
          curveSmoothness: 0.3,
          color: color,
          barWidth: 3.5,
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

  Widget _buildWeightPointLabels(
    List<Map<String, dynamic>> points,
    Color color,
    double minY,
    double maxY,
  ) {
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (points.isEmpty) return const SizedBox.shrink();
          final width = constraints.maxWidth;
          final height = math.max(1.0, constraints.maxHeight - 18 - 18);
          final step = points.length == 1 ? 0.0 : width / (points.length - 1);
          final usableRange = (maxY - minY).abs();

          return Stack(
            children: [
              for (var i = 0; i < points.length; i++)
                Positioned(
                  left: points.length == 1 ? width / 2 - 34 : (step * i) - 34,
                  top: 12 +
                      ((maxY - (points[i]['value'] as double)) /
                              (usableRange == 0 ? 1 : usableRange)) *
                          height -
                      36,
                  child: _buildWeightPointBubble(
                    value: _formatValue('${points[i]['value']}'),
                    dateText: _formatWeightDate(points[i]['timestamp'] as DateTime),
                    color: color,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildWeightPointBubble({
    required String value,
    required String dateText,
    required Color color,
  }) {
    return Container(
      width: 78,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(16),
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
            '$value กก.',
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            dateText,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 8,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderCell(String text, {required int flex}) {
    return Expanded(
      flex: flex,
      child: Text(
        text,
        style: AppTextStyles.caption.copyWith(
          fontWeight: FontWeight.bold,
          color: const Color(0xFF5B9A8B),
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildDataCell(String text, {required int flex, bool isBold = false}) {
    return Expanded(
      flex: flex,
      child: Text(
        text,
        style: AppTextStyles.bodySmall.copyWith(
          fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
          color: AppColors.textSecondary,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  String _formatDate(DateTime date) {
    // Simple mock thai date format using BE
    final yearBE = date.year + 543;
    final month = _thaiMonth(date.month);
    return '${date.day} $month ${yearBE.toString().substring(2)}'; // e.g. 10 ก.พ. 67
  }

  String _thaiMonth(int month) {
    const months = [
      'ม.ค.',
      'ก.พ.',
      'มี.ค.',
      'เม.ย.',
      'พ.ค.',
      'มิ.ย.',
      'ก.ค.',
      'ส.ค.',
      'ก.ย.',
      'ต.ค.',
      'พ.ย.',
      'ธ.ค.',
    ];
    return months[month - 1];
  }
}
