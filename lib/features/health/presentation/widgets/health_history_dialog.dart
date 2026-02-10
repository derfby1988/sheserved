import 'dart:ui';
import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../data/models/health_data_change_log.dart';

class HealthHistoryDialog extends StatelessWidget {
  final String title;
  final List<HealthDataChangeLog> historyLogs;

  const HealthHistoryDialog({
    Key? key,
    required this.title,
    required this.historyLogs,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Sort logs by timestamp descending (latest first)
    final sortedLogs = List<HealthDataChangeLog>.from(historyLogs)
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            constraints: const BoxConstraints(maxHeight: 500),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.95), // High opacity for readability
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
                  title,
                  style: AppTextStyles.heading3.copyWith(
                    color: const Color(0xFF5B9A8B),
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                
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
                      _buildHeaderCell('ข้อมูล', flex: 3), // Old -> New
                      _buildHeaderCell('ผู้เปลี่ยน', flex: 2),
                    ],
                  ),
                ),
                const SizedBox(height: 8),

                // Data List
                Flexible(
                  child: sortedLogs.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(32.0),
                          child: Text(
                            'ไม่พบประวัติการเปลี่ยนแปลง',
                            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textHint),
                          ),
                        )
                      : ListView.separated(
                          shrinkWrap: true,
                          itemCount: sortedLogs.length,
                          separatorBuilder: (context, index) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final log = sortedLogs[index];
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                              child: Row(
                                children: [
                                  _buildDataCell('#${log.sequence}', flex: 1, isBold: true),
                                  _buildDataCell(_formatDate(log.timestamp), flex: 2),
                                  _buildDataCell('${log.oldValue} -> ${log.newValue}', flex: 3),
                                  _buildDataCell(log.editorName ?? 'Unknown', flex: 2),
                                ],
                              ),
                            );
                          },
                        ),
                ),
                
                const SizedBox(height: 24),

                // Close Button
                Container(
                  width: MediaQuery.of(context).size.width * 0.5,
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
              ],
            ),
          ),
        ),
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
