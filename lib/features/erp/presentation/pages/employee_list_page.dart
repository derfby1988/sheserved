import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/dashboard_theme.dart';
import '../../data/models/employee.dart';
import '../providers/phase_three_provider.dart';
import '../widgets/glass_card.dart';
import 'tax_allowance_page.dart';

class EmployeeListPage extends ConsumerStatefulWidget {
  final String professionId;

  const EmployeeListPage({
    Key? key,
    required this.professionId,
  }) : super(key: key);

  @override
  ConsumerState<EmployeeListPage> createState() => _EmployeeListPageState();
}

class _EmployeeListPageState extends ConsumerState<EmployeeListPage> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(phaseThreeProvider.notifier).loadEmployees(widget.professionId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(phaseThreeProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('พนักงาน / Employees'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: state.isLoading
          ? const Center(child: CircularProgressIndicator())
          : state.errorMessage != null
              ? Center(child: Text('Error: ${state.errorMessage}'))
              : state.employees.isEmpty
                  ? const Center(
                      child: Text(
                        'ยังไม่มีข้อมูลพนักงาน',
                        style: TextStyle(color: Colors.grey),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: state.employees.length,
                      itemBuilder: (context, index) {
                        final emp = state.employees[index];
                        return _EmployeeCard(
                          employee: emp,
                          professionId: widget.professionId,
                          onEdit: () => _showEditEmployeeDialog(context, emp),
                          onTaxAllowance: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => TaxAllowancePage(
                                  professionId: widget.professionId,
                                  employeeId: emp.id,
                                  employeeName: emp.fullName,
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddEmployeeDialog(context),
        child: const Icon(Icons.add),
      ),
    );
  }

  void _showAddEmployeeDialog(BuildContext context) {
    _showEmployeeDialog(context);
  }

  void _showEditEmployeeDialog(BuildContext context, Employee employee) {
    _showEmployeeDialog(context, employee: employee);
  }

  void _showEmployeeDialog(BuildContext context, {Employee? employee}) {
    final isEdit = employee != null;
    final codeController = TextEditingController(text: employee?.employeeCode ?? '');
    final nameController = TextEditingController(text: employee?.fullName ?? '');
    final deptController = TextEditingController(text: employee?.department ?? '');
    final titleController = TextEditingController(text: employee?.jobTitle ?? '');
    final salaryController = TextEditingController(
      text: employee?.salary != null ? employee!.salary.toString() : '',
    );
    final baseSalaryController = TextEditingController(
      text: employee?.baseSalary != null ? employee!.baseSalary.toString() : '',
    );
    final commissionController = TextEditingController(
      text: employee?.commissionRate != null ? employee!.commissionRate.toString() : '',
    );
    final pfRateController = TextEditingController(
      text: employee?.providentFundRate != null ? employee!.providentFundRate.toString() : '0.03',
    );
    final taxExpensesController = TextEditingController(
      text: employee?.taxDeductibleExpenses != null ? employee!.taxDeductibleExpenses.toString() : '0',
    );
    final personalAllowanceController = TextEditingController(
      text: employee?.personalAllowance != null ? employee!.personalAllowance.toString() : '60000',
    );
    final bankNameController = TextEditingController(text: employee?.bankName ?? '');
    final bankAccController = TextEditingController(text: employee?.bankAccountNumber ?? '');
    bool isActive = employee?.isActive ?? true;
    String paymentMethod = employee?.paymentMethod ?? 'bank_transfer';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(isEdit ? 'แก้ไขพนักงาน' : 'เพิ่มพนักงาน'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: codeController, decoration: const InputDecoration(labelText: 'รหัสพนักงาน')),
                TextField(controller: nameController, decoration: const InputDecoration(labelText: 'ชื่อ-นามสกุล')),
                TextField(controller: deptController, decoration: const InputDecoration(labelText: 'แผนก')),
                TextField(controller: titleController, decoration: const InputDecoration(labelText: 'ตำแหน่ง')),
                TextField(
                  controller: salaryController,
                  decoration: const InputDecoration(labelText: 'เงินเดือน (เดิม)'),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                ),
                TextField(
                  controller: baseSalaryController,
                  decoration: const InputDecoration(labelText: 'เงินเดือนพื้นฐาน (Base Salary) *'),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                ),
                TextField(
                  controller: commissionController,
                  decoration: const InputDecoration(labelText: 'ค่าคอมมิชชั่น (%)'),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                ),
                const Divider(),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('การหักภาษี/กองทุน',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                ),
                TextField(
                  controller: pfRateController,
                  decoration: const InputDecoration(labelText: 'อัตรากองทุนสำรองเลี้ยงชีพ (%)'),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                ),
                TextField(
                  controller: personalAllowanceController,
                  decoration: const InputDecoration(labelText: 'ค่าลดหย่อนส่วนบุคคล (THB)'),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                ),
                TextField(
                  controller: taxExpensesController,
                  decoration: const InputDecoration(labelText: 'ค่าใช้จ่ายหักภาษีเพิ่ม (THB)'),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                ),
                const Divider(),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('การจ่ายเงิน',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                ),
                DropdownButtonFormField<String>(
                  value: paymentMethod,
                  decoration: const InputDecoration(labelText: 'วิธีจ่าย'),
                  items: const [
                    DropdownMenuItem(value: 'bank_transfer', child: Text('โอนผ่านธนาคาร')),
                    DropdownMenuItem(value: 'cash', child: Text('เงินสด')),
                    DropdownMenuItem(value: 'check', child: Text('เช็ค')),
                  ],
                  onChanged: (v) => setState(() => paymentMethod = v ?? 'bank_transfer'),
                ),
                if (paymentMethod == 'bank_transfer') ...[
                  TextField(
                    controller: bankNameController,
                    decoration: const InputDecoration(labelText: 'ชื่อธนาคาร'),
                  ),
                  TextField(
                    controller: bankAccController,
                    decoration: const InputDecoration(labelText: 'เลขบัญชี'),
                  ),
                ],
                if (isEdit)
                  SwitchListTile(
                    title: const Text('Active'),
                    value: isActive,
                    onChanged: (v) => setState(() => isActive = v),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('ยกเลิก')),
            ElevatedButton(
              onPressed: () async {
                final data = {
                  'profession_id': widget.professionId,
                  'employee_code': codeController.text.trim(),
                  'full_name': nameController.text.trim(),
                  'department': deptController.text.trim().isEmpty ? null : deptController.text.trim(),
                  'job_title': titleController.text.trim().isEmpty ? null : titleController.text.trim(),
                  'salary': double.tryParse(salaryController.text.trim()) ?? 0,
                  'base_salary': double.tryParse(baseSalaryController.text.trim()) ?? 0,
                  'commission_rate': double.tryParse(commissionController.text.trim()) ?? 0,
                  'provident_fund_rate': double.tryParse(pfRateController.text.trim()) ?? 0.03,
                  'personal_allowance': double.tryParse(personalAllowanceController.text.trim()) ?? 60000,
                  'tax_deductible_expenses': double.tryParse(taxExpensesController.text.trim()) ?? 0,
                  'payment_method': paymentMethod,
                  'bank_name': bankNameController.text.trim().isEmpty ? null : bankNameController.text.trim(),
                  'bank_account_number': bankAccController.text.trim().isEmpty ? null : bankAccController.text.trim(),
                  if (isEdit) 'is_active': isActive,
                };
                final notifier = ref.read(phaseThreeProvider.notifier);
                if (isEdit) {
                  await notifier.updateEmployee(employee.id, data);
                } else {
                  await notifier.createEmployee(data);
                }
                if (context.mounted) Navigator.pop(context);
              },
              child: const Text('บันทึก'),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmployeeCard extends StatelessWidget {
  final Employee employee;
  final String professionId;
  final VoidCallback onEdit;
  final VoidCallback onTaxAllowance;

  const _EmployeeCard({
    required this.employee,
    required this.professionId,
    required this.onEdit,
    required this.onTaxAllowance,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassCard(
        section: GlassSection.card,
        borderRadius: 12,
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            CircleAvatar(
              child: Text(employee.fullName.substring(0, 1)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(employee.fullName, style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text('${employee.employeeCode} | ${employee.department ?? '-'}'),
                  if (employee.jobTitle != null)
                    Text(employee.jobTitle!, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  if (employee.baseSalary > 0)
                    Text('฿${employee.baseSalary.toStringAsFixed(0)}/เดือน',
                        style: const TextStyle(fontSize: 12, color: Colors.green)),
                ],
              ),
            ),
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'edit') onEdit();
                if (v == 'tax') onTaxAllowance();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'edit', child: Text('แก้ไข')),
                PopupMenuItem(value: 'tax', child: Text('ค่าลดหย่อนภาษี')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
