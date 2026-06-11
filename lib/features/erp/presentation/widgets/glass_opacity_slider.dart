import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/dashboard_theme.dart';
import '../providers/dashboard_theme_provider.dart';

/// Slider ปรับระดับความโปร่งใส (Opacity) แยกตามส่วน
class GlassOpacitySlider extends ConsumerWidget {
  final String label;
  final GlassSection section;

  const GlassOpacitySlider({
    Key? key,
    required this.label,
    required this.section,
  }) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(dashboardThemeProvider).theme;
    if (theme == null) return const SizedBox.shrink();

    final currentOpacity = theme.getOpacityFor(section);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            const Text('ทึบ', style: TextStyle(fontSize: 11, color: Colors.grey)),
            Expanded(
              child: Slider(
                value: currentOpacity,
                min: 0.0,
                max: 0.50,
                divisions: 50,
                label: '${(currentOpacity * 100).toInt()}%',
                activeColor: theme.accentColor,
                inactiveColor: theme.accentColor.withOpacity(0.2),
                onChanged: (value) {
                  ref.read(dashboardThemeProvider.notifier).setOpacity(section, value);
                },
              ),
            ),
            const Text('โปร่ง', style: TextStyle(fontSize: 11, color: Colors.grey)),
          ],
        ),
        Align(
          alignment: Alignment.centerRight,
          child: Text(
            '${(currentOpacity * 100).toInt()}%',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: theme.textPrimaryColor,
            ),
          ),
        ),
      ],
    );
  }
}

/// Slider ปรับ Blur Intensity (ใช้ร่วมกันทุกส่วน)
class GlassBlurSlider extends ConsumerWidget {
  const GlassBlurSlider({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(dashboardThemeProvider).theme;
    if (theme == null) return const SizedBox.shrink();

    final currentBlur = theme.glassBlurLevel;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Blur Intensity (ทุกส่วน)',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            const Text('เบา', style: TextStyle(fontSize: 11, color: Colors.grey)),
            Expanded(
              child: Slider(
                value: currentBlur.toDouble(),
                min: 2,
                max: 20,
                divisions: 18,
                label: '${currentBlur}px',
                activeColor: theme.accentColor,
                inactiveColor: theme.accentColor.withOpacity(0.2),
                onChanged: (value) {
                  ref.read(dashboardThemeProvider.notifier).setBlurLevel(value.toInt());
                },
              ),
            ),
            const Text('หนัก', style: TextStyle(fontSize: 11, color: Colors.grey)),
          ],
        ),
        Align(
          alignment: Alignment.centerRight,
          child: Text(
            '${currentBlur}px',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: theme.textPrimaryColor,
            ),
          ),
        ),
      ],
    );
  }
}
