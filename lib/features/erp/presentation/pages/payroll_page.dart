import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../data/models/payroll_run.dart';
import '../../data/models/payroll_item.dart';
import '../../data/models/dashboard_theme.dart';
import '../providers/phase_three_provider.dart';
import '../widgets/glass_card.dart';
import '../widgets/payroll_formula_viewer_sheet.dart';
import '../widgets/payroll_run_create_dialog.dart';

class PayrollPage extends ConsumerStatefulWidget {
  final String professionId;

  const PayrollPage({
    Key? key,
    required this.professionId,
  }) : super(key: key);

  @override
  ConsumerState<PayrollPage> createState() => _PayrollPageState();
}

class _PayrollPageState extends ConsumerState<PayrollPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String? _selectedRunId;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    Future.microtask(() {
      ref
          .read(phaseThreeProvider.notifier)
          .loadPayrollRuns(widget.professionId);
      ref
          .read(phaseThreeProvider.notifier)
          .loadHrSettings(widget.professionId);
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(phaseThreeProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('เงินเดือน / Payroll'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.calculate),
            tooltip: 'ดูสูตรคำนวณ',
            onPressed: () => PayrollFormulaViewerSheet.show(context),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'รอบเงินเดือน'),
            Tab(text: 'รายละเอียด'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _PayrollRunListTab(
            professionId: widget.professionId,
            runs: state.payrollRuns,
            isLoading: state.isLoading,
            isSaving: state.isSaving,
            errorMessage: state.errorMessage,
            onCreateRun: () => _showCreateRunDialog(context),
            onRunCalculation: (run) => _runCalculation(run),
            onApprove: (run) => _approveRun(run),
            onViewItems: (run) {
              setState(() => _selectedRunId = run.id);
              ref
                  .read(phaseThreeProvider.notifier)
                  .loadPayrollItems(run.id);
              _tabController.animateTo(1);
            },
          ),
          _PayrollItemsTab(
            items: state.payrollItems,
            isLoading: state.isLoading,
            selectedRunId: _selectedRunId,
          ),
        ],
      ),
    );
  }

  Future<void> _showCreateRunDialog(BuildContext context) async {
    final run = await showDialog<PayrollRun>(
      context: context,
      builder: (_) => PayrollRunCreateDialog(professionId: widget.professionId),
    );
    if (run != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('สร้างรอบ "${run.runName}" สำเร็จ')),
      );
    }
  }

  Future<void> _runCalculation(PayrollRun run) async {
    final success = await ref.read(phaseThreeProvider.notifier).runPayrollCalculation(
      payrollRunId: run.id,
      professionId: widget.professionId,
      periodStart: run.periodStart,
      periodEnd: run.periodEnd,
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? 'คำนวณเงินเดือนสำเร็จ' : 'คำนวณล้มเหลว'),
        ),
      );
    }
  }

  Future<void> _approveRun(PayrollRun run) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ยืนยันการอนุมัติ'),
        content: Text(
          'ยืนยันการอนุมัติ Payroll รอบ "${run.runName}"?\n'
          'หลังอนุมัติจะไม่สามารถแก้ไขได้ และจะสร้างรายการบัญชีอัตโนมัติ',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('ยกเลิก'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('อนุมัติ'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final userId = Supabase.instance.client.auth.currentUser?.id ?? '';
    final success =
        await ref.read(phaseThreeProvider.notifier).approvePayrollRun(
      run.id,
      userId,
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? 'อนุมัติสำเร็จ' : 'อนุมัติล้มเหลว'),
        ),
      );
    }
  }
}

// ========================
// Payroll Run List Tab
// ========================
class _PayrollRunListTab extends StatelessWidget {
  final String professionId;
  final List<PayrollRun> runs;
  final bool isLoading;
  final bool isSaving;
  final String? errorMessage;
  final VoidCallback onCreateRun;
  final void Function(PayrollRun) onRunCalculation;
  final void Function(PayrollRun) onApprove;
  final void Function(PayrollRun) onViewItems;

