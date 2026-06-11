import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/dashboard_theme_provider.dart';
import 'glass_card.dart';

/// Collapsible Sidebar แบบ Glassmorphism
/// รองรับ Light/Dark Theme + Responsive (Mobile/Tablet/Desktop)
class GlassSidebar extends ConsumerStatefulWidget {
  final bool isExpanded;
  final VoidCallback? onToggle;
  final int? selectedIndex;
  final ValueChanged<int>? onItemSelected;
  final List<SidebarItem> items;
  final Widget? promoCard;
  final Widget? footer;

  const GlassSidebar({
    Key? key,
    this.isExpanded = true,
    this.onToggle,
    this.selectedIndex,
    this.onItemSelected,
    required this.items,
    this.promoCard,
    this.footer,
  }) : super(key: key);

  @override
  ConsumerState<GlassSidebar> createState() => _GlassSidebarState();
}

class _GlassSidebarState extends ConsumerState<GlassSidebar> {
  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(dashboardThemeProvider).theme;
    final isDark = theme?.isDarkMode ?? false;
    final primaryColor = theme?.primaryColor ?? const Color(0xFF00695C);
    final accentColor = theme?.accentColor ?? const Color(0xFFFFC107);

    // Gradient background สำหรับ glass effect
    final bgGradient = LinearGradient(
      colors: [
        primaryColor,
        primaryColor.withOpacity(0.85),
      ],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );

    final sidebarWidth = widget.isExpanded ? 240.0 : 56.0;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      width: sidebarWidth,
      child: Stack(
        children: [
          // Layer 1: Gradient Background
          Container(
            decoration: BoxDecoration(gradient: bgGradient),
          ),
          // Layer 2: Glass overlay
          GlassCard(
            section: GlassSection.sidebar,
            borderRadius: 0,
            width: sidebarWidth,
            child: Column(
              children: [
                // Header: Logo + Toggle
                _buildHeader(accentColor, isDark),
                const SizedBox(height: 8),
                // Nav Items
                Expanded(
                  child: ListView.builder(
                    padding: EdgeInsets.zero,
                    itemCount: widget.items.length,
                    itemBuilder: (context, index) {
                      final item = widget.items[index];
                      final isSelected = widget.selectedIndex == index;
                      return _NavItem(
                        item: item,
                        isExpanded: widget.isExpanded,
                        isSelected: isSelected,
                        isDark: isDark,
                        accentColor: accentColor,
                        onTap: () => widget.onItemSelected?.call(index),
                      );
                    },
                  ),
                ),
                // Promo Card (bottom)
                if (widget.promoCard != null && widget.isExpanded)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: widget.promoCard,
                  ),
                // Footer
                if (widget.footer != null)
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: widget.footer,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(Color accentColor, bool isDark) {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          if (widget.isExpanded) ...[
            const Icon(Icons.local_pharmacy, color: Colors.white, size: 28),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Sheserved',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ] else ...[
            const Icon(Icons.local_pharmacy, color: Colors.white, size: 28),
          ],
          // Toggle button
          Material(
            color: accentColor,
            borderRadius: BorderRadius.circular(20),
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: widget.onToggle,
              child: Container(
                width: 32,
                height: 32,
                child: Icon(
                  widget.isExpanded ? Icons.chevron_left : Icons.chevron_right,
                  color: isDark ? Colors.black : Colors.white,
                  size: 20,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ========================
// Sidebar Item Model
// ========================

class SidebarItem {
  final IconData icon;
  final String label;
  final String? route;
  final int? badgeCount;
  final bool isLocked;

  const SidebarItem({
    required this.icon,
    required this.label,
    this.route,
    this.badgeCount,
    this.isLocked = false,
  });
}

// ========================
// Nav Item Widget
// ========================

class _NavItem extends StatelessWidget {
  final SidebarItem item;
  final bool isExpanded;
  final bool isSelected;
  final bool isDark;
  final Color accentColor;
  final VoidCallback? onTap;

  const _NavItem({
    required this.item,
    required this.isExpanded,
    required this.isSelected,
    required this.isDark,
    required this.accentColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final activeBg = isDark ? const Color(0xFF1A1A1A) : Colors.white;
    final activeText = isDark ? accentColor : const Color(0xFF00695C);
    final inactiveOpacity = isDark ? 0.5 : 0.7;
    final activeBorder = isDark ? Border.all(color: accentColor.withOpacity(0.5), width: 0.5) : null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: item.isLocked ? null : onTap,
          child: Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: isSelected ? activeBg : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              border: isSelected ? activeBorder : null,
            ),
            child: Row(
              children: [
                Icon(
                  item.icon,
                  color: isSelected
                      ? activeText
                      : Colors.white.withOpacity(inactiveOpacity),
                  size: 24,
                ),
                if (isExpanded) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      item.label,
                      style: TextStyle(
                        color: isSelected
                            ? activeText
                            : Colors.white.withOpacity(inactiveOpacity),
                        fontSize: 14,
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  // Badge
                  if (item.badgeCount != null && item.badgeCount! > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${item.badgeCount}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  // Lock icon
                  if (item.isLocked)
                    const Icon(Icons.lock, color: Colors.white38, size: 16),
                ] else if (item.badgeCount != null && item.badgeCount! > 0) ...[
                  // จุดแดงเล็กๆ ตอน collapsed
                  Positioned(
                    right: 0,
                    top: 0,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
