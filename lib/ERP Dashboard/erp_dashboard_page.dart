import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../features/erp/presentation/providers/organization_settings_provider.dart';
import '../features/erp/presentation/providers/dashboard_theme_provider.dart';
import '../features/erp/presentation/widgets/glass_card.dart';
import '../features/erp/data/models/dashboard_theme.dart';
import '../features/admin/models/organization_settings.dart';
import 'erp_first_time_setup_page.dart';

/// Main ERP Dashboard Page – entry point after tapping HomeErpCard.
/// Shows Organization Header (real data), branch selector, and module tiles.
class ErpDashboardPage extends ConsumerStatefulWidget {
  const ErpDashboardPage({Key? key}) : super(key: key);

  @override
  ConsumerState<ErpDashboardPage> createState() => _ErpDashboardPageState();
}

class _ErpDashboardPageState extends ConsumerState<ErpDashboardPage> {
  @override
  void initState() {
    super.initState();
    // Load organization from current user on first build
    Future.microtask(() {
      ref.read(organizationSettingsProvider.notifier).loadFromCurrentUser();
    });
  }

  @override
  Widget build(BuildContext context) {
    final orgState = ref.watch(organizationSettingsProvider);
    final theme = ref.watch(dashboardThemeProvider).theme;
    final isDark = theme?.isDarkMode ?? false;

    // Dynamic background gradient based on theme
    final bgColors = isDark
        ? [const Color(0xFF0F0F0F), const Color(0xFF1A1A1A)]
        : [const Color(0xFFDFF8FF), const Color(0xFFDFF7E8), const Color(0xFFF4E4FB)];

    // First-time setup: no org data yet (but user has profession_id)
    if (!orgState.isLoading && orgState.settings == null) {
      return Stack(
        children: [
          _DashboardBackdrop(isDark: isDark, colors: bgColors),
          SafeArea(child: const ErpFirstTimeSetupPage()),
        ],
      );
    }

    return Stack(
      children: [
        _DashboardBackdrop(isDark: isDark, colors: bgColors),
        SafeArea(
          child: Column(
            children: [
              _OrganizationHeader(
                isLoading: orgState.isLoading,
                settings: orgState.settings,
                selectedBranchId: orgState.selectedBranchId,
                theme: theme,
                onBranchChanged: (branchId) {
                  ref.read(organizationSettingsProvider.notifier).selectBranch(branchId);
                },
              ),
              if (orgState.errorMessage != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                  child: GlassCard(
                    section: GlassSection.card,
                    tintColor: const Color(0xFFFFE5E8),
                    borderRadius: 24,
                    padding: const EdgeInsets.all(14),
                    child: Text(
                      orgState.errorMessage!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.red.shade800,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final boardWidth = constraints.maxWidth;
                    final columns = _responsiveColumns(boardWidth);
                    return SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                      child: _DashboardModuleBoard(
                        width: boardWidth - 32,
                        columns: columns,
                        theme: theme,
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Background layer with natural pastel light mode blobs.
class _DashboardBackdrop extends StatelessWidget {
  final bool isDark;
  final List<Color> colors;

  const _DashboardBackdrop({required this.isDark, required this.colors});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: colors,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        if (!isDark) ...[
          Positioned(
            top: -70,
            left: -40,
            child: _BackdropBlob(color: const Color(0xFFBFE7FF), size: 220),
          ),
          Positioned(
            top: 110,
            right: -70,
            child: _BackdropBlob(color: const Color(0xFFCFEFBA), size: 250),
          ),
          Positioned(
            bottom: -90,
            left: 60,
            child: _BackdropBlob(color: const Color(0xFFF0D6FF), size: 240),
          ),
        ],
      ],
    );
  }
}

class _BackdropBlob extends StatelessWidget {
  final Color color;
  final double size;

  const _BackdropBlob({required this.color, required this.size});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withOpacity(0.55),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.24),
              blurRadius: 80,
              spreadRadius: 30,
            ),
          ],
        ),
      ),
    );
  }
}

/// Organization Header widget — แสดงชื่อองค์กร, โลโก้, สาขา
class _OrganizationHeader extends StatelessWidget {
  final bool isLoading;
  final OrganizationSettings? settings;
  final String? selectedBranchId;
  final DashboardTheme? theme;
  final ValueChanged<String> onBranchChanged;

