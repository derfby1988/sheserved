import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/dashboard_theme.dart';
import '../providers/phase_three_provider.dart';
import '../widgets/glass_card.dart';

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
                        return _EmployeeCard(employee: emp);
                      },
                    ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddEmployeeDialog(context),
        child: const Icon(Icons.add),
      ),
    );
  }

  void _showAddEmployeeDialog(BuildContext context) {
    final codeController = TextEditingController();
    final nameController = TextEditingController();
    final deptController = TextEditingController();
    final titleController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('เพิ่มพนักงาน'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: codeController, decoration: const InputDecoration(labelText: 'รหัสพนักงาน')),
              TextField(controller: nameController, decoration: const InputDecoration(labelText: 'ชื่อ-นามสกุล')),
              TextField(controller: deptController, decoration: const InputDecoration(labelText: 'แผนก')),
              TextField(controller: titleController, decoration: const InputDecoration(labelText: 'ตำแหน่ง')),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('ยกเลิก')),
          ElevatedButton(
            onPressed: () async {
              final notifier = ref.read(phaseThreeProvider.notifier);
              await notifier.createEmployee({
                'profession_id': widget.professionId,
                'employee_code': codeController.text,
                'full_name': nameController.text,
                'department': deptController.text,
                'job_title': titleController.text,
              });
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('บันทึก'),
          ),
        ],
      ),
    );
  }
}

class _EmployeeCard extends StatelessWidget {
  final dynamic employee;

  const _EmployeeCard({required this.employee});

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
                ],
              ),
            ),
            Chip(
              label: Text(employee.isActive ? 'Active' : 'Inactive'),
              backgroundColor: employee.isActive ? Colors.green.withOpacity(0.2) : Colors.red.withOpacity(0.2),
            ),
          ],
        ),
      ),
    );
  }
}
