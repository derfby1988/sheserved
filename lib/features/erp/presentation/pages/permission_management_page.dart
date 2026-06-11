import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/dashboard_theme.dart';
import '../../data/models/organization_role.dart';
import '../../data/models/role_module_permission.dart';
import '../providers/phase_zero_provider.dart';
import '../widgets/glass_card.dart';

class PermissionManagementPage extends ConsumerStatefulWidget {
  final OrganizationRole role;

  const PermissionManagementPage({
    Key? key,
    required this.role,
  }) : super(key: key);

  @override
  ConsumerState<PermissionManagementPage> createState() =>
      _PermissionManagementPageState();
}

class _PermissionManagementPageState
    extends ConsumerState<PermissionManagementPage> {
  final List<String> _allModules = [
    'pos',
    'inventory',
    'procurement',
    'accounting',
    'hr',
    'crm',
    'his',
    'lis',
    'telemedicine',
    'logistics',
    'commerce',
    'cart',
    'settlement',
    'read_model',
    'reliability',
  ];

  late Map<String, int> _moduleLevels;

  @override
  void initState() {
    super.initState();
    _moduleLevels = {};
    Future.microtask(() async {
      await ref.read(phaseZeroProvider.notifier).selectRole(widget.role);
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(phaseZeroProvider);
    final permissions = state.selectedRolePermissions;

    // Sync local map from state
    if (permissions.isNotEmpty && _moduleLevels.isEmpty) {
      for (final p in permissions) {
        _moduleLevels[p.moduleName] = p.accessLevel;
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('สิทธิ์: ${widget.role.roleName}'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          if (state.isSaving)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            TextButton(
              onPressed: () => _savePermissions(),
              child: const Text('บันทึก'),
            ),
        ],
      ),
      body: state.isLoading && permissions.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _allModules.length,
              itemBuilder: (context, index) {
                final module = _allModules[index];
                final level = _moduleLevels[module] ?? 0;
                return _PermissionRow(
                  moduleName: module,
                  accessLevel: level,
                  onChanged: (newLevel) {
                    setState(() {
                      _moduleLevels[module] = newLevel;
                    });
                  },
                );
              },
            ),
    );
  }

  Future<void> _savePermissions() async {
    final notifier = ref.read(phaseZeroProvider.notifier);

    final permissions = _moduleLevels.entries
        .where((e) => e.value > 0)
        .map((e) => RoleModulePermission(
              id: '',
              roleId: widget.role.id,
              moduleName: e.key,
              accessLevel: e.value,
            ))
        .toList();

    final success = await notifier.updateSelectedRolePermissions(permissions);

    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('บันทึกสิทธิ์สำเร็จ')),
      );
    }
  }
}

class _PermissionRow extends StatelessWidget {
  final String moduleName;
  final int accessLevel;
  final ValueChanged<int> onChanged;

  const _PermissionRow({
    required this.moduleName,
    required this.accessLevel,
    required this.onChanged,
  });

  String get _label {
    switch (accessLevel) {
      case 0:
        return 'None';
      case 1:
        return 'View';
      case 2:
        return 'Edit';
      case 3:
        return 'Full';
      default:
        return 'None';
    }
  }

  Color get _color {
    switch (accessLevel) {
      case 0:
        return Colors.grey;
      case 1:
        return Colors.blue;
      case 2:
        return Colors.orange;
      case 3:
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassCard(
        section: GlassSection.card,
        borderRadius: 12,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Text(
                moduleName.toUpperCase(),
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ),
            Chip(
              label: Text(
                _label,
                style: TextStyle(
                  color: _color.computeLuminance() > 0.5
                      ? Colors.black
                      : Colors.white,
                  fontSize: 12,
                ),
              ),
              backgroundColor: _color.withOpacity(0.2),
              side: BorderSide(color: _color.withOpacity(0.5)),
            ),
            const SizedBox(width: 8),
            DropdownButton<int>(
              value: accessLevel,
              underline: const SizedBox.shrink(),
              items: const [
                DropdownMenuItem(value: 0, child: Text('None')),
                DropdownMenuItem(value: 1, child: Text('View')),
                DropdownMenuItem(value: 2, child: Text('Edit')),
                DropdownMenuItem(value: 3, child: Text('Full')),
              ],
              onChanged: (v) {
                if (v != null) onChanged(v);
              },
            ),
          ],
        ),
      ),
    );
  }
}
