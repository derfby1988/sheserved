import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/hr_settings.dart';
import '../providers/phase_three_provider.dart';
import '../widgets/glass_card.dart';
import '../widgets/payroll_formula_viewer_sheet.dart';
import 'thai_holidays_page.dart';

class HrSettingsPage extends ConsumerStatefulWidget {
  final String professionId;

  const HrSettingsPage({
    super.key,
    required this.professionId,
  });

  @override
  ConsumerState<HrSettingsPage> createState() => _HrSettingsPageState();
}

class _HrSettingsPageState extends ConsumerState<HrSettingsPage> {
  late TextEditingController _otWeekdayCtrl;
  late TextEditingController _otWeekendCtrl;
  late TextEditingController _otHolidayCtrl;
  late TextEditingController _ssRateCtrl;
  late TextEditingController _diligenceCtrl;
  late TextEditingController _pfEmpRateCtrl;
  late TextEditingController _pfEmpRateCtrl2;
  late TextEditingController _pfWageCapCtrl;
  late TextEditingController _latePerMinCtrl;
  late TextEditingController _absentPerDayCtrl;
  late TextEditingController _workHoursCtrl;
  bool _taxEnabled = false;
  bool _flexibleHours = false;
  String _attendanceMode = 'manual';
  bool _settingsSynced = false;

  @override
  void initState() {
    super.initState();
    _otWeekdayCtrl = TextEditingController(text: '1.50');
    _otWeekendCtrl = TextEditingController(text: '2.00');
    _otHolidayCtrl = TextEditingController(text: '3.00');
    _ssRateCtrl = TextEditingController(text: '0.0500');
    _diligenceCtrl = TextEditingController(text: '0');
    _pfEmpRateCtrl = TextEditingController(text: '0.0300');
    _pfEmpRateCtrl2 = TextEditingController(text: '0.0300');
    _pfWageCapCtrl = TextEditingController(text: '100000');
    _latePerMinCtrl = TextEditingController(text: '0');
    _absentPerDayCtrl = TextEditingController(text: '0');
    _workHoursCtrl = TextEditingController(text: '8.00');

    Future.microtask(() {
      ref.read(phaseThreeProvider.notifier).loadHrSettings(widget.professionId);
    });
  }

  @override
  void dispose() {
    _otWeekdayCtrl.dispose();
    _otWeekendCtrl.dispose();
    _otHolidayCtrl.dispose();
    _ssRateCtrl.dispose();
    _diligenceCtrl.dispose();
    _pfEmpRateCtrl.dispose();
    _pfEmpRateCtrl2.dispose();
    _pfWageCapCtrl.dispose();
    _latePerMinCtrl.dispose();
    _absentPerDayCtrl.dispose();
    _workHoursCtrl.dispose();
    super.dispose();
  }

  void _syncFromSettings(HrSettings? s) {
    if (s == null || _settingsSynced) return;
    _settingsSynced = true;
    _otWeekdayCtrl.text = s.otMultiplierWeekday.toString();
    _otWeekendCtrl.text = s.otMultiplierWeekend.toString();
    _otHolidayCtrl.text = s.otMultiplierHoliday.toString();
    _ssRateCtrl.text = s.socialSecurityRate.toString();
    _diligenceCtrl.text = s.diligenceAllowanceAmount.toString();
    _pfEmpRateCtrl.text = s.providentFundEmployeeRate.toString();
    _pfEmpRateCtrl2.text = s.providentFundEmployerRate.toString();
    _pfWageCapCtrl.text = s.providentFundWageCap.toString();
    _latePerMinCtrl.text = s.lateDeductionPerMinute.toString();
    _absentPerDayCtrl.text = s.absentDeductionPerDay.toString();
    _workHoursCtrl.text = s.defaultWorkHoursPerDay.toString();
    _taxEnabled = s.taxCalculationEnabled;
    _flexibleHours = s.allowFlexibleHours;
    _attendanceMode = s.attendanceMode;
  }

