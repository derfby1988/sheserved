import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/employee_tax_allowance.dart';
import '../providers/phase_three_provider.dart';
import '../widgets/glass_card.dart';

class TaxAllowancePage extends ConsumerStatefulWidget {
  final String professionId;
  final String employeeId;
  final String employeeName;

  const TaxAllowancePage({
    super.key,
    required this.professionId,
    required this.employeeId,
    required this.employeeName,
  });

  @override
  ConsumerState<TaxAllowancePage> createState() => _TaxAllowancePageState();
}

class _TaxAllowancePageState extends ConsumerState<TaxAllowancePage> {
  int _selectedYear = DateTime.now().year;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref
          .read(phaseThreeProvider.notifier)
          .loadTaxAllowances(widget.employeeId, year: _selectedYear);
    });
  }

  Future<void> _addAllowance() async {
    final amountCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    String type = 'personal';

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('เพิ่มค่าลดหย่อนภาษี'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: type,
                  decoration: const InputDecoration(labelText: 'ประเภท'),
                  items: const [
                    DropdownMenuItem(value: 'personal', child: Text('ค่าลดหย่อนส่วนบุคคล')),
                    DropdownMenuItem(value: 'spouse', child: Text('คู่สมรส')),
                    DropdownMenuItem(value: 'child', child: Text('บุตร')),
                    DropdownMenuItem(value: 'parent', child: Text('บิดามารดา')),
                    DropdownMenuItem(value: 'insurance', child: Text('ประกันชีวิต')),
                    DropdownMenuItem(value: 'donation', child: Text('เงินบริจาค')),
                    DropdownMenuItem(value: 'housing', child: Text('ดอกเบี้ยเงินกู้บ้าน')),
                    DropdownMenuItem(value: 'education', child: Text('ค่าเล่าเรียน')),
                    DropdownMenuItem(value: 'disability', child: Text('ค่าลดหย่อนผู้พิการ')),
                    DropdownMenuItem(value: 'other', child: Text('อื่นๆ')),
                  ],
                  onChanged: (v) => setState(() => type = v ?? 'personal'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: amountCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'จำนวนเงิน (THB)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: descCtrl,
                  decoration: const InputDecoration(
                    labelText: 'หมายเหตุ (ไม่บังคับ)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('ยกเลิก')),
            ElevatedButton(
              onPressed: () async {
                final amount = double.tryParse(amountCtrl.text);
                if (amount == null || amount <= 0) return;
                await ref.read(phaseThreeProvider.notifier).createTaxAllowance({
                  'profession_id': widget.professionId,
                  'employee_id': widget.employeeId,
                  'allowance_type': type,
                  'amount': amount,
                  'description': descCtrl.text.isEmpty ? null : descCtrl.text,
                  'effective_year': _selectedYear,
                });
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('บันทึก'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteAllowance(EmployeeTaxAllowance allowance) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ยืนยันการลบ'),
        content: Text('ลบ "${allowance.typeLabel}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('ยกเลิก')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('ลบ'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(phaseThreeProvider.notifier).deleteTaxAllowance(allowance.id);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(phaseThreeProvider);
    final allowances = state.taxAllowances;
    final totalAllowance = allowances.fold(0.0, (s, a) => s + a.amount);
    final personalAllowance = 60000.0;
    final totalDeduction = personalAllowance + totalAllowance;

    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.employeeName} - ค่าลดหย่อนภาษี'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Text('ปี: ', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(width: 8),
                DropdownButton<int>(
                  value: _selectedYear,
                  items: List.generate(5, (i) => DateTime.now().year - 2 + i)
                      .map((y) => DropdownMenuItem(value: y, child: Text('${y + 543}')))
                      .toList(),
                  onChanged: (y) {
                    if (y == null) return;
                    setState(() => _selectedYear = y);
                    ref.read(phaseThreeProvider.notifier).loadTaxAllowances(widget.employeeId, year: y);
                  },
                ),
              ],
            ),
          ),
          GlassCard(
            section: GlassSection.card,
            borderRadius: 12,
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                _SummaryRow(label: 'ค่าลดหย่อนส่วนบุคคล (ค่าเริ่มต้น)', amount: personalAllowance),
                _SummaryRow(label: 'ค่าลดหย่อนเพิ่ม', amount: totalAllowance, color: Colors.green),
                const Divider(height: 16),
                _SummaryRow(
                  label: 'รวมค่าลดหย่อนทั้งหมด',
                  amount: totalDeduction,
                  isBold: true,
                  color: Colors.blue,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: state.isLoading && allowances.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : allowances.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.receipt_long, size: 48, color: Colors.grey),
                            const SizedBox(height: 8),
                            const Text('ยังไม่มีค่าลดหย่อนเพิ่ม',
                                style: TextStyle(color: Colors.grey)),
                            const SizedBox(height: 16),
                            ElevatedButton.icon(
                              onPressed: _addAllowance,
                              icon: const Icon(Icons.add),
                              label: const Text('เพิ่มค่าลดหย่อน'),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: allowances.length,
                        itemBuilder: (context, index) {
                          final a = allowances[index];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: GlassCard(
                              section: GlassSection.card,
                              borderRadius: 10,
                              padding: const EdgeInsets.all(12),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(a.typeLabel,
                                            style: const TextStyle(
                                                fontWeight: FontWeight.w600, fontSize: 14)),
                                        if (a.description != null)
                                          Text(a.description!,
                                              style: const TextStyle(
                                                  fontSize: 12, color: Colors.grey)),
                                      ],
                                    ),
                                  ),
                                  Text(
                                    '฿${a.amount.toStringAsFixed(0)}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                      color: Colors.green,
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline,
                                        color: Colors.red, size: 20),
                                    onPressed: () => _deleteAllowance(a),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addAllowance,
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final double amount;
  final bool isBold;
  final Color color;

  const _SummaryRow({
    required this.label,
    required this.amount,
    this.isBold = false,
    this.color = Colors.black87,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(
                fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
              )),
          Text(
            '฿${amount.toStringAsFixed(0)}',
            style: TextStyle(
              fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
