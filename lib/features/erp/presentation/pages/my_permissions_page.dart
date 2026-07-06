import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/dashboard_theme.dart';
import '../providers/phase_zero_provider.dart';
import '../widgets/glass_card.dart';

class MyPermissionsPage extends ConsumerStatefulWidget {
  final String professionId;

  const MyPermissionsPage({
    super.key,
    required this.professionId,
  });

  @override
  ConsumerState<MyPermissionsPage> createState() => _MyPermissionsPageState();
}

class _MyPermissionsPageState extends ConsumerState<MyPermissionsPage> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(phaseZeroProvider.notifier).loadCurrentUserRoles();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(phaseZeroProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('สิทธิ์ของฉัน'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: state.isLoading
          ? const Center(child: CircularProgressIndicator())
          : state.errorMessage != null
              ? Center(child: Text(state.errorMessage!))
              : _buildContent(context, state.userRolesAndPermissions),
    );
  }

  Widget _buildContent(
    BuildContext context,
    List<Map<String, dynamic>> rolesAndPermissions,
  ) {
    if (rolesAndPermissions.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.lock_outline, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
              'คุณยังไม่มีตำแหน่งในองค์กร',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'กรุณาติดต่อผู้ดูแลระบบเพื่อมอบตำแหน่ง',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => _showContactAdminDialog(context),
              icon: const Icon(Icons.contact_support),
              label: const Text('ติดต่อผู้ดูแลระบบ'),
            ),
          ],
        ),
      );
    }

    final modulePermissions = <String, int>{};
    final roles = <Map<String, dynamic>>[];

    for (final roleMap in rolesAndPermissions) {
      final roleName = roleMap['role_name'] as String? ?? 'ไม่ทราบ';
      final branchId = roleMap['branch_id'] as String?;
      final isActive = roleMap['is_active'] as bool? ?? true;
      roles.add({
        'role_name': roleName,
        'branch_id': branchId,
        'is_active': isActive,
      });

      final perms = roleMap['permissions'] as List<dynamic>?;
      if (perms == null) continue;
      for (final perm in perms) {
        if (perm is Map<String, dynamic>) {
          final moduleName = perm['module_name'] as String? ?? '';
          final accessLevel = perm['access_level'] as int? ?? 0;
          if (accessLevel > (modulePermissions[moduleName] ?? 0)) {
            modulePermissions[moduleName] = accessLevel;
          }
        }
      }
    }

    final sortedModules = modulePermissions.keys.toList()..sort();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'ตำแหน่งของฉัน',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: roles.map((role) {
            final roleName = role['role_name'] as String;
            final branchId = role['branch_id'] as String?;
            final isActive = role['is_active'] as bool;
            return Chip(
              label: Text(
                '$roleName${branchId == null ? ' (HQ)' : ' (สาขา)'}',
                style: TextStyle(
                  color: isActive ? null : Colors.grey,
                  decoration: isActive ? null : TextDecoration.lineThrough,
                ),
              ),
              avatar: Icon(
                isActive ? Icons.check_circle : Icons.pause_circle,
                size: 18,
                color: isActive ? Colors.green : Colors.grey,
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 24),
        Text(
          'สิทธิ์การเข้าถึงโมดูล',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        ...sortedModules.map((moduleName) => _PermissionMatrixCard(
              moduleName: moduleName,
              accessLevel: modulePermissions[moduleName]!,
            )),
        const SizedBox(height: 24),
        OutlinedButton.icon(
          onPressed: () => _showContactAdminDialog(context),
          icon: const Icon(Icons.contact_support),
          label: const Text('ติดต่อผู้ดูแลระบบ'),
        ),
      ],
    );
  }

  void _showContactAdminDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ติดต่อผู้ดูแลระบบ'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('หากต้องการสิทธิ์เพิ่มเติม กรุณาติดต่อผู้ดูแลระบบขององค์กร'),
            SizedBox(height: 16),
            ListTile(
              leading: Icon(Icons.email),
              title: Text('อีเมล'),
              subtitle: Text('admin@your-organization.com'),
            ),
            ListTile(
              leading: Icon(Icons.phone),
              title: Text('โทรศัพท์'),
              subtitle: Text('02-XXX-XXXX'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ปิด'),
          ),
        ],
      ),
    );
  }
}

class _PermissionMatrixCard extends StatelessWidget {
  final String moduleName;
  final int accessLevel;

  const _PermissionMatrixCard({
    required this.moduleName,
    required this.accessLevel,
  });

  String get _levelLabel {
    switch (accessLevel) {
      case 0:
        return 'ไม่มีสิทธิ์';
      case 1:
        return 'ดูได้';
      case 2:
        return 'แก้ไข';
      case 3:
        return 'เต็มรูปแบบ';
      default:
        return 'ไม่ทราบ';
    }
  }

  Color get _levelColor {
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

  IconData get _levelIcon {
    switch (accessLevel) {
      case 0:
        return Icons.block;
      case 1:
        return Icons.visibility;
      case 2:
        return Icons.edit;
      case 3:
        return Icons.admin_panel_settings;
      default:
        return Icons.help;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GlassCard(
        section: GlassSection.card,
        borderRadius: 12,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(_levelIcon, color: _levelColor, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    moduleName,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    _levelLabel,
                    style: TextStyle(
                      color: _levelColor,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            if (accessLevel == 0)
              TextButton(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('กรุณาติดต่อผู้ดูแลระบบเพื่อขอสิทธิ์'),
                    ),
                  );
                },
                child: const Text('ขอสิทธิ์'),
              ),
          ],
        ),
      ),
    );
  }
}
