import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../features/erp/presentation/providers/organization_settings_provider.dart';
import '../features/erp/presentation/providers/dashboard_theme_provider.dart';
import '../features/erp/presentation/widgets/glass_card.dart';
import '../features/erp/data/models/dashboard_theme.dart';
import '../features/erp/data/models/dashboard_module_layout.dart';
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
                        professionId: orgState.settings?.professionId ?? '',
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
              professionIconName: org.professionIconName,
              professionColorHex: org.professionColorHex,
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
  final String? professionIconName;
  final String? professionColorHex;

  const _LogoBadge({
    required this.isDark,
    required this.accentColor,
    this.child,
    this.imageUrl,
    this.professionIconName,
    this.professionColorHex,
  });

  @override
  Widget build(BuildContext context) {
    final fallbackIcon = _professionIconData(professionIconName);
    final fallbackColor = _parseHexColor(professionColorHex) ??
        (isDark ? accentColor : const Color(0xFF4F7DF3));

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
      child: imageUrl == null
          ? Center(
              child: child ?? Icon(fallbackIcon, size: 28, color: fallbackColor),
            )
          : null,
    );
  }

  static IconData _professionIconData(String? iconName) {
    switch (iconName) {
      case 'shopping_cart':
        return Icons.shopping_cart;
      case 'store':
        return Icons.store;
      case 'local_hospital':
        return Icons.local_hospital;
      case 'person':
        return Icons.person;
      case 'medical_services':
        return Icons.medical_services;
      case 'delivery_dining':
        return Icons.delivery_dining;
      case 'engineering':
        return Icons.engineering;
      case 'gavel':
        return Icons.gavel;
      case 'school':
        return Icons.school;
      case 'restaurant':
        return Icons.restaurant;
      case 'spa':
        return Icons.spa;
      case 'fitness_center':
        return Icons.fitness_center;
      default:
        return Icons.business;
    }
  }

  static Color? _parseHexColor(String? hex) {
    if (hex == null || hex.isEmpty) return null;
    try {
      final clean = hex.replaceFirst('#', '');
      if (clean.length == 6) return Color(int.parse('FF$clean', radix: 16));
      if (clean.length == 8) return Color(int.parse(clean, radix: 16));
    } catch (_) {}
    return null;
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
  final String professionId;

  const _DashboardModuleBoard({
    required this.width,
    required this.columns,
    required this.theme,
    required this.professionId,
  });

  @override
  Widget build(BuildContext context) {
    final layout = theme?.moduleLayoutJson != null
        ? DashboardModuleLayoutConfig.fromJson(theme!.moduleLayoutJson).normalize()
        : DashboardModuleLayoutConfig.defaultLayout();
    final spacing = columns >= 3 ? 11.0 : 10.0;
    // The group card adds horizontal padding (14 on each side via GlassCard).
    // Use the actual inner width so cards can still fit 2-4 columns correctly.
    final innerWidth = width - 28;
    final tileWidth = (innerWidth - (spacing * (columns - 1))) / columns;

    final groupedModules = _groupModules(layout);

    return Column(
      children: [
        for (final entry in groupedModules)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: _GroupSection(
              title: entry.group.title,
              tintColor: entry.group.tintColor,
              titleAccentColor: entry.group.titleColor,
              count: entry.modules.length,
              child: Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: entry.modules.map((module) {
                  final spec = _buildSpec(module, entry.group.tintColor);
                  final span = spec.span.clamp(1, columns);
                  final itemWidth = span == columns ? innerWidth : (tileWidth * span) + (spacing * (span - 1));
                  final itemHeight = tileWidth * spec.heightFactor;
                  return SizedBox(
                    width: itemWidth,
                    height: itemHeight,
                    child: _ModuleTile(spec: spec, theme: theme, professionId: professionId),
                  );
                }).toList(),
              ),
            ),
          ),
      ],
    );
  }

  List<_DashboardGroupSection> _groupModules(DashboardModuleLayoutConfig layout) {
    final assigned = <String>{};
    final sections = <_DashboardGroupSection>[];

    for (final group in layout.groups) {
      final modules = group.moduleIds
          .map((id) => dashboardModuleById(id))
          .whereType<DashboardModuleDefinition>()
          .toList();
      assigned.addAll(group.moduleIds);
      if (modules.isNotEmpty) {
        sections.add(_DashboardGroupSection(group: group, modules: modules));
      }
    }

    final fallback = dashboardModuleDefinitions.where((module) => !assigned.contains(module.id)).toList();
    if (fallback.isNotEmpty) {
      sections.add(
        _DashboardGroupSection(
          group: DashboardModuleGroupConfig(
            id: 'ungrouped',
            title: 'ไม่มีกลุ่ม',
            colorHex: '#D9E8FF',
            moduleIds: fallback.map((m) => m.id).toList(),
          ),
          modules: fallback,
        ),
      );
    }

    return sections;
  }

  _DashboardModuleSpec _buildSpec(DashboardModuleDefinition module, Color? tintColor) {
    return _DashboardModuleSpec(
      label: module.label,
      thaiLabel: module.thaiLabel,
      routeName: module.routeName,
      icon: module.icon,
      span: module.span,
      heightFactor: module.heightFactor,
      variant: _mapVariant(module.variant),
      tintColor: tintColor,
    );
  }

  _ModuleTileVariant _mapVariant(DashboardModuleTileVariant variant) {
    return switch (variant) {
      DashboardModuleTileVariant.square => _ModuleTileVariant.square,
      DashboardModuleTileVariant.capsule => _ModuleTileVariant.capsule,
      DashboardModuleTileVariant.tall => _ModuleTileVariant.tall,
    };
  }
}

