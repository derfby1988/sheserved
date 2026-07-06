import 'package:flutter/material.dart';
import 'payroll_formula_data.dart';

class PayrollFormulaViewerSheet extends StatelessWidget {
  const PayrollFormulaViewerSheet({super.key});

  static void show(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width > 600;
    if (isWide) {
      showDialog(
        context: context,
        builder: (_) => Dialog(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600, maxHeight: 700),
            child: const PayrollFormulaViewerSheet(),
          ),
        ),
      );
    } else {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (_) => const PayrollFormulaViewerSheet(),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: theme.dividerColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Row(
            children: [
              const Icon(Icons.calculate, size: 24),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'สูตรคำนวณ Payroll',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const Divider(height: 16),
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SectionHeader(title: 'รายได้ (Earnings)', color: Colors.green),
                  ...PayrollFormulaData.earnings.map((e) => _FormulaTile(item: e)),
                  const SizedBox(height: 12),
                  _SectionHeader(title: 'การหัก (Deductions)', color: Colors.red),
                  ...PayrollFormulaData.deductions.map((e) => _FormulaTile(item: e)),
                  const SizedBox(height: 12),
                  _SectionHeader(title: 'ส่วนนายจ้าง (Employer Cost)', color: Colors.blue),
                  ...PayrollFormulaData.employerCosts.map((e) => _FormulaTile(item: e)),
                  const SizedBox(height: 16),
                  _SectionHeader(title: 'สรุป (Summary)', color: theme.primaryColor),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.cardColor,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: theme.dividerColor),
                    ),
                    child: Text(
                      PayrollFormulaData.summaryExample,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 13,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final Color color;
  const _SectionHeader({required this.title, required this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Container(width: 4, height: 18, color: color),
          const SizedBox(width: 8),
          Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 15,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _FormulaTile extends StatelessWidget {
  final PayrollFormulaItem item;
  const _FormulaTile({required this.item});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final icon = item.isEarning ? '💰' : '➖';
    return ExpansionTile(
      tilePadding: const EdgeInsets.symmetric(horizontal: 0),
      title: Text('$icon ${item.title}', style: const TextStyle(fontSize: 14)),
      subtitle: Text(
        'สูตร: ${item.formula}',
        style: TextStyle(
          fontSize: 12,
          color: theme.textTheme.bodySmall?.color,
          fontFamily: 'monospace',
        ),
      ),
      children: [
        if (item.condition != null)
          _DetailRow(label: 'เงื่อนไข', value: item.condition!),
        if (item.example != null)
          _DetailRow(label: 'ตัวอย่าง', value: item.example!),
        if (item.details != null)
          ...item.details!.map((d) => Padding(
                padding: const EdgeInsets.only(left: 16, bottom: 2),
                child: Text(
                  d,
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.textTheme.bodySmall?.color,
                    fontFamily: 'monospace',
                  ),
                ),
              )),
        const SizedBox(height: 4),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: 16, bottom: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$label: ',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: theme.textTheme.bodySmall?.color,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 12,
                color: theme.textTheme.bodySmall?.color,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
