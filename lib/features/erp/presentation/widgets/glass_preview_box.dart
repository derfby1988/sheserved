import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/dashboard_theme.dart';
import '../providers/dashboard_theme_provider.dart';
import 'glass_card.dart';

/// Preview Box แสดงตัวอย่าง Glassmorphism แบบ real-time
/// อัปเดตทันทีเมื่อปรับ slider
class GlassPreviewBox extends ConsumerWidget {
  const GlassPreviewBox({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(dashboardThemeProvider).theme;
    final isDark = theme?.isDarkMode ?? false;
    final backgroundGradient = isDark
        ? [const Color(0xFF0F0F0F), const Color(0xFF1A1A1A)]
        : [const Color(0xFFDFF8FF), const Color(0xFFDFF7E8), const Color(0xFFF4E4FB)];

    return Container(
      height: 190,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          colors: backgroundGradient,
          stops: isDark ? null : const [0.0, 0.5, 1.0],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        children: [
          if (!isDark) ...[
            Positioned(
              top: -18,
              left: -12,
              child: _GlowBlob(color: const Color(0xFFBFE7FF), size: 90),
            ),
            Positioned(
              bottom: -16,
              right: 6,
              child: _GlowBlob(color: const Color(0xFFCFEFBA), size: 110),
            ),
          ],
          // Preview: Sidebar mini
          Positioned(
            left: 12,
            top: 12,
            bottom: 12,
            child: GlassCard(
              section: GlassSection.sidebar,
              tintColor: const Color(0xFFBFE7FF),
              borderRadius: 22,
              child: SizedBox(
                width: 56,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.menu, color: theme?.textPrimaryColor ?? Colors.white, size: 20),
                    const SizedBox(height: 8),
                    Container(width: 24, height: 5, decoration: BoxDecoration(color: theme?.accentColor ?? Colors.amber, borderRadius: BorderRadius.circular(999))),
                    const SizedBox(height: 5),
                    Container(width: 24, height: 5, decoration: BoxDecoration(color: theme?.accentColor ?? Colors.amber, borderRadius: BorderRadius.circular(999))),
                    const SizedBox(height: 5),
                    Container(width: 24, height: 5, decoration: BoxDecoration(color: theme?.accentColor ?? Colors.amber, borderRadius: BorderRadius.circular(999))),
                  ],
                ),
              ),
            ),
          ),
          // Preview: Module Card (square)
          Positioned(
            left: 80,
            top: 12,
            right: 12,
            height: 74,
            child: GlassCard(
              section: GlassSection.card,
              tintColor: const Color(0xFFBFE7FF),
              borderRadius: 30,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _PreviewBubble(icon: Icons.point_of_sale, color: theme?.accentColor ?? const Color(0xFFCCFF00)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'POS Management',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: theme?.textPrimaryColor ?? Colors.white,
                        fontSize: 12.7,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Preview: Capsule card
          Positioned(
            left: 80,
            top: 94,
            right: 12,
            height: 72,
            child: GlassCard(
              section: GlassSection.card,
              tintColor: const Color(0xFFF7C9A9),
              borderRadius: 999,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _PreviewBubble(icon: Icons.shopping_bag, color: theme?.accentColor ?? const Color(0xFFCCFF00)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Procurement Capsule',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: theme?.textPrimaryColor ?? Colors.white,
                        fontSize: 12.4,
                        fontWeight: FontWeight.w700,
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

class _GlowBlob extends StatelessWidget {
  final Color color;
  final double size;

  const _GlowBlob({required this.color, required this.size});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withOpacity(0.35),
          boxShadow: [
            BoxShadow(color: color.withOpacity(0.20), blurRadius: 48, spreadRadius: 20),
          ],
        ),
      ),
    );
  }
}

class _PreviewBubble extends StatelessWidget {
  final IconData icon;
  final Color color;

  const _PreviewBubble({required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [color.withOpacity(0.35), color.withOpacity(0.65)],
        ),
      ),
      child: Icon(icon, size: 16, color: Colors.white),
    );
  }
}
