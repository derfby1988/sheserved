import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../features/erp/presentation/providers/organization_settings_provider.dart';
import '../features/admin/models/organization_settings.dart';

/// ERP Dashboard Shell — consistent Drawer + AppBar + Branch Selector
/// for all ERP sub-pages. Child pages render inside the body without
/// their own Scaffold/AppBar.
class ErpDashboardShell extends ConsumerStatefulWidget {
  final Widget child;

  const ErpDashboardShell({Key? key, required this.child}) : super(key: key);

  @override
  ConsumerState<ErpDashboardShell> createState() => _ErpDashboardShellState();
}

class _ErpDashboardShellState extends ConsumerState<ErpDashboardShell> {
  @override
  void initState() {
    super.initState();
    // Ensure organization data is loaded when shell mounts
    Future.microtask(() {
      ref.read(organizationSettingsProvider.notifier).loadFromCurrentUser();
    });
  }

  @override
  Widget build(BuildContext context) {
    final orgState = ref.watch(organizationSettingsProvider);
    final settings = orgState.settings;

    return Scaffold(
      appBar: AppBar(
        title: _buildAppBarTitle(context, orgState),
        backgroundColor: const Color(0xFF0066FF),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          // Notification bell
          IconButton(
            icon: const Icon(Icons.notifications_outlined, color: Colors.white),
            onPressed: () {
              // TODO: navigate to notifications
            },
          ),
        ],
      ),
      drawer: _ErpDrawer(
        onRouteSelected: (route) {
          Navigator.of(context).pop(); // close drawer
          if (route != null) {
            Navigator.of(context).pushNamed(route);
          }
        },
      ),
      body: widget.child,
    );
  }

  /// Build AppBar title with organization name + branch selector
  Widget _buildAppBarTitle(BuildContext context, OrganizationSettingsState orgState) {
    final settings = orgState.settings;

    if (orgState.isLoading || settings == null) {
      return Text('ERP Dashboard', style: GoogleFonts.inter(color: Colors.white));
    }

    final selectedBranch = orgState.selectedBranchId != null
        ? settings.branches.firstWhere(
            (b) => b.id == orgState.selectedBranchId,
            orElse: () => settings.selectedBranch ?? const OrganizationBranch(id: '', branchCode: '', branchName: ''),
          )
        : settings.selectedBranch;

    return Row(
      children: [
        // Logo thumbnail
        if (settings.hasLogo)
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Image.network(
              settings.logoUrl!,
              width: 28,
              height: 28,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const Icon(Icons.business, size: 24, color: Colors.white),
            ),
          )
        else
          const Icon(Icons.business, size: 24, color: Colors.white),
        const SizedBox(width: 8),
        // Org name + branch
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                settings.professionName,
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (selectedBranch != null)
                Text(
                  selectedBranch.branchName,
                  style: GoogleFonts.inter(
                    color: Colors.white.withOpacity(0.85),
                    fontSize: 12,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
        // Branch selector dropdown (if multiple branches)
        if (settings.branches.length > 1)
          _BranchSelector(
            branches: settings.branches,
            selectedBranchId: orgState.selectedBranchId,
            onChanged: (branchId) {
              ref.read(organizationSettingsProvider.notifier).selectBranch(branchId);
            },
          ),
      ],
    );
  }
}

/// Compact branch selector for AppBar
class _BranchSelector extends StatelessWidget {
  final List<OrganizationBranch> branches;
  final String? selectedBranchId;
  final ValueChanged<String> onChanged;

  const _BranchSelector({
    required this.branches,
    required this.selectedBranchId,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.2),
        borderRadius: BorderRadius.circular(6),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          isDense: true,
          value: selectedBranchId ?? (branches.isNotEmpty ? branches.first.id : null),
          icon: const Icon(Icons.expand_more, size: 16, color: Colors.white),
          dropdownColor: const Color(0xFF0066FF),
          style: GoogleFonts.inter(color: Colors.white, fontSize: 12),
          items: branches.map((branch) {
            return DropdownMenuItem<String>(
              value: branch.id,
              child: Text(
                branch.branchName,
                style: GoogleFonts.inter(fontSize: 12, color: Colors.white),
              ),
            );
          }).toList(),
          onChanged: (value) {
            if (value != null) onChanged(value);
          },
        ),
      ),
    );
  }
}

/// ERP Drawer with module navigation
class _ErpDrawer extends StatelessWidget {
  final void Function(String? route)? onRouteSelected;

  const _ErpDrawer({this.onRouteSelected});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: Color(0xFF0066FF),
              ),
              child: Row(
                children: [
                  const Icon(Icons.dashboard, color: Colors.white, size: 32),
                  const SizedBox(width: 12),
                  Text(
                    'ERP Dashboard',
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            // Menu items
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  _DrawerItem(
                    icon: Icons.home,
                    label: 'หน้าหลัก',
                    route: '/erp/dashboard',
                    onTap: onRouteSelected,
                  ),
                  _DrawerItem(
                    icon: Icons.point_of_sale,
                    label: 'POS Management',
                    route: null, // not yet implemented
                    onTap: onRouteSelected,
                  ),
                  _DrawerItem(
                    icon: Icons.inventory_2,
                    label: 'Inventory Management',
                    route: null,
                    onTap: onRouteSelected,
                  ),
                  _DrawerItem(
                    icon: Icons.shopping_bag,
                    label: 'Procurement Management',
                    route: null,
                    onTap: onRouteSelected,
                  ),
                  _DrawerItem(
                    icon: Icons.account_balance,
                    label: 'Accounting Management',
                    route: null,
                    onTap: onRouteSelected,
                  ),
                  _DrawerItem(
                    icon: Icons.people_alt,
                    label: 'HR Management',
                    route: null,
                    onTap: onRouteSelected,
                  ),
                  _DrawerItem(
                    icon: Icons.contact_support,
                    label: 'CRM Management',
                    route: null,
                    onTap: onRouteSelected,
                  ),
                  _DrawerItem(
                    icon: Icons.analytics,
                    label: 'KPI / Analytics',
                    route: '/kpi/dashboard',
                    onTap: onRouteSelected,
                  ),
                  const Divider(),
                  _DrawerItem(
                    icon: Icons.business,
                    label: 'ตั้งค่าองค์กร',
                    route: '/erp/settings',
                    onTap: onRouteSelected,
                  ),
                  _DrawerItem(
                    icon: Icons.logout,
                    label: 'กลับหน้า Home',
                    route: '/home',
                    onTap: (route) {
                      Navigator.of(context).pop();
                      Navigator.of(context).pushReplacementNamed('/home');
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DrawerItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? route;
  final void Function(String? route)? onTap;

  const _DrawerItem({
    required this.icon,
    required this.label,
    this.route,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDisabled = route == null;
    return ListTile(
      leading: Icon(icon, color: isDisabled ? Colors.grey : const Color(0xFF0066FF)),
      title: Text(
        label,
        style: GoogleFonts.inter(
          color: isDisabled ? Colors.grey : Colors.black87,
          fontSize: 14,
        ),
      ),
      onTap: isDisabled
          ? null
          : () => onTap?.call(route),
    );
  }
}