  const _PayrollRunListTab({
    required this.professionId,
    required this.runs,
    required this.isLoading,
    required this.isSaving,
    required this.errorMessage,
    required this.onCreateRun,
    required this.onRunCalculation,
    required this.onApprove,
    required this.onViewItems,
  });

  Color _statusColor(String status) {
    switch (status) {
      case 'paid':
        return Colors.green;
      case 'approved':
        return Colors.blue;
      case 'pending_approval':
        return Colors.orange;
      case 'calculating':
        return Colors.purple;
      case 'cancelled':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'draft':
        return 'ร่าง';
      case 'calculating':
        return 'กำลังคำนวณ';
      case 'pending_approval':
        return 'รออนุมัติ';
      case 'approved':
        return 'อนุมัติแล้ว';
      case 'paid':
        return 'จ่ายแล้ว';
      case 'cancelled':
        return 'ยกเลิก';
      default:
        return status;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading && runs.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (errorMessage != null && runs.isEmpty) {
      return Center(child: Text('Error: $errorMessage'));
    }

    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: () async {},
          child: runs.isEmpty
              ? ListView(
                  children: const [
                    SizedBox(height: 200),
                    Center(
                      child: Text(
                        'ยังไม่มีรอบเงินเดือน',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                  ],
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: runs.length,
                  itemBuilder: (context, index) {
                    final run = runs[index];
                    return _PayrollRunCard(
                      run: run,
                      statusColor: _statusColor(run.status),
                      statusLabel: _statusLabel(run.status),
                      isSaving: isSaving,
                      onRunCalculation: () => onRunCalculation(run),
                      onApprove: () => onApprove(run),
                      onViewItems: () => onViewItems(run),
                    );
                  },
                ),
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton(
            onPressed: onCreateRun,
            child: const Icon(Icons.add),
          ),
        ),
      ],
    );
  }
}

class _PayrollRunCard extends StatelessWidget {
  final PayrollRun run;
  final Color statusColor;
  final String statusLabel;
  final bool isSaving;
  final VoidCallback onRunCalculation;
  final VoidCallback onApprove;
  final VoidCallback onViewItems;

