import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:csv/csv.dart';

import 'package:sheserved/core/constants/app_colors.dart';
import 'package:sheserved/core/constants/app_text_styles.dart';
import 'package:sheserved/services/service_locator.dart';
import 'package:sheserved/features/donation/data/repositories/fee_repository.dart';
import 'package:sheserved/features/donation/data/repositories/donation_repository.dart';
import 'package:sheserved/features/donation/models/fee_models.dart';

class DonationReportPanel extends StatefulWidget {
  const DonationReportPanel({super.key});

  @override
  State<DonationReportPanel> createState() => _DonationReportPanelState();
}

class _DonationReportPanelState extends State<DonationReportPanel> {
  late FeeRepository _feeRepo;
  late DonationRepository _donationRepo;

  bool _isLoading = true;
  List<DisbursementLog> _disbursements = [];
  List<Map<String, dynamic>> _contributions = [];

  @override
  void initState() {
    super.initState();
    _feeRepo = ServiceLocator.instance.feeRepository;
    _donationRepo = ServiceLocator.instance.donationRepository;
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final disbursements = await _feeRepo.getAllDisbursementLogs(limit: 100);
      final contributions = await _donationRepo.getContributions();

      if (mounted) {
        setState(() {
          _disbursements = disbursements;
          _contributions = contributions;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('เกิดข้อผิดพลาดในการโหลดข้อมูล: $e')));
      }
    }
  }

  Future<void> _exportDisbursementsCsv() async {
    try {
      final List<List<dynamic>> rows = [];
      // Header
      rows.add([
        'ID',
        'Request ID',
        'วันที่จ่ายเงิน',
        'ผู้ทำรายการ',
        'บัญชีปลายทาง',
        'อ้างอิงการโอน',
        'ยอดรวม (Gross)',
        'หักค่าธรรมเนียมรวม',
        'ยอดสุทธิ (Net)',
        'รายละเอียดค่าธรรมเนียม'
      ]);

      for (var log in _disbursements) {
        final feeDetails = log.feeBreakdown.map((e) => '${e.name}: ${e.deducted}').join(', ');
        rows.add([
          log.id,
          log.requestId,
          log.disbursedAt.toIso8601String(),
          log.disbursedBy,
          log.recipientAccount ?? '-',
          log.transferRef ?? '-',
          log.grossAmount,
          log.totalFees,
          log.netAmount,
          feeDetails,
        ]);
      }

      String csvData = const ListToCsvConverter().convert(rows);
      await _saveCsvAndNotify(csvData, 'disbursements_report.csv');
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _exportContributionsCsv() async {
    try {
      final List<List<dynamic>> rows = [];
      rows.add(['ID', 'วันที่บริจาค', 'User', 'คำร้อง', 'จำนวนเงิน']);

      for (var item in _contributions) {
        final user = item['user'] as Map?;
        final req = item['request'] as Map?;
        rows.add([
          item['id'] ?? '',
          item['created_at']?.toString() ?? '',
          user?['username'] ?? 'ไม่ระบุชื่อ',
          req?['title'] ?? 'ไม่ทราบรายการ',
          item['amount']?.toString() ?? '0',
        ]);
      }

      String csvData = const ListToCsvConverter().convert(rows);
      await _saveCsvAndNotify(csvData, 'contributions_report.csv');
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _saveCsvAndNotify(String csvData, String fileName) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final File file = File('${directory.path}/$fileName');
      await file.writeAsString(csvData);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('ดาวน์โหลดสำเร็จ! บันทึกไว้ที่: ${file.path}'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 4),
          action: SnackBarAction(
            label: 'คัดลอก Path',
            textColor: Colors.white,
            onPressed: () {
              Clipboard.setData(ClipboardData(text: file.path));
            },
          ),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('บันทึกไฟล์ล้มเหลว: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('รายงานประวัติทางการเงิน / บัญชี', style: AppTextStyles.heading2.copyWith(color: AppColors.primary)),
              IconButton(onPressed: _loadData, icon: const Icon(Icons.refresh, color: AppColors.primary)),
            ],
          ),
          const Text('สนับสนุนการดาวน์โหลดรายงานสรุปการรับเงินและจ่ายเงิน (Escrow & Disbursements) ออกเป็นไฟล์ CSV', style: TextStyle(color: Colors.grey, fontSize: 13)),
          const SizedBox(height: 24),

          // ส่วน Disbursement
          _buildReportSection(
            title: 'การจ่ายเงิน / ปล่อย Escrow (Disbursements)',
            icon: Icons.outbond,
            color: Colors.orange,
            itemCount: _disbursements.length,
            onExport: _exportDisbursementsCsv,
            subtitle: 'บันทึกการส่งมอบยอดบริจาคให้หน่วยงานต่างๆ หลังหักค่าธรรมเนียมแพลตฟอร์ม',
            child: _buildDisbursementsList(),
          ),

          const SizedBox(height: 24),

          // ส่วน Contributions
          _buildReportSection(
            title: 'รับเงินบริจาคเข้าสู่ระบบ (Contributions)',
            icon: Icons.input,
            color: Colors.green,
            itemCount: _contributions.length,
            onExport: _exportContributionsCsv,
            subtitle: 'รายการบริจาคทั้งหมดจาก User เข้าสู่ระบบ',
            child: _buildContributionsList(),
          ),
        ],
      ),
    );
  }

  Widget _buildReportSection({
    required String title,
    required IconData icon,
    required Color color,
    required int itemCount,
    required VoidCallback onExport,
    required String subtitle,
    required Widget child,
  }) {
    return Expanded(
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 4))],
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: AppTextStyles.bodyLarge.copyWith(fontWeight: FontWeight.bold)),
                      Text(subtitle, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                    ],
                  ),
                ),
                Text('$itemCount รายการ', style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(width: 16),
                ElevatedButton.icon(
                  onPressed: onExport,
                  icon: const Icon(Icons.download, size: 16),
                  label: const Text('Export CSV'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }

  Widget _buildDisbursementsList() {
    if (_disbursements.isEmpty) return const Center(child: Text('ไม่มีประวัติการจ่ายเงิน'));
    final fmt = NumberFormat('#,##0.00');

    return ListView.builder(
      itemCount: _disbursements.length,
      itemBuilder: (context, index) {
        final log = _disbursements[index];
        final dt = DateFormat('dd/MM/yyyy HH:mm').format(log.disbursedAt);
        return Card(
          elevation: 0,
          color: Colors.grey.shade50,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: Colors.grey.shade200)),
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            title: Text('Ref: ${log.transferRef ?? log.id.substring(0, 8)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('อนุมัติโดย: ${log.disbursedBy} เมื่อ $dt', style: const TextStyle(fontSize: 12)),
                Text('Gross: ฿${fmt.format(log.grossAmount)} | หัก: ฿${fmt.format(log.totalFees)}', style: const TextStyle(fontSize: 12, color: Colors.red)),
              ],
            ),
            trailing: Text('Net: ฿${fmt.format(log.netAmount)}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green, fontSize: 14)),
          ),
        );
      },
    );
  }

  Widget _buildContributionsList() {
    if (_contributions.isEmpty) return const Center(child: Text('ไม่มีประวัติรับเงิน'));
    final fmt = NumberFormat('#,##0');

    return ListView.builder(
      itemCount: _contributions.length,
      itemBuilder: (context, index) {
        final item = _contributions[index];
        final user = item['user'] as Map?;
        final request = item['request'] as Map?;
        final dt = item['created_at'] != null ? DateFormat('dd/MM/yyyy HH:mm').format(DateTime.parse(item['created_at'])) : '-';

        return Card(
          elevation: 0,
          color: Colors.grey.shade50,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: Colors.grey.shade200)),
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            title: Text('${user?['username'] ?? 'ไม่ระบุชื่อ'}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            subtitle: Text('ให้: ${request?['title'] ?? 'ไม่ทราบรายการ'}\nเมื่อ: $dt', style: const TextStyle(fontSize: 12)),
            isThreeLine: true,
            trailing: Text('+ ฿${fmt.format(item['amount'] ?? 0)}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue, fontSize: 14)),
          ),
        );
      },
    );
  }
}
