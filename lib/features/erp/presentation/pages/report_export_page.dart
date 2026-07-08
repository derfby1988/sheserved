import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/dashboard_theme.dart';
import '../providers/phase_five_provider.dart';
import '../widgets/glass_card.dart';
import '../../../../shared/widgets/thai_buddhist_date_picker.dart';

class ReportExportPage extends ConsumerStatefulWidget {
  final String professionId;

  const ReportExportPage({super.key, required this.professionId});

  @override
  ConsumerState<ReportExportPage> createState() => _ReportExportPageState();
}

class _ReportExportPageState extends ConsumerState<ReportExportPage> {
  String _selectedReportType = 'sales_summary';
  DateTime _startDate = DateTime.now().subtract(const Duration(days: 30));
  DateTime _endDate = DateTime.now();

  final List<Map<String, String>> _reportTypes = [
    {'value': 'sales_summary', 'label': 'สรุปยอดขาย'},
    {'value': 'inventory_status', 'label': 'สถานะคลังสินค้า'},
    {'value': 'employee_performance', 'label': 'ประสิทธิภาพพนักงาน'},
    {'value': 'customer_activity', 'label': 'กิจกรรมลูกค้า'},
    {'value': 'financial_gl', 'label': 'บัญชี GL'},
  ];

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(phaseFiveProvider.notifier).loadScheduledReports(widget.professionId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(phaseFiveProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('รายงาน / Reports'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Generate Report Section
          GlassCard(
            section: GlassSection.card,
            borderRadius: 12,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('สร้างรายงาน', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _selectedReportType,
                  decoration: const InputDecoration(labelText: 'ประเภทรายงาน'),
                  items: _reportTypes.map((type) {
                    return DropdownMenuItem(value: type['value'], child: Text(type['label']!));
                  }).toList(),
                  onChanged: (v) => setState(() => _selectedReportType = v!),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: ThaiBuddhistDatePickerField(
                        value: _startDate,
                        label: 'จากวันที่',
                        hint: 'เลือกวันที่เริ่มต้น',
                        onDateSelected: (date) => setState(() => _startDate = date),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ThaiBuddhistDatePickerField(
                        value: _endDate,
                        label: 'ถึงวันที่',
                        hint: 'เลือกวันที่สิ้นสุด',
                        onDateSelected: (date) => setState(() => _endDate = date),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: state.isLoading
                        ? null
                        : () {
                            ref.read(phaseFiveProvider.notifier).generateReport(
                              widget.professionId,
                              _selectedReportType,
                              _startDate,
                              _endDate,
                            );
                          },
                    child: state.isLoading
                        ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('สร้างรายงาน'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Report Result
          if (state.reportPayload != null)
            GlassCard(
              section: GlassSection.card,
              borderRadius: 12,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('ผลลัพธ์', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Text(
                    const JsonEncoder.withIndent('  ').convert(state.reportPayload),
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 16),
          // Scheduled Reports
          if (state.scheduledReports.isNotEmpty) ...[
            const Text('รายงานตั้งเวลา', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
            const SizedBox(height: 8),
            ...state.scheduledReports.map((report) => _ScheduledReportCard(report: report)),
          ],
        ],
      ),
    );
  }
}


class _ScheduledReportCard extends StatelessWidget {
  final dynamic report;

  const _ScheduledReportCard({required this.report});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GlassCard(
        section: GlassSection.card,
        borderRadius: 8,
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            Icon(Icons.schedule, color: report.isActive ? Colors.green : Colors.grey, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(report.reportName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                  Text('${report.reportType} · ${report.frequency} · ${report.format.toUpperCase()}',
                      style: const TextStyle(fontSize: 11, color: Colors.grey)),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: (report.lastRunStatus == 'success' ? Colors.green : Colors.orange).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                report.lastRunStatus ?? 'never',
                style: TextStyle(
                  fontSize: 10,
                  color: report.lastRunStatus == 'success' ? Colors.green : Colors.orange,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
