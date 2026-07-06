import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/phase_three_provider.dart';
import 'payroll_formula_viewer_sheet.dart';

class PayrollRunCreateDialog extends ConsumerStatefulWidget {
  final String professionId;

  const PayrollRunCreateDialog({
    super.key,
    required this.professionId,
  });

  static void show(BuildContext context, String professionId) {
    showDialog(
      context: context,
      builder: (_) => PayrollRunCreateDialog(professionId: professionId),
    );
  }

  @override
  ConsumerState<PayrollRunCreateDialog> createState() =>
      _PayrollRunCreateDialogState();
}

class _PayrollRunCreateDialogState
    extends ConsumerState<PayrollRunCreateDialog> {
  final _nameController = TextEditingController();
  DateTime _periodStart = DateTime.now().subtract(const Duration(days: 30));
  DateTime _periodEnd = DateTime.now();
  bool _calcTax = true;
  bool _calcPF = true;
  bool _calcOTByDay = true;
  bool _includeBonus = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(phaseThreeProvider);

    return AlertDialog(
      title: Row(
        children: [
          const Text('สร้าง Payroll Run ใหม่'),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.calculate, size: 20),
            tooltip: 'ดูสูตรคำนวณ',
            onPressed: () => PayrollFormulaViewerSheet.show(context),
          ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'ชื่อรอบ (เช่น เงินเดือน กรกฎาคม 2026)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              ListTile(
                title: Text(
                    'วันที่เริ่มต้น: ${_periodStart.day}/${_periodStart.month}/${_periodStart.year}'),
                trailing: const Icon(Icons.calendar_today),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _periodStart,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2100),
                  );
                  if (picked != null) setState(() => _periodStart = picked);
                },
              ),
              ListTile(
                title: Text(
                    'วันที่สิ้นสุด: ${_periodEnd.day}/${_periodEnd.month}/${_periodEnd.year}'),
                trailing: const Icon(Icons.calendar_today),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _periodEnd,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2100),
                  );
                  if (picked != null) setState(() => _periodEnd = picked);
                },
              ),
              const Divider(),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('ตัวเลือกการคำนวณ',
                    style: TextStyle(fontWeight: FontWeight.w600)),
              ),
              CheckboxListTile(
                dense: true,
                title: const Text('คำนวณภาษี (ถ้าเปิดใน Settings)'),
                value: _calcTax,
                onChanged: (v) => setState(() => _calcTax = v ?? true),
              ),
              CheckboxListTile(
                dense: true,
                title: const Text('คำนวณกองทุนสำรองเลี้ยงชีพ'),
                value: _calcPF,
                onChanged: (v) => setState(() => _calcPF = v ?? true),
              ),
              CheckboxListTile(
                dense: true,
                title: const Text('คำนวณ OT แยกตามวัน'),
                value: _calcOTByDay,
                onChanged: (v) => setState(() => _calcOTByDay = v ?? true),
              ),
              CheckboxListTile(
                dense: true,
                title: const Text('รวม bonus/allowance จาก benefit_policies'),
                value: _includeBonus,
                onChanged: (v) => setState(() => _includeBonus = v ?? false),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('ยกเลิก'),
        ),
        ElevatedButton(
          onPressed: state.isSaving
              ? null
              : () async {
                  if (_nameController.text.isEmpty) return;
                  final run = await ref
                      .read(phaseThreeProvider.notifier)
                      .createPayrollRun({
                    'profession_id': widget.professionId,
                    'run_name': _nameController.text,
                    'period_start':
                        _periodStart.toIso8601String().split('T')[0],
                    'period_end': _periodEnd.toIso8601String().split('T')[0],
                    'status': 'draft',
                  });
                  if (context.mounted) {
                    Navigator.pop(context, run);
                  }
                },
          child: state.isSaving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('สร้าง'),
        ),
      ],
    );
  }
}