  const _OrganizationHeader({
    required this.isLoading,
    required this.settings,
    required this.selectedBranchId,
    required this.theme,
    required this.onBranchChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = theme?.isDarkMode ?? false;
    final headerTint = isDark ? const Color(0xFF101010) : const Color(0xFFF8FBFF);
    final titleColor = isDark ? Colors.white : const Color(0xFF1D2733);
    final subtitleColor = isDark ? Colors.white70 : const Color(0xFF617181);
    final accentColor = isDark ? const Color(0xFFCCFF00) : const Color(0xFF4F7DF3);

    if (isLoading) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: GlassCard(
          section: GlassSection.card,
          tintColor: headerTint,
          borderRadius: 24,
          padding: const EdgeInsets.all(18),
          child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      );
    }

    if (settings == null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: GlassCard(
          section: GlassSection.card,
          tintColor: headerTint,
          borderRadius: 24,
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              _LogoBadge(
                isDark: isDark,
                accentColor: accentColor,
                child: const Icon(Icons.business, color: Color(0xFF4F7DF3), size: 28),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Text(
                  'กำลังโหลดข้อมูลองค์กร...',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.grey),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final org = settings!;
    final selectedBranch = selectedBranchId != null
        ? org.branches.firstWhere(
            (b) => b.id == selectedBranchId,
            orElse: () => org.selectedBranch ?? const OrganizationBranch(id: '', branchCode: '', branchName: ''),
          )
        : org.selectedBranch;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: GlassCard(
        section: GlassSection.card,
        tintColor: headerTint,
        borderRadius: 24,
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            _LogoBadge(
              isDark: isDark,
              accentColor: accentColor,
              imageUrl: org.hasLogo ? org.logoUrl : null,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    org.professionName,
                    style: GoogleFonts.inter(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: titleColor,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    selectedBranch?.branchName ?? 'เลือกสาขา',
                    style: GoogleFonts.inter(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                      color: subtitleColor,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (org.branches.length > 1) ...[
                    const SizedBox(height: 8),
                    _BranchDropdown(
                      branches: org.branches,
                      selectedBranchId: selectedBranchId,
                      onChanged: onBranchChanged,
                      isDark: isDark,
                    ),
                  ],
                ],
              ),
            ),
            IconButton(
              icon: Icon(Icons.notifications_outlined, color: accentColor),
              onPressed: () {
                // TODO: navigate to notifications
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _LogoBadge extends StatelessWidget {
  final bool isDark;
  final Color accentColor;
  final Widget? child;
  final String? imageUrl;

  const _LogoBadge({
    required this.isDark,
    required this.accentColor,
    this.child,
    this.imageUrl,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: isDark ? Colors.white.withOpacity(0.08) : const Color(0xFFF4F8FF),
        border: Border.all(color: Colors.white.withOpacity(isDark ? 0.15 : 0.6), width: 1),
        boxShadow: [
          BoxShadow(
            color: accentColor.withOpacity(0.10),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
        image: imageUrl != null
            ? DecorationImage(image: NetworkImage(imageUrl!), fit: BoxFit.contain)
            : null,
      ),
      child: imageUrl == null ? Center(child: child) : null,
    );
  }
}

/// Dropdown เลือกสาขา
class _BranchDropdown extends StatelessWidget {
  final List<OrganizationBranch> branches;
  final String? selectedBranchId;
  final ValueChanged<String> onChanged;
  final bool isDark;

  const _BranchDropdown({
    required this.branches,
    required this.selectedBranchId,
    required this.onChanged,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.08) : const Color(0xFFF5FBFF),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: isDark ? Colors.white.withOpacity(0.15) : const Color(0xFFD7E8F6)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          isDense: true,
          value: selectedBranchId ?? (branches.isNotEmpty ? branches.first.id : null),
          icon: Icon(Icons.expand_more, size: 18, color: isDark ? const Color(0xFFCCFF00) : const Color(0xFF4F7DF3)),
          dropdownColor: isDark ? const Color(0xFF1A1A1A) : Colors.white,
          style: GoogleFonts.inter(
            fontSize: 13,
            color: isDark ? Colors.white : const Color(0xFF1D2733),
            fontWeight: FontWeight.w500,
          ),
          items: branches.map((branch) {
            return DropdownMenuItem<String>(
              value: branch.id,
              child: Text(
                branch.branchName,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: isDark ? Colors.white : const Color(0xFF1D2733),
                ),
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

int _responsiveColumns(double width) {
  if (width >= 1200) return 4;
  if (width >= 800) return 3;
  return 2;
}

class _DashboardModuleBoard extends StatelessWidget {
  final double width;
  final int columns;
  final DashboardTheme? theme;

  const _DashboardModuleBoard({
    required this.width,
    required this.columns,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = theme?.isDarkMode ?? false;
    final specs = _moduleSpecs(isDark);
    final spacing = columns >= 3 ? 11.0 : 10.0;
    final tileWidth = (width - (spacing * (columns - 1))) / columns;

    return Wrap(
      spacing: spacing,
      runSpacing: spacing,
      children: specs.map((spec) {
        final span = spec.span.clamp(1, columns);
        final itemWidth = span == columns ? width : (tileWidth * span) + (spacing * (span - 1));
        final itemHeight = tileWidth * spec.heightFactor;
        return SizedBox(
          width: itemWidth,
          height: itemHeight,
          child: _ModuleTile(spec: spec, theme: theme),
        );
      }).toList(),
    );
  }

  List<_DashboardModuleSpec> _moduleSpecs(bool isDark) {
    final pastel = isDark
        ? null
        : <Color>[
            const Color(0xFFBFE7FF),
            const Color(0xFFCFEFBA),
            const Color(0xFFF0E7B4),
            const Color(0xFFA7D8F5),
            const Color(0xFFBDEBDB),
            const Color(0xFFE5F6C8),
            const Color(0xFFD7D0FF),
            const Color(0xFFF7C9A9),
          ];

    Color tint(int index, Color fallback) => isDark ? fallback : pastel![index % pastel.length];

    return [
      _DashboardModuleSpec(label: 'POS Management', routeName: '/posManagement', icon: Icons.point_of_sale, span: 1, heightFactor: 0.96, variant: _ModuleTileVariant.square, tintColor: tint(0, const Color(0xFFCCFF00))),
      _DashboardModuleSpec(label: 'Inventory Management', routeName: '/inventoryManagement', icon: Icons.inventory_2, span: 1, heightFactor: 0.96, variant: _ModuleTileVariant.square, tintColor: tint(1, const Color(0xFFCCFF00))),
      _DashboardModuleSpec(label: 'Procurement Management', routeName: '/procurementManagement', icon: Icons.shopping_bag, span: 2, heightFactor: 0.68, variant: _ModuleTileVariant.capsule, tintColor: tint(2, const Color(0xFFCCFF00))),
      _DashboardModuleSpec(label: 'Accounting Management', routeName: '/accountingManagement', icon: Icons.account_balance, span: 1, heightFactor: 0.96, variant: _ModuleTileVariant.square, tintColor: tint(3, const Color(0xFFCCFF00))),
      _DashboardModuleSpec(label: 'HR Management', routeName: '/hrManagement', icon: Icons.people_alt, span: 1, heightFactor: 0.96, variant: _ModuleTileVariant.square, tintColor: tint(4, const Color(0xFFCCFF00))),
      _DashboardModuleSpec(label: 'CRM Management', routeName: '/crmManagement', icon: Icons.contact_support, span: 1, heightFactor: 0.96, variant: _ModuleTileVariant.square, tintColor: tint(5, const Color(0xFFCCFF00))),
      _DashboardModuleSpec(label: 'KPI / Analytics', routeName: '/kpi/dashboard', icon: Icons.analytics, span: 2, heightFactor: 1.42, variant: _ModuleTileVariant.tall, tintColor: tint(6, const Color(0xFFCCFF00))),
      _DashboardModuleSpec(label: 'Organization Settings', routeName: '/erp/settings', icon: Icons.business, span: 1, heightFactor: 0.96, variant: _ModuleTileVariant.square, tintColor: tint(7, const Color(0xFFCCFF00))),
    ];
  }
}

class _DashboardModuleSpec {
  final String label;
  final String routeName;
  final IconData icon;
  final int span;
  final double heightFactor;
  final _ModuleTileVariant variant;
  final Color tintColor;

  const _DashboardModuleSpec({
    required this.label,
    required this.routeName,
    required this.icon,
    required this.span,
    required this.heightFactor,
    required this.variant,
    required this.tintColor,
  });
}

enum _ModuleTileVariant { square, capsule, tall }

class _ModuleTile extends StatelessWidget {
  final _DashboardModuleSpec spec;
  final DashboardTheme? theme;

  const _ModuleTile({
    required this.spec,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = theme?.isDarkMode ?? false;
    final baseTint = isDark ? (theme?.accentColor ?? const Color(0xFFCCFF00)) : spec.tintColor;
    final iconTint = isDark ? baseTint : Color.lerp(spec.tintColor, Colors.black, 0.18)!;
    final textColor = isDark ? Colors.white : const Color(0xFF1D2733);
    final radius = switch (spec.variant) {
      _ModuleTileVariant.square => 30.0,
      _ModuleTileVariant.capsule => 999.0,
      _ModuleTileVariant.tall => 36.0,
    };
    final isCapsule = spec.variant == _ModuleTileVariant.capsule;

    return GlassCard(
      section: GlassSection.card,
      tintColor: spec.tintColor,
      borderRadius: radius,
      padding: EdgeInsets.zero,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: () => Navigator.of(context).pushNamed(spec.routeName),
          borderRadius: BorderRadius.circular(radius),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: isCapsule ? 16 : 12,
              vertical: isCapsule ? 12 : 12,
            ),
            child: Stack(
              children: [
                Positioned(
                  right: isCapsule ? -22 : -18,
                  top: isCapsule ? -18 : -12,
                  child: Container(
                    width: isCapsule ? 72 : 58,
                    height: isCapsule ? 72 : 58,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          spec.tintColor.withOpacity(isDark ? 0.10 : 0.20),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
                if (isCapsule)
                  Row(
                    children: [
                      _IconBubble(icon: spec.icon, color: iconTint, isDark: isDark, variant: spec.variant),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              spec.label,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                fontSize: 12.4,
                                fontWeight: FontWeight.w700,
                                color: textColor,
                                height: 1.08,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  )
                else
                  Positioned.fill(
                    child: Column(
                      children: [
                        const Spacer(flex: 3),
                        _IconBubble(icon: spec.icon, color: iconTint, isDark: isDark, variant: spec.variant),
                        const Spacer(flex: 1),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          child: Text(
                            spec.label,
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                              fontSize: spec.variant == _ModuleTileVariant.tall ? 12.9 : 12.7,
                              fontWeight: FontWeight.w600,
                              color: textColor,
                              height: 1.12,
                            ),
                          ),
                        ),
                        const Spacer(flex: 3),
                      ],
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

class _IconBubble extends StatelessWidget {
  final IconData icon;
  final Color color;
  final bool isDark;
  final _ModuleTileVariant variant;

  const _IconBubble({
    required this.icon,
    required this.color,
    required this.isDark,
    required this.variant,
  });

  @override
  Widget build(BuildContext context) {
    final size = switch (variant) {
      _ModuleTileVariant.square => 48.0,
      _ModuleTileVariant.capsule => 40.0,
      _ModuleTileVariant.tall => 50.0,
    };

    final iconSize = switch (variant) {
      _ModuleTileVariant.square => 23.0,
      _ModuleTileVariant.capsule => 20.0,
      _ModuleTileVariant.tall => 23.0,
    };

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withOpacity(isDark ? 0.7 : 0.35),
            color.withOpacity(isDark ? 0.95 : 0.55),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(isDark ? 0.28 : 0.18),
            blurRadius: 16,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Icon(icon, size: iconSize, color: isDark ? const Color(0xFF0F0F0F) : Colors.white),
    );
  }
}
