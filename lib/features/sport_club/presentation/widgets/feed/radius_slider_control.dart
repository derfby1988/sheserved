import 'package:flutter/material.dart';
import 'package:sheserved/core/constants/app_colors.dart';

/// Slider for adjusting the search radius (1–50 กม.) with a reset
/// button. Renders nothing when [visible] is false.
class RadiusSliderControl extends StatelessWidget {
  final bool visible;
  final double? radiusKm;
  final void Function(double value) onChanged;
  final void Function(double value) onChangeEnd;
  final VoidCallback onReset;

  const RadiusSliderControl({
    super.key,
    required this.visible,
    required this.radiusKm,
    required this.onChanged,
    required this.onChangeEnd,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    if (!visible) {
      return const SizedBox.shrink();
    }
    final radius = (radiusKm ?? 10).clamp(1, 50).toDouble();
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 2),
      child: Row(
        children: [
          const Icon(
            Icons.near_me_rounded,
            size: 18,
            color: AppColors.primaryDark,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Slider(
              value: radius,
              min: 1,
              max: 50,
              divisions: 49,
              label: '${radius.round()} กม.',
              activeColor: AppColors.primaryDark,
              onChanged: onChanged,
              onChangeEnd: onChangeEnd,
            ),
          ),
          SizedBox(
            width: 48,
            child: Text(
              '${radius.round()} กม.',
              textAlign: TextAlign.end,
              style: const TextStyle(
                color: AppColors.primaryDark,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          IconButton(
            tooltip: 'รีเซ็ตรัศมีเป็น 10 กิโลเมตร',
            visualDensity: VisualDensity.compact,
            onPressed: onReset,
            icon: const Icon(Icons.close_rounded, size: 18),
          ),
        ],
      ),
    );
  }
}
