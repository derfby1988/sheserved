import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/payroll_item.dart';
import '../providers/phase_three_provider.dart';
import '../widgets/glass_card.dart';
import '../widgets/payroll_formula_viewer_sheet.dart';

class PayrollItemDetailPage extends ConsumerWidget {
  final String payrollRunId;
  final String employeeId;
  final String employeeName;

  const PayrollItemDetailPage({
    super.key,
    required this.payrollRunId,
    required this.employeeId,
    required this.employeeName,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(phaseThreeProvider);
    final items = state.payrollItems
        .where((i) => i.employeeId == employeeId)
        .toList();

    final earnings = items.where((i) => i.isEarning).toList();
    final deductions =
        items.where((i) => !i.isEarning && !i.isEmployerCost).toList();
    final employerCosts = items.where((i) => i.isEmployerCost).toList();

    double totalGross = earnings.fold(0, (s, i) => s + i.amount);
    double totalDed = deductions.fold(0, (s, i) => s + i.amount);
    double totalEmployer = employerCosts.fold(0, (s, i) => s + i.amount);
    double net = totalGross - totalDed;

    return Scaffold(
      appBar: AppBar(
        title: Text('$employeeName - รายละเอียดเงินเดือน'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.calculate),
            tooltip: 'ดูสูตรคำนวณ',
            onPressed: () => PayrollFormulaViewerSheet.show(context),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SectionCard(
            title: 'รายได้ (Earnings)',
            color: Colors.green,
            items: earnings,
            total: totalGross,
            showFormula: true,
            onShowFormula: () => PayrollFormulaViewerSheet.show(context),
          ),
          const SizedBox(height: 12),
          _SectionCard(
            title: 'การหัก (Deductions)',
            color: Colors.red,
            items: deductions,
            total: totalDed,
            showFormula: true,
            onShowFormula: () => PayrollFormulaViewerSheet.show(context),
          ),
          const SizedBox(height: 12),
          if (employerCosts.isNotEmpty) ...[
            _SectionCard(
              title: 'ส่วนนายจ้าง (Employer Cost)',
              color: Colors.blue,
              items: employerCosts,
              total: totalEmployer,
            ),
            const SizedBox(height: 12),
          ],
          _SummaryCard(
            totalGross: totalGross,
            totalDeductions: totalDed,
            net: net,
            employerCost: totalEmployer,
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () => PayrollFormulaViewerSheet.show(context),
            icon: const Icon(Icons.calculate),
            label: const Text('ดูสูตรคำนวณทั้งหมด'),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final Color color;
  final List<PayrollItem> items;
  final double total;
  final bool showFormula;
  final VoidCallback? onShowFormula;

  const _SectionCard({
    required this.title,
    required this.color,
    required this.items,
    required this.total,
    this.showFormula = false,
    this.onShowFormula,
  });

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      section: GlassSection.card,
      borderRadius: 12,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(width: 4, height: 18, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: color,
                  ),
                ),
              ),
              if (showFormula)
                TextButton.icon(
                  onPressed: onShowFormula,
                  icon: const Icon(Icons.calculate, size: 16),
                  label: const Text('สูตร', style: TextStyle(fontSize: 12)),
                ),
            ],
          ),
          const SizedBox(height: 8),
          ...items.map((item) => _ItemRow(item: item)),
          const Divider(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('รวม${title.split('(')[0].trim()}',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              Text(
                '฿${total.toStringAsFixed(2)}',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ItemRow extends StatelessWidget {
  final PayrollItem item;
  const _ItemRow({required this.item});

  @override
  Widget build(BuildContext context) {
    final icon = item.isEmployerCost
        ? '🏢'
        : item.isEarning
            ? '💰'
            : '➖';
    final color = item.isEmployerCost
        ? Colors.blue
        : item.isEarning
            ? Colors.green
            : Colors.red;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('$icon ${item.itemLabel}',
              style: TextStyle(fontSize: 13, color: color.withOpacity(0.9))),
          Text(
            '${item.isEarning ? '+' : ''}฿${item.amount.toStringAsFixed(2)}',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final double totalGross;
  final double totalDeductions;
  final double net;
  final double employerCost;

  const _SummaryCard({
    required this.totalGross,
    required this.totalDeductions,
    required this.net,
    required this.employerCost,
  });

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      section: GlassSection.card,
      borderRadius: 12,
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _SummaryRow(label: 'รายได้รวม (Gross)', amount: totalGross, color: Colors.green),
          _SummaryRow(label: 'การหักรวม', amount: -totalDeductions, color: Colors.red),
          const Divider(height: 20),
          _SummaryRow(
            label: 'เงินสุทธิ (Net Pay)',
            amount: net,
            color: Colors.blue,
            isBold: true,
            fontSize: 18,
          ),
          if (employerCost > 0) ...[
            const SizedBox(height: 12),
            const Divider(height: 16),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'ส่วนนายจ้าง',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.blue),
              ),
            ),
            _SummaryRow(label: 'ต้นทุนรวม (Employer)', amount: totalGross + employerCost, color: Colors.blue),
          ],
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final double amount;
  final Color color;
  final bool isBold;
  final double fontSize;

  const _SummaryRow({
    required this.label,
    required this.amount,
    required this.color,
    this.isBold = false,
    this.fontSize = 14,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: fontSize * 0.85,
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          Text(
            '฿${amount.toStringAsFixed(2)}',
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
