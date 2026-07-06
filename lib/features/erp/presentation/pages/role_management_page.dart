import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
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
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(
          'จัดการตำแหน่ง (Roles)',
          style: GoogleFonts.notoSansThai(
            fontWeight: FontWeight.w600,
            fontSize: 20,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                theme.scaffoldBackgroundColor.withOpacity(0.8),
                theme.scaffoldBackgroundColor.withOpacity(0.0),
              ],
            ),
          ),
        ),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDark
                ? [
                    const Color(0xFF1E1E2F),
                    const Color(0xFF0F0F1A),
                  ]
                : [
                    const Color(0xFFE8F5E9), // Light green tint
                    const Color(0xFFF3E5F5), // Light purple tint
                  ],
          ),
        ),
        child: SafeArea(
          child: state.isLoading
              ? const Center(
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                  ),
                )
              : state.errorMessage != null
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.error_outline,
                            size: 48,
                            color: theme.colorScheme.error,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'เกิดข้อผิดพลาด: ${state.errorMessage}',
                            style: GoogleFonts.notoSansThai(
                              color: theme.colorScheme.error,
                            ),
                          ),
                        ],
                      ),
                    )
                  : state.organizationRoles.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.admin_panel_settings_outlined,
                                size: 80,
                                color: theme.colorScheme.primary.withOpacity(0.4),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'ยังไม่มีการสร้างตำแหน่งภายในองค์กร',
                                style: GoogleFonts.notoSansThai(
                                  fontSize: 16,
                                  color: Colors.grey,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          itemCount: state.organizationRoles.length,
                          itemBuilder: (context, index) {
                            final role = state.organizationRoles[index];
                            return _RoleCard(
                              role: role,
                              professionId: widget.professionId,
                              onTap: () => _showEditPermissions(role),
                              onToggleActive: (value) => _toggleRoleActive(
                                context,
                                value,
                                role,
                                ref,
                                widget.professionId,
                              ),
                            );
                          },
                        ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCreateRoleDialog(),
        elevation: 4,
        highlightElevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
        ),
        backgroundColor: theme.colorScheme.primary,
        icon: const Icon(Icons.add, color: Colors.white),
        label: Text(
          'เพิ่มตำแหน่ง',
          style: GoogleFonts.notoSansThai(
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
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
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        title: Text(
          'เพิ่มตำแหน่งใหม่',
          style: GoogleFonts.notoSansThai(
            fontWeight: FontWeight.w600,
            fontSize: 20,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'กำหนดชื่อและคำอธิบายสิทธิ์สำหรับตำแหน่งงานใหม่นี้',
              style: GoogleFonts.notoSansThai(
                fontSize: 12,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: nameController,
              decoration: InputDecoration(
                labelText: 'ชื่อตำแหน่ง (เช่น accountant, manager)',
                labelStyle: GoogleFonts.notoSansThai(fontSize: 13),
                prefixIcon: const Icon(Icons.badge_outlined, size: 20),
                filled: true,
                fillColor: Theme.of(context).brightness == Brightness.dark
                    ? Colors.black.withOpacity(0.2)
                    : Colors.grey.withOpacity(0.05),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(
                    color: Theme.of(context).colorScheme.primary,
                    width: 1.5,
                  ),
                ),
              ),
              style: GoogleFonts.notoSansThai(fontSize: 14),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: descController,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: 'คำอธิบาย (หน้าที่ความรับผิดชอบ)',
                labelStyle: GoogleFonts.notoSansThai(fontSize: 13),
                prefixIcon: const Icon(Icons.description_outlined, size: 20),
                filled: true,
                fillColor: Theme.of(context).brightness == Brightness.dark
                    ? Colors.black.withOpacity(0.2)
                    : Colors.grey.withOpacity(0.05),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(
                    color: Theme.of(context).colorScheme.primary,
                    width: 1.5,
                  ),
                ),
              ),
              style: GoogleFonts.notoSansThai(fontSize: 14),
            ),
          ],
        ),
        actionsPadding: const EdgeInsets.only(right: 16, bottom: 16),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(
              'ยกเลิก',
              style: GoogleFonts.notoSansThai(
                fontWeight: FontWeight.w600,
                color: Colors.grey,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              final notifier = ref.read(phaseZeroProvider.notifier);
              final success = await notifier.createRole(
                professionId: widget.professionId,
                roleName: nameController.text.trim(),
                roleDescription: descController.text.trim(),
              );
              if (success && context.mounted) {
                Navigator.pop(context);
                messenger.showSnackBar(
                  SnackBar(
                    content: Text(
                      'สร้างตำแหน่งสำเร็จ',
                      style: GoogleFonts.notoSansThai(),
                    ),
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              backgroundColor: Theme.of(context).colorScheme.primary,
            ),
            child: Text(
              'บันทึก',
              style: GoogleFonts.notoSansThai(
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _toggleRoleActive(
    BuildContext context,
    bool isActive,
    OrganizationRole role,
    WidgetRef ref,
    String professionId,
  ) {
    final messenger = ScaffoldMessenger.of(context);
    ref.read(phaseZeroProvider.notifier).toggleOrganizationRoleActive(
      role.id,
      isActive,
      professionId: professionId,
    );
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          isActive ? 'เปิดใช้งาน ${role.roleName}' : 'ระงับการใช้งาน ${role.roleName}',
          style: GoogleFonts.notoSansThai(),
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  final OrganizationRole role;
  final String professionId;
  final VoidCallback onTap;
  final ValueChanged<bool> onToggleActive;

  const _RoleCard({
    required this.role,
    required this.professionId,
    required this.onTap,
    required this.onToggleActive,
  });

  IconData _getRoleIcon(String name) {
    final lower = name.toLowerCase();
    if (lower.contains('owner')) return Icons.workspace_premium;
    if (lower.contains('manager') || lower.contains('admin')) return Icons.manage_accounts;
    if (lower.contains('cashier') || lower.contains('sale')) return Icons.point_of_sale;
    if (lower.contains('account')) return Icons.account_balance_wallet;
    if (lower.contains('procure')) return Icons.shopping_bag_outlined;
    if (lower.contains('stock') || lower.contains('inventory')) return Icons.inventory_2_outlined;
    if (lower.contains('staff') || lower.contains('employee')) return Icons.badge_outlined;
    return Icons.shield_outlined;
  }

  Color _getIconColor(String name, BuildContext context) {
    final theme = Theme.of(context);
    final lower = name.toLowerCase();
    if (lower.contains('owner')) return const Color(0xFFFFD700); // gold
    if (lower.contains('manager') || lower.contains('admin')) return theme.colorScheme.primary;
    if (lower.contains('cashier') || lower.contains('sale')) return const Color(0xFF4CAF50); // green
    if (lower.contains('account')) return const Color(0xFF2196F3); // blue
    return theme.colorScheme.onSurface.withOpacity(0.6);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final iconColor = _getIconColor(role.roleName, context);
    final roleIcon = _getRoleIcon(role.roleName);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlassCard(
        section: GlassSection.card,
        borderRadius: 20,
        padding: EdgeInsets.zero,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                // Role Icon Container
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: iconColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: iconColor.withOpacity(0.2),
                      width: 1,
                    ),
                  ),
                  child: Icon(
                    roleIcon,
                    color: iconColor,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                // Text Column
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        role.roleName,
                        style: GoogleFonts.notoSansThai(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: role.isActive
                              ? theme.colorScheme.onSurface
                              : theme.colorScheme.onSurface.withOpacity(0.4),
                          decoration: role.isActive
                              ? TextDecoration.none
                              : TextDecoration.lineThrough,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          if (role.isSystemRole)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.orange.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: Colors.orange.withOpacity(0.3),
                                  width: 1,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.shield,
                                    size: 10,
                                    color: Colors.orange,
                                  ),
                                  const SizedBox(width: 3),
                                  Text(
                                    'System',
                                    style: GoogleFonts.inter(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.orange,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          if (!role.isActive)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.grey.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: Colors.grey.withOpacity(0.3),
                                  width: 1,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.pause_circle_filled,
                                    size: 10,
                                    color: Colors.grey,
                                  ),
                                  const SizedBox(width: 3),
                                  Text(
                                    'Inactive',
                                    style: GoogleFonts.inter(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w700,
                                    ).copyWith(color: Colors.grey),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        role.roleDescription ?? 'ไม่มีคำอธิบายสำหรับตำแหน่งนี้',
                        style: GoogleFonts.notoSansThai(
                          fontSize: 12,
                          color: role.isActive
                              ? theme.colorScheme.onSurface.withOpacity(0.55)
                              : theme.colorScheme.onSurface.withOpacity(0.35),
                          height: 1.4,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                // Active toggle switch (compact)
                Transform.scale(
                  scale: 0.8,
                  child: Switch(
                    value: role.isActive,
                    onChanged: onToggleActive,
                    activeThumbColor: theme.colorScheme.primary,
                    inactiveThumbColor: Colors.grey,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
                const SizedBox(width: 2),
                // Chevron icon inside interactive container
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.onSurface.withOpacity(0.03),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: theme.colorScheme.onSurface.withOpacity(0.35),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

}

