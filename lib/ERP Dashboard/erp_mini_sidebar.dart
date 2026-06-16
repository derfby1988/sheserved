import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../features/erp/presentation/providers/dashboard_theme_provider.dart';

class ErpMiniSidebar extends ConsumerStatefulWidget {
  final bool isExpanded;
  final VoidCallback onToggle;

  const ErpMiniSidebar({
    super.key,
    required this.isExpanded,
    required this.onToggle,
  });

  @override
  ConsumerState<ErpMiniSidebar> createState() => _ErpMiniSidebarState();
}

class _ErpMiniSidebarState extends ConsumerState<ErpMiniSidebar> {
  static const double _expandedWidth = 240;
  static const double _collapsedWidth = 60;

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(dashboardThemeProvider).theme;
    final isDark = theme?.isDarkMode ?? false;
    final primaryColor = theme?.primaryColor ?? const Color(0xFF00695C);
    final activeColor = isDark ? const Color(0xFFCCFF00) : const Color(0xFF4F7DF3);
    final inactiveColor = isDark ? Colors.white.withOpacity(0.55) : const Color(0xFF7A8794);
    final currentRoute = ModalRoute.of(context)?.settings.name ?? '/erp/dashboard';

    return AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeInOutCubic,
      width: widget.isExpanded ? _expandedWidth : _collapsedWidth,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? [primaryColor, const Color(0xFF0F0F0F)]
              : [const Color(0xFFF8FDFF), const Color(0xFFEAF8F0), const Color(0xFFF4EAFF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border(
          right: BorderSide(
            color: isDark ? Colors.white.withOpacity(0.08) : Colors.white.withOpacity(0.55),
            width: 1,
          ),
        ),
      ),
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final sidebarWidth = constraints.maxWidth;
            final showExpandedContent = widget.isExpanded && sidebarWidth >= _expandedWidth;

            return ClipRect(
              child: Column(
                children: [
                _buildToggleButton(isDark, activeColor),
                const SizedBox(height: 6),
                Expanded(
                  child: ListView(
                    padding: EdgeInsets.zero,
                    children: [
                      _MiniNavItem(
                        icon: Icons.home,
                        label: 'หน้าหลัก',
                        route: '/erp/dashboard',
                        isExpanded: widget.isExpanded,
                        currentRoute: currentRoute,
                        activeColor: activeColor,
                        inactiveColor: inactiveColor,
                        isDark: isDark,
                        onTap: (route) => Navigator.of(context).pushNamed(route!),
                      ),
                      _MiniNavItem(
                        icon: Icons.point_of_sale,
                        label: 'POS Management',
                        route: null,
                        isExpanded: widget.isExpanded,
                        currentRoute: currentRoute,
                        activeColor: activeColor,
                        inactiveColor: inactiveColor,
                        isDark: isDark,
                      ),
                      _MiniNavItem(
                        icon: Icons.inventory_2,
                        label: 'Inventory Management',
                        route: null,
                        isExpanded: widget.isExpanded,
                        currentRoute: currentRoute,
                        activeColor: activeColor,
                        inactiveColor: inactiveColor,
                        isDark: isDark,
                      ),
                      _MiniNavItem(
                        icon: Icons.shopping_bag,
                        label: 'Procurement Management',
                        route: null,
                        isExpanded: widget.isExpanded,
                        currentRoute: currentRoute,
                        activeColor: activeColor,
                        inactiveColor: inactiveColor,
                        isDark: isDark,
                      ),
                      _MiniNavItem(
                        icon: Icons.account_balance,
                        label: 'Accounting Management',
                        route: null,
                        isExpanded: widget.isExpanded,
                        currentRoute: currentRoute,
                        activeColor: activeColor,
                        inactiveColor: inactiveColor,
                        isDark: isDark,
                      ),
                      _MiniNavItem(
                        icon: Icons.people_alt,
                        label: 'HR Management',
                        route: null,
                        isExpanded: widget.isExpanded,
                        currentRoute: currentRoute,
                        activeColor: activeColor,
                        inactiveColor: inactiveColor,
                        isDark: isDark,
                      ),
                      _MiniNavItem(
                        icon: Icons.contact_support,
                        label: 'CRM Management',
                        route: null,
                        isExpanded: widget.isExpanded,
                        currentRoute: currentRoute,
                        activeColor: activeColor,
                        inactiveColor: inactiveColor,
                        isDark: isDark,
                      ),
                      _MiniNavItem(
                        icon: Icons.analytics,
                        label: 'KPI / Analytics',
                        route: '/kpi/dashboard',
                        isExpanded: widget.isExpanded,
                        currentRoute: currentRoute,
                        activeColor: activeColor,
                        inactiveColor: inactiveColor,
                        isDark: isDark,
                        onTap: (route) => Navigator.of(context).pushNamed(route!),
                      ),
                      if (showExpandedContent) ...[
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          child: Divider(color: isDark ? Colors.white24 : Colors.black12, height: 1),
                        ),
                        _MiniNavItem(
                          icon: Icons.color_lens,
                          label: 'ธีมสี Dashboard',
                          route: '/erp/settings/theme',
                          isExpanded: showExpandedContent,
                          currentRoute: currentRoute,
                          activeColor: activeColor,
                          inactiveColor: inactiveColor,
                          isDark: isDark,
                          onTap: (route) => Navigator.of(context).pushNamed(route!),
                        ),
                        _MiniNavItem(
                          icon: Icons.blur_on,
                          label: 'ความโปร่งใส (Glass)',
                          route: '/erp/settings/glass',
                          isExpanded: showExpandedContent,
                          currentRoute: currentRoute,
                          activeColor: activeColor,
                          inactiveColor: inactiveColor,
                          isDark: isDark,
                          onTap: (route) => Navigator.of(context).pushNamed(route!),
                        ),
                        _MiniNavItem(
                          icon: Icons.business,
                          label: 'ตั้งค่าองค์กร',
                          route: '/erp/settings',
                          isExpanded: showExpandedContent,
                          currentRoute: currentRoute,
                          activeColor: activeColor,
                          inactiveColor: inactiveColor,
                          isDark: isDark,
                          onTap: (route) => Navigator.of(context).pushNamed(route!),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          child: Divider(color: isDark ? Colors.white24 : Colors.black12, height: 1),
                        ),
                        _MiniNavItem(
                          icon: Icons.logout,
                          label: 'กลับหน้า Home',
                          route: '/home',
                          isExpanded: showExpandedContent,
                          currentRoute: currentRoute,
                          activeColor: activeColor,
                          inactiveColor: inactiveColor,
                          isDark: isDark,
                          onTap: (_) => Navigator.of(context).pushReplacementNamed('/home'),
                        ),
                      ],
                    ],
                  ),
                ),
                showExpandedContent ? _buildExpandedBottomCard(isDark) : _buildCollapsedBottomButton(isDark),
              ],
            ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildToggleButton(bool isDark, Color activeColor) {
    return Padding(
      padding: EdgeInsets.only(
        top: 12,
        left: widget.isExpanded ? 8 : 0,
        right: widget.isExpanded ? 8 : 0,
      ),
      child: Align(
        alignment: widget.isExpanded ? Alignment.centerRight : Alignment.center,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: widget.onToggle,
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withOpacity(0.06) : Colors.white.withOpacity(0.5),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isDark ? Colors.white.withOpacity(0.1) : Colors.white.withOpacity(0.8),
                ),
              ),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                transitionBuilder: (child, animation) => RotationTransition(
                  turns: Tween<double>(begin: 0.5, end: 0).animate(animation),
                  child: FadeTransition(opacity: animation, child: child),
                ),
                child: Icon(
                  widget.isExpanded ? Icons.chevron_left : Icons.chevron_right,
                  key: ValueKey<bool>(widget.isExpanded),
                  color: activeColor,
                  size: 22,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildExpandedBottomCard(bool isDark) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withOpacity(0.06) : Colors.white.withOpacity(0.72),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: isDark ? Colors.white.withOpacity(0.12) : Colors.white.withOpacity(0.9)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFCCFF00), Color(0xFF88CC00)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(Icons.auto_awesome, color: Colors.black87, size: 24),
            ),
            const SizedBox(height: 10),
            Text(
              'Upgrade to AI',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : const Color(0xFF1D2733),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'Features',
              style: GoogleFonts.inter(
                fontSize: 12,
                color: isDark ? Colors.white70 : const Color(0xFF617181),
              ),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFFCCFF00), Color(0xFF88CC00)]),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Upgrade now',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF1D2733),
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.arrow_forward, size: 14, color: Color(0xFF1D2733)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCollapsedBottomButton(bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Tooltip(
        message: 'Upgrade to AI Features',
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () {},
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFCCFF00), Color(0xFF88CC00)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.auto_awesome, color: Colors.black87, size: 20),
            ),
          ),
        ),
      ),
    );
  }
}

