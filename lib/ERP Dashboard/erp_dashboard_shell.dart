import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../features/erp/presentation/providers/organization_settings_provider.dart';
import '../features/erp/presentation/providers/dashboard_theme_provider.dart';
import '../features/admin/models/organization_settings.dart';
import '../services/auth_service.dart';
import 'erp_mini_sidebar.dart';

/// ERP Dashboard Shell — Collapsible Mini Sidebar + AppBar + Branch Selector
/// for all ERP sub-pages. Child pages render inside the body without
/// their own Scaffold/AppBar.
class ErpDashboardShell extends ConsumerStatefulWidget {
  final Widget child;

  const ErpDashboardShell({Key? key, required this.child}) : super(key: key);

  @override
  ConsumerState<ErpDashboardShell> createState() => _ErpDashboardShellState();
}

class _ErpDashboardShellState extends ConsumerState<ErpDashboardShell> {
  bool _isSidebarExpanded = false;

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
    final iconColor = isDark ? const Color(0xFFCCFF00) : const Color(0xFF4F7DF3);

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F0F0F) : const Color(0xFFE8F6FF),
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        toolbarHeight: orgState.settings != null && orgState.settings!.branches.length > 1 ? 68 : kToolbarHeight,
        title: _buildAppBarTitle(orgState, isDark),
        centerTitle: false,
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: iconColor),
        actions: [
          if (orgState.settings != null && orgState.settings!.branches.length > 1)
            _BranchSelector(
              branches: orgState.settings!.branches,
              selectedBranchId: orgState.selectedBranchId,
              onChanged: (branchId) {
                ref.read(organizationSettingsProvider.notifier).selectBranch(branchId);
              },
              isDark: isDark,
            ),
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
      drawer: null,
      body: Row(
        children: [
          ErpMiniSidebar(
            isExpanded: _isSidebarExpanded,
            onToggle: () => setState(() => _isSidebarExpanded = !_isSidebarExpanded),
          ),
          Expanded(
            child: Container(
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
          ),
        ],
      ),
    );
  }

  Widget _buildAppBarTitle(OrganizationSettingsState orgState, bool isDark) {
    final settings = orgState.settings;
    final textPrimary = isDark ? Colors.white : const Color(0xFF1D2733);
    final textSecondary = isDark ? Colors.white70 : const Color(0xFF617181);

    if (settings == null) {
      return Text(
        'ERP Dashboard',
        style: GoogleFonts.inter(
          color: textPrimary,
          fontWeight: FontWeight.w600,
        ),
      );
    }

    final selectedBranch = orgState.selectedBranchId != null
        ? settings.branches.firstWhere(
            (b) => b.id == orgState.selectedBranchId,
            orElse: () => settings.selectedBranch ?? const OrganizationBranch(id: '', branchCode: '', branchName: ''),
          )
        : settings.selectedBranch;

    if (settings.branches.length <= 1 || selectedBranch == null || selectedBranch.branchName.isEmpty) {
      return Text(
        'ERP Dashboard',
        style: GoogleFonts.inter(
          color: textPrimary,
          fontWeight: FontWeight.w600,
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'ERP Dashboard',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.inter(
            color: textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 1),
        Text(
          selectedBranch.branchName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.inter(
            color: textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
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

