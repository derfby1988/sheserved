import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/dashboard_theme.dart';
import '../../data/models/employee.dart';
import '../../data/models/employee_invitation.dart';
import '../providers/organization_settings_provider.dart';
import '../providers/phase_three_provider.dart';
import '../providers/phase_zero_provider.dart';
import '../widgets/glass_card.dart';
import '../widgets/permission_denied_widget.dart';
import '../../../../shared/widgets/thai_buddhist_date_picker.dart';
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

class _EmployeeListPageState extends ConsumerState<EmployeeListPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) return;
      if (_tabController.index == 0) {
        // Refresh employees list when returning to employees tab
        // so invitees who just accepted appear immediately
        ref.read(phaseThreeProvider.notifier).loadEmployees(widget.professionId);
      } else if (_tabController.index == 1) {
        ref.read(phaseThreeProvider.notifier).loadEmployeeInvitations(widget.professionId);
      }
    });
    Future.microtask(() {
      ref.read(phaseZeroProvider.notifier).loadCurrentUserRoles();
      ref.read(phaseThreeProvider.notifier).loadEmployees(widget.professionId);
      ref.read(phaseThreeProvider.notifier).loadEmployeeInvitations(widget.professionId);
      ref.read(organizationSettingsProvider.notifier).loadOrganization(widget.professionId);
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  int get _hrAccessLevel {
    final zeroState = ref.watch(phaseZeroProvider);
    int maxLevel = 0;
    for (final roleMap in zeroState.userRolesAndPermissions) {
      final perms = roleMap['permissions'] as List<dynamic>?;
      if (perms == null) continue;
      for (final perm in perms) {
        if (perm is Map<String, dynamic> && perm['module_name'] == 'hr') {
          final lvl = perm['access_level'] as int? ?? 0;
          if (lvl > maxLevel) maxLevel = lvl;
        }
      }
    }
    return maxLevel;
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(phaseThreeProvider);
    final zeroState = ref.watch(phaseZeroProvider);

    if (zeroState.isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final accessLevel = _hrAccessLevel;
    if (accessLevel == 0) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('พนักงาน / Employees'),
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
        body: PermissionDeniedWidget(
          moduleName: 'hr',
          moduleLabel: 'จัดการพนักงาน',
          onRequestPermission: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('กรุณาติดต่อผู้ดูแลระบบเพื่อขอสิทธิ์')),
            );
          },
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('พนักงาน / Employees'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'พนักงาน'),
            Tab(text: 'คำเชิญ'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildEmployeesTab(state, accessLevel),
          _buildInvitationsTab(state, accessLevel),
        ],
      ),
      floatingActionButton: accessLevel < 2
          ? null
          : FloatingActionButton(
              onPressed: () => _showInviteEmployeeDialog(context),
              child: const Icon(Icons.person_add),
            ),
    );
  }

  Widget _buildEmployeesTab(PhaseThreeState state, int accessLevel) {
    if (state.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.errorMessage != null) {
      return Center(child: Text('Error: ${state.errorMessage}'));
    }
    final active = state.employees.where((e) => e.isActive).toList();
    final terminated = state.employees.where((e) => !e.isActive).toList();
    if (active.isEmpty && terminated.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'ยังไม่มีข้อมูลพนักงาน',
              style: TextStyle(color: Colors.grey),
            ),
            if (accessLevel >= 2)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: ElevatedButton.icon(
                  onPressed: () => _ensureOwnerAsEmployee(context),
                  icon: const Icon(Icons.person_pin),
                  label: const Text('สร้างพนักงานเจ้าของ'),
                ),
              ),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: active.length + terminated.length + (terminated.isNotEmpty ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == active.length && terminated.isNotEmpty) {
          return Padding(
            padding: const EdgeInsets.only(top: 24, bottom: 8),
            child: Text(
              'พนักงานที่ออกแล้ว (${terminated.length})',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          );
        }
        final emp = index < active.length
            ? active[index]
            : terminated[index - active.length - (terminated.isNotEmpty ? 1 : 0)];
        return _EmployeeCard(
          employee: emp,
          professionId: widget.professionId,
          accessLevel: accessLevel,
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
          onTerminate: accessLevel >= 3 && emp.isActive
              ? () => _showTerminateEmployeeDialog(context, emp)
              : null,
        );
      },
    );
  }

  Widget _buildInvitationsTab(PhaseThreeState state, int accessLevel) {
    if (state.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    final pending = state.employeeInvitations.where((i) => i.isPending).toList();
    final rejected = state.employeeInvitations.where((i) => i.isRejected).toList();
    if (pending.isEmpty && rejected.isEmpty) {
      return const Center(
        child: Text(
          'ไม่มีคำเชิญที่ค้างอยู่',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: pending.length + rejected.length,
      itemBuilder: (context, index) {
        if (index < pending.length) {
          final invite = pending[index];
          return _InvitationCard(
            invitation: invite,
            accessLevel: accessLevel,
            onCancel: accessLevel < 2
                ? null
                : () => _cancelInvitation(context, invite),
          );
        }
        final invite = rejected[index - pending.length];
        return _InvitationCard(
          invitation: invite,
          accessLevel: accessLevel,
          onReinvite: accessLevel >= 2
              ? () => _showInviteEmployeeDialog(context, reinviteInvitation: invite)
              : null,
        );
      },
    );
  }

  Future<void> _ensureOwnerAsEmployee(BuildContext context) async {
    final success = await ref.read(phaseThreeProvider.notifier).ensureOwnerAsEmployee(widget.professionId);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? 'สร้างพนักงานเจ้าของสำเร็จ' : 'สร้างพนักงานเจ้าของล้มเหลว'),
        ),
      );
    }
  }

  Future<void> _cancelInvitation(BuildContext context, EmployeeInvitation invite) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ยกเลิกคำเชิญ'),
        content: Text('ยกเลิกคำเชิญของ ${invite.fullName}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('ไม่')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('ยกเลิก')),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(phaseThreeProvider.notifier).rejectEmployeeInvitation(invite.token, widget.professionId);
  }

  void _showEditEmployeeDialog(BuildContext context, Employee employee) {
    _showEmployeeDialog(context, employee: employee);
  }

  void _showTerminateEmployeeDialog(BuildContext context, Employee employee) {
    final reasonController = TextEditingController();
    DateTime? terminationDate;
    bool canReinvite = true;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('ให้พนักงานออก'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('พนักงาน: ${employee.fullName}'),
                const SizedBox(height: 12),
                ThaiBuddhistDatePickerField(
                  value: terminationDate,
                  label: 'วันที่ให้ออก',
                  hint: 'เลือกวันที่ให้ออก',
                  onDateSelected: (date) => setState(() => terminationDate = date),
                ),
                TextField(
                  controller: reasonController,
                  decoration: const InputDecoration(labelText: 'เหตุผล'),
                  maxLines: 3,
                ),
                CheckboxListTile(
                  title: const Text('อนุญาตให้รับกลับได้'),
                  value: canReinvite,
                  onChanged: (v) => setState(() => canReinvite = v ?? true),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('ยกเลิก')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () async {
                final notifier = ref.read(phaseThreeProvider.notifier);
                final result = await notifier.terminateEmployee(
                  employeeId: employee.id,
                  terminationReason: reasonController.text.trim().isEmpty ? null : reasonController.text.trim(),
                  terminationDate: terminationDate,
                  canReinvite: canReinvite,
                );
                if (context.mounted) Navigator.pop(context);
                if (result != null && result['success'] == true) {
                  await notifier.loadEmployees(widget.professionId);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('ให้พนักงานออกสำเร็จ')),
                    );
                  }
                } else if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(result?['error'] as String? ?? 'ให้พนักงานออกล้มเหลว')),
                  );
                }
              },
              child: const Text('ให้ออก', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
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
    final emailController = TextEditingController(text: employee?.email ?? '');
    final phoneController = TextEditingController(text: employee?.phone ?? '');
    final bankNameController = TextEditingController(text: employee?.bankName ?? '');
    final bankAccController = TextEditingController(text: employee?.bankAccountNumber ?? '');
    bool isActive = employee?.isActive ?? true;
    String paymentMethod = employee?.paymentMethod ?? 'bank_transfer';
    DateTime? hireDate = employee?.hireDate;
    String? selectedBranchId = employee?.branchId;

    final orgState = ref.read(organizationSettingsProvider);
    final branches = orgState.settings?.branches ?? [];

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
                TextField(
                  controller: emailController,
                  decoration: const InputDecoration(labelText: 'อีเมล'),
                  keyboardType: TextInputType.emailAddress,
                ),
                TextField(
                  controller: phoneController,
                  decoration: const InputDecoration(labelText: 'เบอร์โทรศัพท์'),
                  keyboardType: TextInputType.phone,
                ),
                TextField(controller: deptController, decoration: const InputDecoration(labelText: 'แผนก')),
                TextField(controller: titleController, decoration: const InputDecoration(labelText: 'ตำแหน่ง')),
                if (branches.isNotEmpty)
                  DropdownButtonFormField<String>(
                    value: selectedBranchId,
                    decoration: const InputDecoration(labelText: 'สาขา'),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('ไม่ระบุ')),
                      ...branches.map((b) => DropdownMenuItem(
                        value: b.id,
                        child: Text(b.branchName),
                      )),
                    ],
                    onChanged: (v) => setState(() => selectedBranchId = v),
                  ),
                ThaiBuddhistDatePickerField(
                  value: hireDate,
                  label: 'วันเริ่มงาน',
                  hint: 'เลือกวันเริ่มงาน',
                  onDateSelected: (date) => setState(() => hireDate = date),
                ),
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
                  'email': emailController.text.trim().isEmpty ? null : emailController.text.trim(),
                  'phone': phoneController.text.trim().isEmpty ? null : phoneController.text.trim(),
                  'department': deptController.text.trim().isEmpty ? null : deptController.text.trim(),
                  'job_title': titleController.text.trim().isEmpty ? null : titleController.text.trim(),
                  'branch_id': selectedBranchId,
                  'hire_date': hireDate?.toIso8601String().split('T')[0],
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

  void _showInviteEmployeeDialog(BuildContext context, {EmployeeInvitation? reinviteInvitation}) {
    final isReinvite = reinviteInvitation != null;
    final codeController = TextEditingController(text: reinviteInvitation?.employeeCode ?? '');
    final nameController = TextEditingController(text: reinviteInvitation?.fullName ?? '');
    final deptController = TextEditingController(text: reinviteInvitation?.department ?? '');
    final titleController = TextEditingController(text: reinviteInvitation?.jobTitle ?? '');
    final salaryController = TextEditingController(
      text: reinviteInvitation?.salary != null ? reinviteInvitation!.salary.toString() : '',
    );
    final baseSalaryController = TextEditingController(
      text: reinviteInvitation?.baseSalary != null ? reinviteInvitation!.baseSalary.toString() : '',
    );
    final commissionController = TextEditingController(
      text: reinviteInvitation?.commissionRate != null ? reinviteInvitation!.commissionRate.toString() : '',
    );
    final pfRateController = TextEditingController(
      text: reinviteInvitation?.providentFundRate != null
          ? reinviteInvitation!.providentFundRate.toString()
          : '0.03',
    );
    final taxExpensesController = TextEditingController(
      text: reinviteInvitation?.taxDeductibleExpenses != null
          ? reinviteInvitation!.taxDeductibleExpenses.toString()
          : '0',
    );
    final personalAllowanceController = TextEditingController(
      text: reinviteInvitation?.personalAllowance != null
          ? reinviteInvitation!.personalAllowance.toString()
          : '60000',
    );
    final emailController = TextEditingController(text: reinviteInvitation?.email ?? '');
    final phoneController = TextEditingController(text: reinviteInvitation?.phone ?? '');
    final bankNameController = TextEditingController(text: reinviteInvitation?.bankName ?? '');
    final bankAccController = TextEditingController(text: reinviteInvitation?.bankAccountNumber ?? '');
    String paymentMethod = reinviteInvitation?.paymentMethod ?? 'bank_transfer';
    DateTime? hireDate;
    String? selectedBranchId = reinviteInvitation?.branchId;
    String? selectedUserId = reinviteInvitation?.userId;
    bool useExistingUser = reinviteInvitation?.userId != null || reinviteInvitation == null;
    String searchQuery = '';
    String? selectedRoleName = reinviteInvitation?.intendedRoleName ?? 'staff';

    final orgState = ref.read(organizationSettingsProvider);
    final branches = orgState.settings?.branches ?? [];

    // Preload roles and history
    Future.microtask(() {
      ref.read(phaseThreeProvider.notifier).loadOrganizationRoles(widget.professionId);
      if (isReinvite) {
        ref.read(phaseThreeProvider.notifier).loadInvitationHistory(
          professionId: widget.professionId,
          userId: reinviteInvitation!.userId,
          email: reinviteInvitation.email,
          phone: reinviteInvitation.phone,
        );
      }
    });

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(isReinvite ? 'เชิญพนักงานใหม่ (รับกลับ)' : 'เชิญพนักงาน'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: true, label: Text('สมาชิก Sheserved')),
                    ButtonSegment(value: false, label: Text('เชิญใหม่')),
                  ],
                  selected: {useExistingUser},
                  onSelectionChanged: isReinvite
                      ? null
                      : (v) => setState(() => useExistingUser = v.first),
                ),
                const SizedBox(height: 12),
                if (useExistingUser) ...[
                  TextField(
                    decoration: const InputDecoration(
                      labelText: 'ค้นหาสมาชิก',
                      suffixIcon: Icon(Icons.search),
                    ),
                    onChanged: (v) async {
                      searchQuery = v;
                      await ref.read(phaseThreeProvider.notifier).loadAvailableUsersForInvite(
                        widget.professionId,
                        search: v,
                      );
                      setState(() {});
                    },
                  ),
                  Consumer(
                    builder: (context, ref, child) {
                      final users = ref.watch(phaseThreeProvider).availableUsersForInvite;
                      if (users.isEmpty) {
                        return const Padding(
                          padding: EdgeInsets.all(8.0),
                          child: Text('ไม่พบสมาชิก', style: TextStyle(color: Colors.grey)),
                        );
                      }
                      return Column(
                        children: users.map((u) {
                          final userId = u['id'] as String;
                          final fullName = u['full_name'] as String? ?? 'ไม่ระบุชื่อ';
                          final email = u['email'] as String?;
                          final phone = u['phone'] as String?;
                          final previousStatus = u['previous_employee_status'] as String?;
                          final canReinviteUser = u['can_reinvite'] as bool? ?? true;
                          final cooldown = u['reinvite_eligible_at'] as String?;
                          final isInCooldown = cooldown != null && DateTime.tryParse(cooldown)?.isAfter(DateTime.now()) == true;
                          final isEligible = previousStatus == null || (canReinviteUser && !isInCooldown);
                          return RadioListTile<String>(
                            title: Text(fullName),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text([email, phone].whereType<String>().join(' | ')),
                                if (previousStatus == 'terminated')
                                  Text(
                                    isEligible
                                        ? 'สามารถรับกลับได้'
                                        : (isInCooldown
                                            ? 'อยู่ในช่วง cooldown (${DateTime.parse(cooldown!).day}/${DateTime.parse(cooldown).month}/${DateTime.parse(cooldown).year + 543})'
                                            : 'ไม่สามารถรับกลับได้'),
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: isEligible ? Colors.green : Colors.red,
                                    ),
                                  ),
                              ],
                            ),
                            value: userId,
                            groupValue: selectedUserId,
                            onChanged: isEligible
                                ? (v) {
                                    setState(() {
                                      selectedUserId = v;
                                      nameController.text = fullName;
                                      if (email != null) emailController.text = email;
                                      if (phone != null) phoneController.text = phone;
                                    });
                                    ref.read(phaseThreeProvider.notifier).loadInvitationHistory(
                                      professionId: widget.professionId,
                                      userId: userId,
                                      email: email,
                                      phone: phone,
                                    );
                                  }
                                : null,
                          );
                        }).toList(),
                      );
                    },
                  ),
                ] else ...[
                  TextField(
                    controller: emailController,
                    decoration: const InputDecoration(labelText: 'อีเมล (สำหรับส่งคำเชิญ)'),
                    keyboardType: TextInputType.emailAddress,
                  ),
                  TextField(
                    controller: phoneController,
                    decoration: const InputDecoration(labelText: 'เบอร์โทรศัพท์ (สำหรับส่งคำเชิญ)'),
                    keyboardType: TextInputType.phone,
                  ),
                ],
                const Divider(),
                TextField(controller: codeController, decoration: const InputDecoration(labelText: 'รหัสพนักงาน')),
                TextField(controller: nameController, decoration: const InputDecoration(labelText: 'ชื่อ-นามสกุล *')),
                TextField(controller: deptController, decoration: const InputDecoration(labelText: 'แผนก')),
                TextField(controller: titleController, decoration: const InputDecoration(labelText: 'ตำแหน่ง')),
                Consumer(
                  builder: (context, ref, child) {
                    final roles = ref.watch(phaseThreeProvider).organizationRoles;
                    if (roles.isEmpty) return const SizedBox.shrink();
                    return DropdownButtonFormField<String>(
                      value: selectedRoleName,
                      decoration: const InputDecoration(labelText: 'บทบาท (Role)'),
                      items: roles.map((r) {
                        final name = r['role_name'] as String? ?? '';
                        return DropdownMenuItem(value: name, child: Text(name));
                      }).toList(),
                      onChanged: (v) => setState(() => selectedRoleName = v ?? 'staff'),
                    );
                  },
                ),
                if (branches.isNotEmpty)
                  DropdownButtonFormField<String>(
                    value: selectedBranchId,
                    decoration: const InputDecoration(labelText: 'สาขา'),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('ไม่ระบุ')),
                      ...branches.map((b) => DropdownMenuItem(
                        value: b.id,
                        child: Text(b.branchName),
                      )),
                    ],
                    onChanged: (v) => setState(() => selectedBranchId = v),
                  ),
                ThaiBuddhistDatePickerField(
                  value: hireDate,
                  label: 'วันเริ่มงาน',
                  hint: 'เลือกวันเริ่มงาน',
                  onDateSelected: (date) => setState(() => hireDate = date),
                ),
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
                const Divider(),
                Consumer(
                  builder: (context, ref, child) {
                    final history = ref.watch(phaseThreeProvider).invitationHistory;
                    if (history.isEmpty) return const SizedBox.shrink();
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'ประวัติคำเชิญ / การรับกลับ',
                          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                        ),
                        const SizedBox(height: 8),
                        ...history.take(5).map((h) {
                          final status = h['status'] as String? ?? '';
                          final createdAt = h['created_at'] != null
                              ? DateTime.parse(h['created_at'] as String)
                              : null;
                          return ListTile(
                            dense: true,
                            title: Text('สถานะ: ${EmployeeInvitation.statusLabelThai(status)}'),
                            subtitle: Text(
                              'เชิญเมื่อ ${createdAt?.day}/${createdAt?.month}/${(createdAt?.year ?? 0) + 543}',
                              style: const TextStyle(fontSize: 11),
                            ),
                          );
                        }).toList(),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('ยกเลิก')),
            ElevatedButton(
              onPressed: () async {
                if (nameController.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('กรุณาระบุชื่อพนักงาน')),
                  );
                  return;
                }
                final data = {
                  'profession_id': widget.professionId,
                  if (useExistingUser && selectedUserId != null) 'user_id': selectedUserId,
                  if (!useExistingUser && emailController.text.trim().isNotEmpty)
                    'email': emailController.text.trim(),
                  if (!useExistingUser && phoneController.text.trim().isNotEmpty)
                    'phone': phoneController.text.trim(),
                  'employee_code': codeController.text.trim().isEmpty ? null : codeController.text.trim(),
                  'full_name': nameController.text.trim(),
                  'department': deptController.text.trim().isEmpty ? null : deptController.text.trim(),
                  'job_title': titleController.text.trim().isEmpty ? null : titleController.text.trim(),
                  'branch_id': selectedBranchId,
                  'hire_date': hireDate?.toIso8601String().split('T')[0],
                  'salary': double.tryParse(salaryController.text.trim()) ?? 0,
                  'base_salary': double.tryParse(baseSalaryController.text.trim()) ?? 0,
                  'commission_rate': double.tryParse(commissionController.text.trim()) ?? 0,
                  'provident_fund_rate': double.tryParse(pfRateController.text.trim()) ?? 0.03,
                  'personal_allowance': double.tryParse(personalAllowanceController.text.trim()) ?? 60000,
                  'tax_deductible_expenses': double.tryParse(taxExpensesController.text.trim()) ?? 0,
                  'payment_method': paymentMethod,
                  'bank_name': bankNameController.text.trim().isEmpty ? null : bankNameController.text.trim(),
                  'bank_account_number': bankAccController.text.trim().isEmpty ? null : bankAccController.text.trim(),
                  'intended_role_name': selectedRoleName,
                };
                await ref.read(phaseThreeProvider.notifier).inviteEmployee(data);
                if (context.mounted) Navigator.pop(context);
              },
              child: const Text('ส่งคำเชิญ'),
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
  final int accessLevel;
  final VoidCallback onEdit;
  final VoidCallback onTaxAllowance;
  final VoidCallback? onTerminate;

  const _EmployeeCard({
    required this.employee,
    required this.professionId,
    required this.accessLevel,
    required this.onEdit,
    required this.onTaxAllowance,
    this.onTerminate,
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
              backgroundColor: employee.isActive ? null : Colors.grey,
              child: Text(employee.fullName.substring(0, 1)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(employee.fullName, style: const TextStyle(fontWeight: FontWeight.w600)),
                  if ((employee.employeeCode != null && employee.employeeCode!.isNotEmpty) ||
                      (employee.department != null && employee.department!.isNotEmpty))
                    Text(
                      [
                        if (employee.employeeCode != null && employee.employeeCode!.isNotEmpty) employee.employeeCode,
                        if (employee.department != null && employee.department!.isNotEmpty) employee.department,
                      ].join(' | '),
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  if (employee.jobTitle != null)
                    Text(employee.jobTitle!, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  if (employee.email != null || employee.phone != null)
                    Text(
                      [employee.email, employee.phone].whereType<String>().join(' | '),
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  if (employee.hireDate != null)
                    Text(
                      'เริ่มงาน: ${employee.hireDate!.day}/${employee.hireDate!.month}/${employee.hireDate!.year + 543}',
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  if (!employee.isActive)
                    Container(
                      margin: const EdgeInsets.only(top: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'ให้ออกแล้ว${employee.terminationDate != null ? ' (${employee.terminationDate!.day}/${employee.terminationDate!.month}/${employee.terminationDate!.year + 543})' : ''}',
                        style: const TextStyle(fontSize: 11, color: Colors.red),
                      ),
                    ),
                  if (employee.terminationReason != null && employee.terminationReason!.isNotEmpty)
                    Text(
                      'เหตุผล: ${employee.terminationReason}',
                      style: const TextStyle(fontSize: 11, color: Colors.red),
                    ),
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
                if (v == 'terminate') onTerminate?.call();
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'edit', child: Text('แก้ไข')),
                const PopupMenuItem(value: 'tax', child: Text('ค่าลดหย่อนภาษี')),
                if (onTerminate != null && accessLevel >= 3)
                  const PopupMenuItem(value: 'terminate', child: Text('ให้ออก', style: TextStyle(color: Colors.red))),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _InvitationCard extends StatelessWidget {
  final EmployeeInvitation invitation;
  final int accessLevel;
  final VoidCallback? onCancel;
  final VoidCallback? onReinvite;

  const _InvitationCard({
    required this.invitation,
    required this.accessLevel,
    this.onCancel,
    this.onReinvite,
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
              child: Text(invitation.fullName.isNotEmpty ? invitation.fullName.substring(0, 1) : '?'),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(invitation.fullName, style: const TextStyle(fontWeight: FontWeight.w600)),
                  if (invitation.email != null)
                    Text(invitation.email!, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  if (invitation.phone != null)
                    Text(invitation.phone!, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  Text(
                    'สถานะ: ${invitation.statusDisplayThai}',
                    style: TextStyle(
                      fontSize: 11,
                      color: invitation.isRejected
                          ? Colors.red
                          : (invitation.isExpiredDate ? Colors.red : Colors.orange),
                    ),
                  ),
                  if (invitation.isRejected && invitation.rejectionReason != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.red.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'เหตุผลที่ปฏิเสธ:',
                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.red),
                            ),
                            Text(
                              invitation.rejectionReason!,
                              style: const TextStyle(fontSize: 11, color: Colors.red),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (invitation.expiresAt != null)
                    Text(
                      'หมดอายุ: ${invitation.expiresAt!.day}/${invitation.expiresAt!.month}/${invitation.expiresAt!.year + 543}',
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                ],
              ),
            ),
            if (accessLevel >= 2 && onCancel != null)
              IconButton(
                icon: const Icon(Icons.close, color: Colors.red),
                onPressed: onCancel,
              ),
            if (accessLevel >= 2 && onReinvite != null)
              IconButton(
                icon: const Icon(Icons.refresh, color: Colors.blue),
                onPressed: onReinvite,
                tooltip: 'เชิญใหม่',
              ),
          ],
        ),
      ),
    );
  }
}
