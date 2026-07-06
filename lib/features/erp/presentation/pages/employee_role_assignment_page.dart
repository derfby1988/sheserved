import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/dashboard_theme.dart';
import '../../data/models/organization_role.dart';
import '../providers/phase_zero_provider.dart';
import '../widgets/glass_card.dart';
import '../../../../services/auth_service.dart';

class EmployeeRoleAssignmentPage extends ConsumerStatefulWidget {
  final String professionId;

  const EmployeeRoleAssignmentPage({
    super.key,
    required this.professionId,
  });

  @override
  ConsumerState<EmployeeRoleAssignmentPage> createState() =>
      _EmployeeRoleAssignmentPageState();
}

class _EmployeeRoleAssignmentPageState
    extends ConsumerState<EmployeeRoleAssignmentPage> {
  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(phaseZeroProvider.notifier).loadUsersWithRoles(widget.professionId);
      ref.read(phaseZeroProvider.notifier).loadOrganizationRoles(widget.professionId);
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get _filteredUsers {
    final state = ref.watch(phaseZeroProvider);
    if (_searchQuery.isEmpty) return state.usersWithRoles;
    return state.usersWithRoles.where((user) {
      final name = (user['full_name'] as String?) ?? '';
      final username = (user['username'] as String?) ?? '';
      final email = (user['email'] as String?) ?? '';
      final phone = (user['phone'] as String?) ?? '';
      final query = _searchQuery.toLowerCase();
      return name.toLowerCase().contains(query) ||
          username.toLowerCase().contains(query) ||
          email.toLowerCase().contains(query) ||
          phone.toLowerCase().contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(phaseZeroProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('มอบหมายตำแหน่งให้ผู้ใช้'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          TextButton.icon(
            onPressed: () => Navigator.of(context).pushNamed(
              '/erp/roles',
              arguments: {'professionId': widget.professionId},
            ),
            icon: const Icon(Icons.settings_suggest),
            label: const Text('จัดการตำแหน่ง'),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                labelText: 'ค้นหาผู้ใช้',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
              ),
              onChanged: (value) => setState(() => _searchQuery = value),
            ),
          ),
          if (state.errorMessage != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                state.errorMessage!,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
          Expanded(
            child: state.isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredUsers.isEmpty
                    ? Center(
                        child: Text(
                          'ไม่พบผู้ใช้ในองค์กร',
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: Colors.grey,
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: _filteredUsers.length,
                        itemBuilder: (context, index) {
                          final user = _filteredUsers[index];
                          return _UserRoleListTile(
                            user: user,
                            professionId: widget.professionId,
                            availableRoles: state.organizationRoles
                                .where((r) => r.isActive)
                                .toList(),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

class _UserRoleListTile extends ConsumerWidget {
  final Map<String, dynamic> user;
  final String professionId;
  final List<OrganizationRole> availableRoles;

  const _UserRoleListTile({
    required this.user,
    required this.professionId,
    required this.availableRoles,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final roles = (user['roles'] as List<dynamic>?) ?? [];
    final userId = user['user_id'] as String;
    final fullName = (user['full_name'] as String?) ?? 'ไม่ทราบชื่อ';
    final username = (user['username'] as String?) ?? '';
    final email = (user['email'] as String?) ?? '';
    final phone = (user['phone'] as String?) ?? '';

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlassCard(
        section: GlassSection.card,
        borderRadius: 16,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                  child: Text(
                    fullName.isNotEmpty ? fullName[0].toUpperCase() : '?',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        fullName,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      if (username.isNotEmpty || email.isNotEmpty || phone.isNotEmpty)
                        Text(
                          [
                            if (username.isNotEmpty) '@$username',
                            if (email.isNotEmpty) email,
                            if (phone.isNotEmpty) phone,
                          ].join(' · '),
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.grey,
                          ),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline),
                  tooltip: 'มอบตำแหน่ง',
                  onPressed: () => _showAssignRoleDialog(context, ref, userId),
                ),
              ],
            ),
            if (roles.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: roles.map((roleData) {
                  final role = roleData as Map<String, dynamic>;
                  final roleName = role['role_name'] as String? ?? 'ไม่ทราบ';
                  final isActive = role['is_active'] as bool? ?? true;
                  final branchId = role['branch_id'] as String?;
                  final employeeRoleId = role['employee_role_id'] as String?;

                  return _RoleAssignmentChip(
                    roleName: roleName,
                    isActive: isActive,
                    branchLabel: branchId == null ? 'HQ' : 'สาขา',
                    onRevoke: () => _revokeRole(context, ref, employeeRoleId),
                    onToggle: (value) => _toggleRole(
                      context,
                      ref,
                      employeeRoleId,
                      value,
                    ),
                  );
                }).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showAssignRoleDialog(
    BuildContext context,
    WidgetRef ref,
    String userId,
  ) {
    OrganizationRole? selectedRole;
    String? selectedBranchId;
    final branches = <Map<String, dynamic>>[];

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('มอบตำแหน่งให้ผู้ใช้'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<OrganizationRole>(
                    decoration: const InputDecoration(
                      labelText: 'เลือกตำแหน่ง',
                      border: OutlineInputBorder(),
                    ),
                    value: selectedRole,
                    items: availableRoles.map((role) {
                      return DropdownMenuItem(
                        value: role,
                        child: Text(role.roleName),
                      );
                    }).toList(),
                    onChanged: (value) =>
                        setDialogState(() => selectedRole = value),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String?>(
                    decoration: const InputDecoration(
                      labelText: 'ขอบเขต (Scope)',
                      border: OutlineInputBorder(),
                    ),
                    value: selectedBranchId,
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('HQ (ทุกสาขา)'),
                      ),
                      ...branches.map((b) => DropdownMenuItem<String?>(
                        value: b['id'] as String?,
                        child: Text(b['name'] as String? ?? 'สาขา'),
                      )),
                    ],
                    onChanged: (value) =>
                        setDialogState(() => selectedBranchId = value),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('ยกเลิก'),
                ),
                ElevatedButton(
                  onPressed: selectedRole == null
                      ? null
                      : () async {
                          final currentUser = AuthService.instance.currentUser;
                          final notifier = ref.read(phaseZeroProvider.notifier);
                          final success = await notifier.assignRoleToUser(
                            professionId: professionId,
                            userId: userId,
                            roleId: selectedRole!.id,
                            branchId: selectedBranchId,
                            assignedBy: currentUser?.id,
                          );
                          if (context.mounted) {
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  success
                                      ? 'มอบตำแหน่ง "${selectedRole!.roleName}" สำเร็จ'
                                      : 'มอบตำแหน่งไม่สำเร็จ',
                                ),
                              ),
                            );
                          }
                        },
                  child: const Text('มอบตำแหน่ง'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _revokeRole(
    BuildContext context,
    WidgetRef ref,
    String? employeeRoleId,
  ) async {
    if (employeeRoleId == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ยืนยันการถอนตำแหน่ง'),
        content: const Text('ต้องการถอนตำแหน่งนี้ออกจากผู้ใช้ใช่หรือไม่?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('ยกเลิก'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('ถอนตำแหน่ง'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final notifier = ref.read(phaseZeroProvider.notifier);
    final success = await notifier.revokeRoleFromUser(
      employeeRoleId: employeeRoleId,
      professionId: professionId,
    );

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? 'ถอนตำแหน่งสำเร็จ' : 'ถอนตำแหน่งไม่สำเร็จ'),
        ),
      );
    }
  }

  Future<void> _toggleRole(
    BuildContext context,
    WidgetRef ref,
    String? employeeRoleId,
    bool isActive,
  ) async {
    if (employeeRoleId == null) return;

    final repository = ref.read(phaseZeroRepositoryProvider);
    final success = await repository.toggleEmployeeRole(employeeRoleId, isActive);

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success
                ? (isActive ? 'เปิดใช้งานตำแหน่งสำเร็จ' : 'ปิดใช้งานตำแหน่งสำเร็จ')
                : 'เปลี่ยนสถานะไม่สำเร็จ',
          ),
        ),
      );
      if (success) {
        ref.read(phaseZeroProvider.notifier).loadUsersWithRoles(professionId);
      }
    }
  }
}

class _RoleAssignmentChip extends StatelessWidget {
  final String roleName;
  final bool isActive;
  final String branchLabel;
  final VoidCallback onRevoke;
  final ValueChanged<bool> onToggle;

  const _RoleAssignmentChip({
    required this.roleName,
    required this.isActive,
    required this.branchLabel,
    required this.onRevoke,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            roleName,
            style: TextStyle(
              color: isActive ? null : Colors.grey,
              decoration: isActive ? null : TextDecoration.lineThrough,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            '($branchLabel)',
            style: TextStyle(
              fontSize: 12,
              color: isActive ? Colors.blue : Colors.grey,
            ),
          ),
        ],
      ),
      avatar: Icon(
        isActive ? Icons.check_circle : Icons.pause_circle,
        size: 18,
        color: isActive ? Colors.green : Colors.grey,
      ),
      deleteIcon: const Icon(Icons.remove_circle_outline, size: 18),
      onDeleted: onRevoke,
      backgroundColor: isActive
          ? Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3)
          : Colors.grey.withOpacity(0.1),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}