  Future<void> _save() async {
    final params = {
      'p_profession_id': widget.professionId,
      'p_attendance_mode': _attendanceMode,
      'p_allow_flexible_hours': _flexibleHours,
      'p_default_work_hours_per_day': double.tryParse(_workHoursCtrl.text) ?? 8.0,
      'p_ot_multiplier_weekday': double.tryParse(_otWeekdayCtrl.text) ?? 1.5,
      'p_ot_multiplier_weekend': double.tryParse(_otWeekendCtrl.text) ?? 2.0,
      'p_ot_multiplier_holiday': double.tryParse(_otHolidayCtrl.text) ?? 3.0,
      'p_social_security_rate': double.tryParse(_ssRateCtrl.text) ?? 0.05,
      'p_diligence_allowance_amount': double.tryParse(_diligenceCtrl.text) ?? 0,
      'p_provident_fund_employee_rate': double.tryParse(_pfEmpRateCtrl.text) ?? 0.03,
      'p_provident_fund_employer_rate': double.tryParse(_pfEmpRateCtrl2.text) ?? 0.03,
      'p_provident_fund_wage_cap': double.tryParse(_pfWageCapCtrl.text) ?? 100000,
      'p_tax_calculation_enabled': _taxEnabled,
      'p_late_deduction_per_minute': double.tryParse(_latePerMinCtrl.text) ?? 0,
      'p_absent_deduction_per_day': double.tryParse(_absentPerDayCtrl.text) ?? 0,
    };

    final success =
        await ref.read(phaseThreeProvider.notifier).saveHrSettings(params);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(success ? 'บันทึกสำเร็จ' : 'บันทึกล้มเหลว')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(phaseThreeProvider);
    _syncFromSettings(state.hrSettings);

    return Scaffold(
      appBar: AppBar(
        title: const Text('ตั้งค่า HR'),
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
          _SettingsSection(
            title: 'การลงเวลา',
            children: [
              DropdownButtonFormField<String>(
                value: _attendanceMode,
                decoration: const InputDecoration(labelText: 'โหมด'),
                items: const [
                  DropdownMenuItem(value: 'manual', child: Text('Manual')),
                  DropdownMenuItem(value: 'device', child: Text('Device')),
                  DropdownMenuItem(value: 'both', child: Text('Both')),
                ],
                onChanged: (v) => setState(() => _attendanceMode = v ?? 'manual'),
              ),
              SwitchListTile(
                title: const Text('Flexible Hours'),
                value: _flexibleHours,
                onChanged: (v) => setState(() => _flexibleHours = v),
              ),
              _NumberField(controller: _workHoursCtrl, label: 'ชั่วโมงทำงาน/วัน'),
            ],
          ),
          const SizedBox(height: 12),
          _SettingsSection(
            title: 'ค่าล่วงเวลา (OT)',
            formulaHint: 'OT = count × hourly_rate × mult',
            children: [
              _NumberField(controller: _otWeekdayCtrl, label: 'OT วันธรรมดา (×)'),
              _NumberField(controller: _otWeekendCtrl, label: 'OT วันหยุด (×)'),
              _NumberField(controller: _otHolidayCtrl, label: 'OT วันหยุดนักขัตฤกษ์ (×)'),
            ],
          ),
          const SizedBox(height: 12),
          _SettingsSection(
            title: 'ประกันสังคม',
            formulaHint: 'MIN(salary × rate, 750)',
            children: [
              _NumberField(controller: _ssRateCtrl, label: 'อัตรา (%)'),
              const SizedBox(height: 4),
              const Text('สูงสุด/เดือน: 750.00 THB (ตามกฎหมาย)',
                  style: TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ),
          const SizedBox(height: 12),
          _SettingsSection(
            title: 'เบี้ยขยัน',
            formulaHint: 'ไม่สาย/ไม่ขาด → ได้เต็ม',
            children: [
              _NumberField(controller: _diligenceCtrl, label: 'จำนวน (THB)'),
            ],
          ),
          const SizedBox(height: 12),
          _SettingsSection(
            title: 'กองทุนสำรองเลี้ยงชีพ',
            formulaHint: 'LEAST(salary, cap) × rate',
            children: [
              _NumberField(controller: _pfEmpRateCtrl, label: 'อัตราพนักงาน (%)'),
              _NumberField(controller: _pfEmpRateCtrl2, label: 'อัตรานายจ้าง (%)'),
              _NumberField(controller: _pfWageCapCtrl, label: 'ฐานสูงสุด (THB)'),
            ],
          ),
          const SizedBox(height: 12),
          _SettingsSection(
            title: 'ภาษีเงินได้',
            formulaHint: 'Progressive PIT (0%-35%) / 12',
            children: [
              SwitchListTile(
                title: const Text('เปิดใช้การคำนวณภาษี'),
                value: _taxEnabled,
                onChanged: (v) async {
                  if (v) {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('ยืนยัน'),
                        content: const Text(
                            'การเปิดการคำนวณภาษีจะมีผลกับ Payroll Run รอบถัดไป ต้องการดำเนินการต่อหรือไม่?'),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: const Text('ยกเลิก')),
                          ElevatedButton(
                              onPressed: () => Navigator.pop(ctx, true),
                              child: const Text('ยืนยัน')),
                        ],
                      ),
                    );
                    if (confirmed != true) return;
                  }
                  setState(() => _taxEnabled = v);
                },
              ),
              ExpansionTile(
                title: const Text('ดูตารางอัตราภาษี', style: TextStyle(fontSize: 14)),
                children: const [
                  _TaxRateTable(),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          _SettingsSection(
            title: 'การหักสาย/ขาด',
            formulaHint: 'late_min × rate + absent × rate',
            children: [
              _NumberField(controller: _latePerMinCtrl, label: 'หักสาย/นาที (THB)'),
              _NumberField(controller: _absentPerDayCtrl, label: 'หักขาด/วัน (THB)'),
            ],
          ),
          const SizedBox(height: 12),
          _SettingsSection(
            title: 'วันหยุดนักขัตฤกษ์',
            children: [
              ListTile(
                leading: const Icon(Icons.calendar_month),
                title: const Text('จัดการวันหยุด'),
                subtitle: Text('${state.thaiHolidays.length} วันหยุดในระบบ'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ThaiHolidaysPage(),
                    ),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: state.isSaving ? null : _save,
            icon: state.isSaving
                ? const SizedBox(
                    width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.save),
            label: const Text('บันทึก'),
          ),
        ],
      ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  final String title;
  final String? formulaHint;
  final List<Widget> children;

  const _SettingsSection({
    required this.title,
    this.formulaHint,
    required this.children,
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
          Text(title,
              style:
                  const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          if (formulaHint != null) ...[
            const SizedBox(height: 4),
            Text('💡 $formulaHint',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          ],
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }
}

class _NumberField extends StatelessWidget {
  final TextEditingController controller;
  final String label;

  const _NumberField({required this.controller, required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: TextField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
      ),
    );
  }
}

class _TaxRateTable extends StatelessWidget {
  const _TaxRateTable();

  @override
  Widget build(BuildContext context) {
    final rates = [
      ('0 - 150,000', '0% (ยกเว้น)'),
      ('150,001 - 300,000', '5%'),
      ('300,001 - 500,000', '10%'),
      ('500,001 - 750,000', '15%'),
      ('750,001 - 1,000,000', '20%'),
      ('1,000,001 - 2,000,000', '25%'),
      ('2,000,001 - 5,000,000', '30%'),
      ('5,000,001 ขึ้นไป', '35%'),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: rates
            .map((r) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(r.$1, style: const TextStyle(fontSize: 13)),
                      Text(r.$2,
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ))
            .toList(),
      ),
    );
  }
}