class _MiniNavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? route;
  final bool isExpanded;
  final String currentRoute;
  final Color activeColor;
  final Color inactiveColor;
  final bool isDark;
  final void Function(String? route)? onTap;

  const _MiniNavItem({
    required this.icon,
    required this.label,
    required this.route,
    required this.isExpanded,
    required this.currentRoute,
    required this.activeColor,
    required this.inactiveColor,
    required this.isDark,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDisabled = route == null;
    final isSelected = route != null && route == currentRoute;

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: isExpanded ? 8 : 6,
        vertical: 3,
      ),
      child: Tooltip(
        message: label,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: isDisabled ? null : () => onTap?.call(route),
            child: Container(
              width: double.infinity,
              height: 40,
              decoration: BoxDecoration(
                color: isSelected
                    ? (isDark ? const Color(0xFF1A1A1A) : Colors.white.withOpacity(0.88))
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(14),
                border: isSelected
                    ? Border.all(
                        color: isDark ? const Color(0xFFCCFF00).withOpacity(0.28) : activeColor.withOpacity(0.18),
                      )
                    : null,
              ),
              child: Row(
                children: [
                  // Icon is always placed at a stable position
                  SizedBox(
                    width: 40,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Icon(
                          icon,
                          size: 22,
                          color: isDisabled
                              ? inactiveColor.withOpacity(isDark ? 0.35 : 0.45)
                              : isSelected
                                  ? (isDark ? const Color(0xFFCCFF00) : activeColor)
                                  : (isDark ? Colors.white.withOpacity(0.75) : const Color(0xFF1D2733)),
                        ),
                        if (isSelected && !isExpanded)
                          Positioned(
                            top: 4,
                            right: 4,
                            child: Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: isDark ? const Color(0xFFCCFF00) : activeColor,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  // Animated content container to prevent layout reflow / overflow
                  Expanded(
                    child: ClipRect(
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 180),
                        opacity: isExpanded ? 1.0 : 0.0,
                        child: OverflowBox(
                          minWidth: 184,
                          maxWidth: 184,
                          alignment: Alignment.centerLeft,
                          child: Row(
                            children: [
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.inter(
                                    color: isDisabled
                                        ? inactiveColor.withOpacity(isDark ? 0.45 : 0.55)
                                        : isSelected
                                            ? (isDark ? const Color(0xFFCCFF00) : activeColor)
                                            : (isDark ? Colors.white : const Color(0xFF1D2733)),
                                    fontSize: 14,
                                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                  ),
                                ),
                              ),
                              if (isSelected) ...[
                                Icon(Icons.chevron_right, color: activeColor, size: 16),
                                const SizedBox(width: 8),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