  const _PayrollRunCard({
    required this.run,
    required this.statusColor,
    required this.statusLabel,
    required this.isSaving,
    required this.onRunCalculation,
    required this.onApprove,
    required this.onViewItems,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassCard(
        section: GlassSection.card,
        borderRadius: 12,
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    run.runName,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 15),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    statusLabel,
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'รอบ: ${run.periodStart.day}/${run.periodStart.month}/${run.periodStart.year} - ${run.periodEnd.day}/${run.periodEnd.month}/${run.periodEnd.year}',
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
            if (run.status == 'pending_approval' ||
                run.status == 'approved' ||
                run.status == 'paid') ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _PayrollAmountBox(
                      label: 'รวมรายได้',
                      amount: run.totalGross,
                      color: Colors.green,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _PayrollAmountBox(
                      label: 'รายการหัก',
                      amount: run.totalDeductions,
                      color: Colors.red,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _PayrollAmountBox(
                      label: 'สุทธิ',
                      amount: run.totalNet,
                      color: Colors.blue,
                      isBold: true,
                    ),
                  ),
                ],
              ),
              if (run.totalEmployerCost > 0) ...[
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'ต้นทุนนายจ้าง',
                        style: TextStyle(fontSize: 11, color: Colors.blue),
                      ),
                      Text(
                        '฿${run.totalEmployerCost.toStringAsFixed(0)}',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                if (run.status == 'draft')
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: isSaving ? null : onRunCalculation,
                      icon: const Icon(Icons.calculate, size: 18),
                      label: const Text('คำนวณ'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.purple,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                if (run.status == 'pending_approval') ...[
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: isSaving ? null : onApprove,
                      icon: const Icon(Icons.check, size: 18),
                      label: const Text('อนุมัติ'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                if (run.status == 'pending_approval' ||
                    run.status == 'approved' ||
                    run.status == 'paid')
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onViewItems,
                      icon: const Icon(Icons.list, size: 18),
                      label: const Text('รายละเอียด'),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PayrollAmountBox extends StatelessWidget {
  final String label;
  final double amount;
  final Color color;
  final bool isBold;

  const _PayrollAmountBox({
    required this.label,
    required this.amount,
    required this.color,
    this.isBold = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 10, color: color.withOpacity(0.8)),
          ),
          const SizedBox(height: 2),
          Text(
            '฿${amount.toStringAsFixed(0)}',
            style: TextStyle(
              fontSize: 13,
              fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// ========================
// Payroll Items Tab
// ========================
class _PayrollItemsTab extends StatelessWidget {
  final List<PayrollItem> items;
  final bool isLoading;
  final String? selectedRunId;

  const _PayrollItemsTab({
    required this.items,
    required this.isLoading,
    required this.selectedRunId,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (selectedRunId == null) {
      return const Center(
        child: Text(
          'เลือกรอบเงินเดือนจากแท็บ "รอบเงินเดือน" ก่อน',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }
    if (items.isEmpty) {
      return const Center(
        child: Text(
          'ไม่มีรายการเงินเดือน',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    final byEmployee = <String, List<PayrollItem>>{};
    for (final item in items) {
      byEmployee.putIfAbsent(item.employeeId, () => []).add(item);
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: byEmployee.length,
      itemBuilder: (context, index) {
        final employeeId = byEmployee.keys.elementAt(index);
        final empItems = byEmployee[employeeId]!;
        return _EmployeePayrollCard(employeeId: employeeId, items: empItems);
      },
    );
  }
}

class _EmployeePayrollCard extends StatelessWidget {
  final String employeeId;
  final List<PayrollItem> items;

  const _EmployeePayrollCard({
    required this.employeeId,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    double totalEarning = 0;
    double totalDeduction = 0;
    double totalEmployerCost = 0;
    for (final item in items) {
      if (item.isEmployerCost) {
        totalEmployerCost += item.amount;
      } else if (item.isEarning) {
        totalEarning += item.amount;
      } else {
        totalDeduction += item.amount;
      }
    }
    final net = totalEarning - totalDeduction;

    final employeeItems = items.where((i) => !i.isEmployerCost).toList();
    final employerItems = items.where((i) => i.isEmployerCost).toList();

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassCard(
        section: GlassSection.card,
        borderRadius: 12,
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Employee: $employeeId',
              style: const TextStyle(
                  fontWeight: FontWeight.w600, fontSize: 14),
            ),
            const Divider(height: 16),
            ...employeeItems.map((item) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        item.itemLabel,
                        style: TextStyle(
                          fontSize: 13,
                          color: item.isEarning
                              ? Colors.black87
                              : Colors.red.shade700,
                        ),
                      ),
                      Text(
                        '${item.isEarning ? '+' : '-'}฿${item.amount.toStringAsFixed(2)}',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: item.isEarning
                              ? Colors.green
                              : Colors.red,
                        ),
                      ),
                    ],
                  ),
                )),
            if (employerItems.isNotEmpty) ...[
              const Divider(height: 16),
              const Text(
                'ส่วนนายจ้าง',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.blue),
              ),
              ...employerItems.map((item) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          item.itemLabel,
                          style: const TextStyle(fontSize: 13, color: Colors.blue),
                        ),
                        Text(
                          '฿${item.amount.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.blue,
                          ),
                        ),
                      ],
                    ),
                  )),
            ],
            const Divider(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('สุทธิ',
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                Text(
                  '฿${net.toStringAsFixed(2)}',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Colors.blue),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
