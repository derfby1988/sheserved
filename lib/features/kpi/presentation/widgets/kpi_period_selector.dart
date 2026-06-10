import 'package:flutter/material.dart';

class KpiPeriodSelector extends StatelessWidget {
  final String selectedPeriod;
  final ValueChanged<String> onPeriodChanged;
  final String selectedTargetType;
  final ValueChanged<String> onTargetTypeChanged;

  const KpiPeriodSelector({
    super.key,
    required this.selectedPeriod,
    required this.onPeriodChanged,
    required this.selectedTargetType,
    required this.onTargetTypeChanged,
  });

  final List<String> _periods = const ['daily', 'weekly', 'monthly', 'quarterly', 'yearly'];
  final List<String> _targetTypes = const [
    'revenue',
    'net_profit',
    'consultations',
    'appointments',
  ];

  String _periodLabel(String period) {
    switch (period) {
      case 'daily':
        return 'รายวัน';
      case 'weekly':
        return 'รายสัปดาห์';
      case 'monthly':
        return 'รายเดือน';
      case 'quarterly':
        return 'รายไตรมาส';
      case 'yearly':
        return 'รายปี';
      default:
        return period;
    }
  }

  String _targetTypeLabel(String type) {
    switch (type) {
      case 'revenue':
        return 'ยอดขาย';
      case 'net_profit':
        return 'กำไรสุทธิ';
      case 'consultations':
        return 'การปรึกษา';
      case 'appointments':
        return 'นัดหมาย';
      default:
        return type;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'ตัวกรอง',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 12),
            // Target Type
            Text(
              'ประเภทเป้าหมาย',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey[600],
                  ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _targetTypes.map((type) {
                final isSelected = type == selectedTargetType;
                return ChoiceChip(
                  label: Text(_targetTypeLabel(type)),
                  selected: isSelected,
                  onSelected: (_) => onTargetTypeChanged(type),
                  selectedColor: Theme.of(context).colorScheme.primary,
                  labelStyle: TextStyle(
                    color: isSelected
                        ? Colors.white
                        : Colors.grey[700],
                    fontSize: 13,
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            // Period Type
            Text(
              'ช่วงเวลา',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey[600],
                  ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _periods.map((period) {
                final isSelected = period == selectedPeriod;
                return ChoiceChip(
                  label: Text(_periodLabel(period)),
                  selected: isSelected,
                  onSelected: (_) => onPeriodChanged(period),
                  selectedColor: Theme.of(context).colorScheme.secondary,
                  labelStyle: TextStyle(
                    color: isSelected
                        ? Colors.white
                        : Colors.grey[700],
                    fontSize: 13,
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}