class _DashboardGroupSection {
  final DashboardModuleGroupConfig group;
  final List<DashboardModuleDefinition> modules;

  const _DashboardGroupSection({required this.group, required this.modules});
}

class _GroupSection extends StatelessWidget {
  final String title;
  final Color? tintColor;
  final Color? titleAccentColor;
  final int count;
  final Widget child;

  const _GroupSection({
    required this.title,
    required this.tintColor,
    this.titleAccentColor,
    required this.count,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveTitleColor = titleAccentColor ?? const Color(0xFF94A3B8);
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: effectiveTitleColor, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: effectiveTitleColor.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '$count',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: effectiveTitleColor),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        child,
      ],
    );

    if (titleAccentColor == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: content,
      );
    }

    return GlassCard(
      section: GlassSection.card,
      tintColor: tintColor,
      borderRadius: 22,
      padding: const EdgeInsets.all(14),
      child: content,
    );
  }
}

class _DashboardModuleSpec {
  final String label;
  final String thaiLabel;
  final String routeName;
  final IconData icon;
  final int span;
  final double heightFactor;
  final _ModuleTileVariant variant;
  final Color? tintColor;

  const _DashboardModuleSpec({
    required this.label,
    required this.thaiLabel,
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
  final String professionId;

  const _ModuleTile({
    required this.spec,
    required this.theme,
    required this.professionId,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = theme?.isDarkMode ?? false;
    final baseTint = isDark ? (theme?.accentColor ?? const Color(0xFFCCFF00)) : (spec.tintColor ?? const Color(0xFF94A3B8));
    final iconTint = isDark ? baseTint : Color.lerp(baseTint, Colors.black, 0.18)!;
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
          onTap: () => Navigator.of(context).pushNamed(
            spec.routeName,
            arguments: {'professionId': professionId},
          ),
          borderRadius: BorderRadius.circular(radius),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: isCapsule ? 16 : 12,
              vertical: isCapsule ? 12 : 12,
            ),
            child: Stack(
              children: [
                if (spec.tintColor != null)
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
                            spec.tintColor!.withOpacity(isDark ? 0.10 : 0.20),
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
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                fontSize: 12.4,
                                fontWeight: FontWeight.w700,
                                color: textColor,
                                height: 1.08,
                              ),
                            ),
                            const SizedBox(height: 1),
                            Text(
                              spec.thaiLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w400,
                                color: textColor.withOpacity(0.55),
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
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                spec.label,
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.inter(
                                  fontSize: spec.variant == _ModuleTileVariant.tall ? 11.8 : 11.6,
                                  fontWeight: FontWeight.w600,
                                  color: textColor,
                                  height: 1.12,
                                ),
                              ),
                              const SizedBox(height: 1),
                              Text(
                                spec.thaiLabel,
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.inter(
                                  fontSize: spec.variant == _ModuleTileVariant.tall ? 10.4 : 10.2,
                                  fontWeight: FontWeight.w400,
                                  color: textColor.withOpacity(0.55),
                                  height: 1.12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Spacer(flex: 2),
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
