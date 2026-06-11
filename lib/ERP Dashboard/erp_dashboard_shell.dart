import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../features/erp/presentation/providers/organization_settings_provider.dart';
import '../features/erp/presentation/providers/dashboard_theme_provider.dart';
import '../features/admin/models/organization_settings.dart';
import '../services/auth_service.dart';

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
    // Ensure organization data + theme are loaded when shell mounts
    Future.microtask(() {
      ref.read(organizationSettingsProvider.notifier).loadFromCurrentUser();
      final user = AuthService.instance.currentUser;
      final professionId = user?.professionId;
      if (user != null && professionId != null && professionId.isNotEmpty) {
        ref.read(dashboardThemeProvider.notifier).loadTheme(
          userId: user.id,
          professionId: professionId,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final orgState = ref.watch(organizationSettingsProvider);
    final theme = ref.watch(dashboardThemeProvider).theme;
    final isDark = theme?.isDarkMode ?? false;
    final bgColors = isDark
        ? [const Color(0xFF0F0F0F), const Color(0xFF1A1A1A)]
        : [const Color(0xFFDFF8FF), const Color(0xFFDFF7E8), const Color(0xFFF4E4FB)];
    final textPrimary = isDark ? Colors.white : const Color(0xFF1D2733);
    final iconColor = isDark ? const Color(0xFFCCFF00) : const Color(0xFF4F7DF3);

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F0F0F) : const Color(0xFFE8F6FF),
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: _buildAppBarTitle(context, orgState, isDark),
        centerTitle: false,
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: iconColor),
        actions: [
          // Theme quick toggle
          IconButton(
            icon: Icon(
              isDark ? Icons.wb_sunny : Icons.nightlight_round,
              color: iconColor,
            ),
            tooltip: isDark ? 'Switch to Light' : 'Switch to Dark',
            onPressed: () {
              ref.read(dashboardThemeProvider.notifier).toggleDarkMode();
            },
          ),
          // Notification bell
          IconButton(
            icon: Icon(Icons.notifications_outlined, color: iconColor),
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
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: bgColors,
            stops: isDark ? null : const [0.0, 0.5, 1.0],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: widget.child,
      ),
    );
  }

  /// Build AppBar title with organization name + branch selector
  Widget _buildAppBarTitle(BuildContext context, OrganizationSettingsState orgState, bool isDark) {
    final settings = orgState.settings;
    final textPrimary = isDark ? Colors.white : const Color(0xFF1D2733);
    final textSecondary = isDark ? Colors.white70 : const Color(0xFF617181);

    if (orgState.isLoading || settings == null) {
      return Text(
        'ERP Dashboard',
        style: GoogleFonts.inter(color: textPrimary, fontWeight: FontWeight.w600),
      );
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
            borderRadius: BorderRadius.circular(6),
            child: Image.network(
              settings.logoUrl!,
              width: 28,
              height: 28,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => Icon(Icons.business, size: 24, color: textPrimary),
            ),
          )
        else
          Icon(Icons.business, size: 24, color: textPrimary),
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
                  color: textPrimary,
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
                    color: textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
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
            isDark: isDark,
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
  final bool isDark;

  const _BranchSelector({
    required this.branches,
    required this.selectedBranchId,
    required this.onChanged,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = isDark ? Colors.white : const Color(0xFF1D2733);
    final bgColor = isDark ? Colors.white.withOpacity(0.15) : const Color(0xFFF5FBFF);
    final borderColor = isDark ? Colors.white.withOpacity(0.25) : const Color(0xFFD7E8F6);

    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: borderColor, width: 1),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          isDense: true,
          value: selectedBranchId ?? (branches.isNotEmpty ? branches.first.id : null),
          icon: Icon(Icons.expand_more, size: 16, color: isDark ? const Color(0xFFCCFF00) : const Color(0xFF4F7DF3)),
          dropdownColor: isDark ? const Color(0xFF1A1A1A) : Colors.white,
          style: GoogleFonts.inter(color: textColor, fontSize: 12, fontWeight: FontWeight.w500),
          items: branches.map((branch) {
            return DropdownMenuItem<String>(
              value: branch.id,
              child: Text(
                branch.branchName,
                style: GoogleFonts.inter(fontSize: 12, color: textColor),
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

/// ERP Drawer with module navigation (uses theme colors)
class _ErpDrawer extends ConsumerWidget {
  final void Function(String? route)? onRouteSelected;

  const _ErpDrawer({this.onRouteSelected});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(dashboardThemeProvider).theme;
    final primaryColor = theme?.primaryColor ?? const Color(0xFF00695C);
    final isDark = theme?.isDarkMode ?? false;
    final activeColor = isDark ? const Color(0xFFCCFF00) : const Color(0xFF4F7DF3);
    final inactiveColor = isDark ? Colors.white.withOpacity(0.55) : const Color(0xFF6B7A8A);
    final currentRoute = ModalRoute.of(context)?.settings.name ?? '/erp/dashboard';

    return Drawer(
      backgroundColor: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isDark
                ? [primaryColor, const Color(0xFF0F0F0F)]
                : [const Color(0xFFF8FDFF), const Color(0xFFEAF8F0), const Color(0xFFF4EAFF)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Header
              Container(
                margin: const EdgeInsets.fromLTRB(16, 12, 16, 10),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white.withOpacity(0.06) : Colors.white.withOpacity(0.72),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: isDark ? Colors.white.withOpacity(0.12) : Colors.white.withOpacity(0.9),
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        color: isDark ? Colors.white.withOpacity(0.08) : const Color(0xFFF4F8FF),
                      ),
                      child: Icon(Icons.local_pharmacy, color: isDark ? const Color(0xFFCCFF00) : const Color(0xFF4F7DF3), size: 28),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Sheserved ERP',
                        style: GoogleFonts.inter(
                          color: isDark ? Colors.white : const Color(0xFF1D2733),
                          fontSize: 19,
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              // Menu items
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                  children: [
                  _DrawerItem(
                    icon: Icons.home,
                    label: 'หน้าหลัก',
                    route: '/erp/dashboard',
                    currentRoute: currentRoute,
                    activeColor: activeColor,
                    inactiveColor: inactiveColor,
                    isDark: isDark,
                    onTap: onRouteSelected,
                  ),
                  _DrawerItem(
                    icon: Icons.point_of_sale,
                    label: 'POS Management',
                    route: null,
                    currentRoute: currentRoute,
                    activeColor: activeColor,
                    inactiveColor: inactiveColor,
                    isDark: isDark,
                    onTap: onRouteSelected,
                  ),
                  _DrawerItem(
                    icon: Icons.inventory_2,
                    label: 'Inventory Management',
                    route: null,
                    currentRoute: currentRoute,
                    activeColor: activeColor,
                    inactiveColor: inactiveColor,
                    isDark: isDark,
                    onTap: onRouteSelected,
                  ),
                  _DrawerItem(
                    icon: Icons.shopping_bag,
                    label: 'Procurement Management',
                    route: null,
                    currentRoute: currentRoute,
                    activeColor: activeColor,
                    inactiveColor: inactiveColor,
                    isDark: isDark,
                    onTap: onRouteSelected,
                  ),
                  _DrawerItem(
                    icon: Icons.account_balance,
                    label: 'Accounting Management',
                    route: null,
                    currentRoute: currentRoute,
                    activeColor: activeColor,
                    inactiveColor: inactiveColor,
                    isDark: isDark,
                    onTap: onRouteSelected,
                  ),
                  _DrawerItem(
                    icon: Icons.people_alt,
                    label: 'HR Management',
                    route: null,
                    currentRoute: currentRoute,
                    activeColor: activeColor,
                    inactiveColor: inactiveColor,
                    isDark: isDark,
                    onTap: onRouteSelected,
                  ),
                  _DrawerItem(
                    icon: Icons.contact_support,
                    label: 'CRM Management',
                    route: null,
                    currentRoute: currentRoute,
                    activeColor: activeColor,
                    inactiveColor: inactiveColor,
                    isDark: isDark,
                    onTap: onRouteSelected,
                  ),
                  _DrawerItem(
                    icon: Icons.analytics,
                    label: 'KPI / Analytics',
                    route: '/kpi/dashboard',
                    currentRoute: currentRoute,
                    activeColor: activeColor,
                    inactiveColor: inactiveColor,
                    isDark: isDark,
                    onTap: onRouteSelected,
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Divider(color: isDark ? Colors.white24 : Colors.black12, height: 1),
                  ),
                  // Theme & Glassmorphism Settings
                  _DrawerItem(
                    icon: Icons.color_lens,
                    label: 'ธีมสี Dashboard',
                    route: '/erp/settings/theme',
                    currentRoute: currentRoute,
                    activeColor: activeColor,
                    inactiveColor: inactiveColor,
                    isDark: isDark,
                    onTap: onRouteSelected,
                  ),
                  _DrawerItem(
                    icon: Icons.blur_on,
                    label: 'ความโปร่งใส (Glass)',
                    route: '/erp/settings/glass',
                    currentRoute: currentRoute,
                    activeColor: activeColor,
                    inactiveColor: inactiveColor,
                    isDark: isDark,
                    onTap: onRouteSelected,
                  ),
                  _DrawerItem(
                    icon: Icons.business,
                    label: 'ตั้งค่าองค์กร',
                    route: '/erp/settings',
                    currentRoute: currentRoute,
                    activeColor: activeColor,
                    inactiveColor: inactiveColor,
                    isDark: isDark,
                    onTap: onRouteSelected,
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Divider(color: isDark ? Colors.white24 : Colors.black12, height: 1),
                  ),
                  _DrawerItem(
                    icon: Icons.logout,
                    label: 'กลับหน้า Home',
                    route: '/home',
                    currentRoute: currentRoute,
                    activeColor: activeColor,
                    inactiveColor: inactiveColor,
                    isDark: isDark,
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
    ),
  );
  }
}

class _DrawerItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? route;
  final String currentRoute;
  final Color activeColor;
  final Color inactiveColor;
  final bool isDark;
  final void Function(String? route)? onTap;

  const _DrawerItem({
    required this.icon,
    required this.label,
    this.route,
    required this.currentRoute,
    required this.activeColor,
    required this.inactiveColor,
    required this.isDark,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDisabled = route == null;
    final isSelected = route != null && currentRoute == route;
    final labelColor = isDisabled
        ? inactiveColor.withOpacity(isDark ? 0.45 : 0.55)
        : isSelected
            ? (isDark ? const Color(0xFFCCFF00) : activeColor)
            : (isDark ? Colors.white : const Color(0xFF1D2733));
    final leadingColor = isDisabled
        ? inactiveColor.withOpacity(isDark ? 0.35 : 0.45)
        : isSelected
            ? (isDark ? const Color(0xFFCCFF00) : activeColor)
            : labelColor;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: isDisabled ? null : () => onTap?.call(route),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: isSelected
                  ? (isDark ? const Color(0xFF1A1A1A) : Colors.white.withOpacity(0.88))
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(18),
              border: isSelected
                  ? Border.all(
                      color: isDark
                          ? const Color(0xFFCCFF00).withOpacity(0.28)
                          : activeColor.withOpacity(0.18),
                    )
                  : null,
            ),
            child: Row(
              children: [
                Icon(icon, color: leadingColor, size: 22),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    label,
                    style: GoogleFonts.inter(
                      color: labelColor,
                      fontSize: 14,
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
                if (isSelected)
                  Icon(
                    Icons.chevron_right,
                    color: isDark ? const Color(0xFFCCFF00) : activeColor,
                    size: 18,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
