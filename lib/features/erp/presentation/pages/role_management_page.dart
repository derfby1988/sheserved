import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/dashboard_theme.dart';
import '../../data/models/organization_role.dart';
import '../providers/phase_zero_provider.dart';
import '../widgets/glass_card.dart';
import 'permission_management_page.dart';

class RoleManagementPage extends ConsumerStatefulWidget {
  final String professionId;

  const RoleManagementPage({
    Key? key,
    required this.professionId,
  }) : super(key: key);

  @override
  ConsumerState<RoleManagementPage> createState() => _RoleManagementPageState();
}

class _RoleManagementPageState extends ConsumerState<RoleManagementPage> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(phaseZeroProvider.notifier).loadOrganizationRoles(widget.professionId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(phaseZeroProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('จัดการตำแหน่ง (Roles)'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: state.isLoading
          ? const Center(child: CircularProgressIndicator())
          : state.errorMessage != null
              ? Center(child: Text('Error: ${state.errorMessage}'))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: state.organizationRoles.length,
                  itemBuilder: (context, index) {
                    final role = state.organizationRoles[index];
                    return _RoleCard(
                      role: role,
                      onTap: () => _showEditPermissions(role),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCreateRoleDialog(),
        icon: const Icon(Icons.add),
        label: const Text('เพิ่มตำแหน่ง'),
      ),
    );
  }

  void _showEditPermissions(OrganizationRole role) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => PermissionManagementPage(role: role),
      ),
    );
  }

  void _showCreateRoleDialog() {
    final nameController = TextEditingController();
    final descController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('เพิ่มตำแหน่งใหม่'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'ชื่อตำแหน่ง'),
            ),
            TextField(
              controller: descController,
              decoration: const InputDecoration(labelText: 'คำอธิบาย'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ยกเลิก'),
          ),
          ElevatedButton(
            onPressed: () async {
              final notifier = ref.read(phaseZeroProvider.notifier);
              final success = await notifier.createRole(
                professionId: widget.professionId,
                roleName: nameController.text.trim(),
                roleDescription: descController.text.trim(),
              );
              if (success && mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('สร้างตำแหน่งสำเร็จ')),
                );
              }
            },
            child: const Text('บันทึก'),
          ),
        ],
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  final OrganizationRole role;
  final VoidCallback onTap;

  const _RoleCard({
    required this.role,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlassCard(
        section: GlassSection.card,
        borderRadius: 16,
        padding: const EdgeInsets.all(16),
        child: ListTile(
          title: Text(role.roleName),
          subtitle: Text(role.roleDescription ?? 'ไม่มีคำอธิบาย'),
          trailing: role.isSystemRole
              ? Chip(
                  label: const Text('System'),
                  backgroundColor: Colors.orange.withOpacity(0.2),
                )
              : const Icon(Icons.chevron_right),
          onTap: onTap,
        ),
      ),
    );
  }
}
