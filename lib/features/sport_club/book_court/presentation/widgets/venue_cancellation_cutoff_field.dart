import 'package:flutter/material.dart';
import 'package:sheserved/shared/widgets/neumorphic/neumorphic.dart';

/// Preset cancellation cutoffs (minutes) offered by the venue terms editors:
/// 0/15/30/45/60 minutes then 1/2/5/12/24/36 hours.
const List<int> kVenueCancellationCutoffPresets = <int>[
  0,
  15,
  30,
  45,
  60,
  120,
  300,
  720,
  1440,
  2160,
];

/// Human-readable cutoff label used by the slider readout and value badge.
String venueCancellationCutoffLabel(int minutes) {
  if (minutes <= 0) return 'ไม่จำกัด';
  if (minutes < 60) return '$minutes นาที';
  if (minutes % 60 == 0) return '${minutes ~/ 60} ชม.';
  return '$minutes นาที';
}

/// Slider options: the presets plus [currentMinutes] when an already published
/// version carries a value outside the preset list — republishing must not
/// silently rewrite a cutoff that bookings are already snapshotted against.
List<int> venueCancellationCutoffOptions(int? currentMinutes) {
  final options = List<int>.of(kVenueCancellationCutoffPresets);
  if (currentMinutes != null &&
      currentMinutes >= 0 &&
      !options.contains(currentMinutes)) {
    options.add(currentMinutes);
    options.sort();
  }
  return options;
}

/// Preset picker for "ยกเลิกล่วงหน้าได้ไม่เกิน" — discrete slider styled like
/// the coach filter rating control, with the selected label shown alongside.
class VenueCancellationCutoffField extends StatelessWidget {
  const VenueCancellationCutoffField({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
    this.title = 'ยกเลิกล่วงหน้าได้ไม่เกิน',
    this.helperText = 'ผู้จองยกเลิกได้ฟรีจนถึงเวลานี้ก่อนเริ่มจอง',
  });

  final int value;
  final List<int> options;
  final ValueChanged<int> onChanged;
  final String title;
  final String helperText;

  @override
  Widget build(BuildContext context) {
    final index = options.indexOf(value);
    final selectedIndex = (index < 0 ? 0 : index).toDouble();
    final label = venueCancellationCutoffLabel(
      index < 0 ? options.first : value,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: NeumorphicTheme.sectionLabel),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: options.length < 2
                  ? const SizedBox.shrink()
                  : NeumorphicSlider(
                      value: selectedIndex,
                      min: 0,
                      max: (options.length - 1).toDouble(),
                      divisions: options.length - 1,
                      label: label,
                      semanticFormatterCallback: (v) =>
                          venueCancellationCutoffLabel(
                            options[v.round().clamp(0, options.length - 1)],
                          ),
                      onChanged: (v) => onChanged(
                        options[v.round().clamp(0, options.length - 1)],
                      ),
                    ),
            ),
            SizedBox(
              width: 62,
              child: Text(
                label,
                textAlign: TextAlign.right,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: NeumorphicTheme.textSecondary,
                ),
              ),
            ),
          ],
        ),
        if (helperText.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            helperText,
            style: const TextStyle(
              fontSize: 12,
              color: NeumorphicTheme.textSecondary,
            ),
          ),
        ],
      ],
    );
  }
}
