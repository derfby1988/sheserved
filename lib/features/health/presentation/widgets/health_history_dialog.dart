import 'dart:ui';
import 'package:flutter/material.dart';
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
    
    final pagedLogs = allLogs.isEmpty ? <HealthDataChangeLog>[] : allLogs.sublist(startIndex, endIndex);

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
                if (allLogs.isNotEmpty) ...[
                  _buildTrendGraph(allLogs),
                  const SizedBox(height: 16),
                ],
                
                // Header Row
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
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
                            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textHint),
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
                            separatorBuilder: (context, index) => const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final log = pagedLogs[index];
                              final sequenceNum = allLogs.length - (startIndex + index);
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                                child: Row(
                                  children: [
                                    _buildDataCell('$sequenceNum', flex: 1, isBold: true),
                                    _buildDataCell(_formatDate(log.timestamp), flex: 2),
                                    _buildDataCell('${_formatValue(log.oldValue)} -> ${_formatValue(log.newValue)}', flex: 3),
                                    _buildDataCell(log.editorName ?? 'Unknown', flex: 2),
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
                            side: const BorderSide(color: Color(0xFF679E83), width: 1.5),
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
          onPressed: _currentPage > 0 ? () => setState(() => _currentPage = 0) : null,
        ),
        _buildPageButton(
          icon: Icons.chevron_left,
          onPressed: _currentPage > 0 ? () => setState(() => _currentPage--) : null,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'หน้า ${_currentPage + 1} / $totalPages',
            style: AppTextStyles.bodySmall.copyWith(fontWeight: FontWeight.bold),
          ),
        ),
        _buildPageButton(
          icon: Icons.chevron_right,
          onPressed: _currentPage < totalPages - 1 ? () => setState(() => _currentPage++) : null,
        ),
        _buildPageButton(
          icon: Icons.last_page,
          onPressed: _currentPage < totalPages - 1 ? () => setState(() => _currentPage = totalPages - 1) : null,
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
    // Show only last 10 entries for the graph, and reverse to show oldest to newest (left to right)
    final graphLogs = logs.take(10).toList().reversed.toList();
    
    // Parse numeric values from "X kg" or "X.Y"
    final List<double> values = graphLogs.map((log) {
      final String numericPart = log.newValue.split(' ').first;
      return double.tryParse(numericPart) ?? 0.0;
    }).toList();

    if (values.isEmpty) return const SizedBox.shrink();

    // Find min/max for scaling
    double maxVal = values.reduce((a, b) => a > b ? a : b);
    double minVal = values.reduce((a, b) => a < b ? a : b);
    
    // Ensure there's a range to avoid division by zero
    if (maxVal == minVal) {
      maxVal += 1;
      minVal -= 1;
    }

    return Container(
      height: 100,
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: values.map((val) {
          // Calculate relative height (0.3 to 1.0 of the box)
          final double hPercent = 0.3 + (0.7 * (val - minVal) / (maxVal - minVal));
          
          return Flexible(
            child: Container(
              width: 12,
              height: 100 * hPercent,
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xFF90E7A6), // Mint Green top
                    Color(0xFFB4E1F4), // Light Blue bottom
                  ],
                ),
                borderRadius: BorderRadius.circular(6),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF90E7A6).withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
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
      'ม.ค.', 'ก.พ.', 'มี.ค.', 'เม.ย.', 'พ.ค.', 'มิ.ย.',
      'ก.ค.', 'ส.ค.', 'ก.ย.', 'ต.ค.', 'พ.ย.', 'ธ.ค.'
    ];
    return months[month - 1];
  }
}
