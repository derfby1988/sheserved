import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../data/models/dashboard_theme.dart';
import '../providers/dashboard_theme_provider.dart';
import '../widgets/glass_opacity_slider.dart';
import '../widgets/glass_preview_box.dart';
import '../widgets/glass_card.dart';

/// หน้า Settings — Glassmorphism Tab
/// ปรับระดับความโปร่งใส (opacity) แยกตามส่วน + Blur Intensity
/// Redesigned with natural pastel glassmorphism aesthetic
class GlassmorphismSettingsPage extends ConsumerWidget {
  const GlassmorphismSettingsPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(dashboardThemeProvider);
    final notifier = ref.read(dashboardThemeProvider.notifier);
    final theme = state.theme;

    if (state.isInitialLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final isDark = theme?.isDarkMode ?? false;
    final bgColors = isDark
        ? [const Color(0xFF0F0F0F), const Color(0xFF1A1A1A)]
        : [const Color(0xFFDFF8FF), const Color(0xFFDFF7E8), const Color(0xFFF4E4FB)];
    final textPrimary = isDark ? Colors.white : const Color(0xFF1D2733);
    final textSecondary = isDark ? Colors.white70 : const Color(0xFF617181);

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F0F0F) : const Color(0xFFE8F6FF),
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(
          'ตั้งค่าความโปร่งใส Dashboard',
          style: GoogleFonts.inter(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: textPrimary,
          ),
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: textPrimary),
      ),
      body: Stack(
        children: [
          // Pastel gradient background
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: bgColors,
                stops: isDark ? null : const [0.0, 0.5, 1.0],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          // Soft backdrop blobs (light mode only)
          if (!isDark) ...[
            Positioned(
              top: -60,
              left: -30,
              child: _BackdropBlob(color: const Color(0xFFBFE7FF), size: 180),
            ),
            Positioned(
              top: 80,
              right: -50,
              child: _BackdropBlob(color: const Color(0xFFCFEFBA), size: 200),
            ),
            Positioned(
              bottom: -70,
              left: 40,
              child: _BackdropBlob(color: const Color(0xFFF0D6FF), size: 190),
            ),
          ],
          // Content
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title card
                  GlassCard(
                    section: GlassSection.card,
                    tintColor: const Color(0xFFBFE7FF),
                    borderRadius: 24,
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'ระดับความโปร่งใส',
                          style: GoogleFonts.inter(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'ปรับความโปร่งใสแยกตามส่วน (0% = ทึบ, 50% = โปร่งสุด)',
                          style: GoogleFonts.inter(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500,
                            color: textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Opacity Sliders inside a glass card
                  GlassCard(
                    section: GlassSection.card,
                    tintColor: const Color(0xFFF0E7B4),
                    borderRadius: 24,
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      children: [
                        const GlassOpacitySlider(
                          label: 'Sidebar (แถบนำทางด้านซ้าย)',
                          section: GlassSection.sidebar,
                        ),
                        const SizedBox(height: 12),
                        const Divider(height: 1, color: Color(0x1A000000)),
                        const SizedBox(height: 12),
                        const GlassOpacitySlider(
                          label: 'Module Cards (การ์ดโมดูล)',
                          section: GlassSection.card,
                        ),
                        const SizedBox(height: 12),
                        const Divider(height: 1, color: Color(0x1A000000)),
                        const SizedBox(height: 12),
                        const GlassOpacitySlider(
                          label: 'Dialog / Popup (หน้าต่างแจ้งเตือน)',
                          section: GlassSection.dialog,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Blur Slider inside a glass card
                  GlassCard(
                    section: GlassSection.card,
                    tintColor: const Color(0xFFBDEBDB),
                    borderRadius: 24,
                    padding: const EdgeInsets.all(18),
                    child: const GlassBlurSlider(),
                  ),
                  const SizedBox(height: 20),

                  // Preview
                  Text(
                    'ตัวอย่างแสดงผล',
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: textPrimary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const GlassPreviewBox(),
                  const SizedBox(height: 24),

                  // Actions — glass capsule buttons
                  Row(
                    children: [
                      Expanded(
                        child: _GlassActionButton(
                          label: 'บันทึก',
                          icon: Icons.save,
                          tintColor: const Color(0xFF4F7DF3),
                          isDark: isDark,
                          isLoading: state.isSaving,
                          onTap: () async {
                            final success = await notifier.saveGlassSettings();
                            if (success && context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('บันทึกสำเร็จ'),
                                  backgroundColor: Colors.green,
                                ),
                              );
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _GlassActionButton(
                          label: 'คืนค่าเริ่มต้น',
                          icon: Icons.restore,
                          tintColor: const Color(0xFFFF8A65),
                          isDark: isDark,
                          onTap: () => notifier.resetGlassSettings(),
                        ),
                      ),
                    ],
                  ),

                  if (state.errorMessage != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: GlassCard(
                        section: GlassSection.card,
                        tintColor: const Color(0xFFFFE5E8),
                        borderRadius: 16,
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          children: [
                            Icon(Icons.error_outline,
                                color: Colors.red.shade700, size: 20),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                state.errorMessage!,
                                style: GoogleFonts.inter(
                                  color: Colors.red.shade800,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Soft blurred backdrop blob for background ambiance
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
          color: color.withOpacity(0.45),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.20),
              blurRadius: 70,
              spreadRadius: 25,
            ),
          ],
        ),
      ),
    );
  }
}

/// Glass-styled action button with pastel tint
class _GlassActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color tintColor;
  final bool isDark;
  final bool isLoading;
  final VoidCallback? onTap;

  const _GlassActionButton({
    required this.label,
    required this.icon,
    required this.tintColor,
    required this.isDark,
    this.isLoading = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = isDark ? Colors.white : const Color(0xFF1D2733);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: isLoading ? null : onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                tintColor.withOpacity(isDark ? 0.35 : 0.22),
                tintColor.withOpacity(isDark ? 0.22 : 0.12),
              ],
            ),
            border: Border.all(
              color: Colors.white.withOpacity(isDark ? 0.25 : 0.55),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: tintColor.withOpacity(isDark ? 0.25 : 0.15),
                blurRadius: 18,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Center(
            child: isLoading
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: textColor,
                    ),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, size: 18, color: textColor),
                      const SizedBox(width: 8),
                      Text(
                        label,
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: textColor,
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
