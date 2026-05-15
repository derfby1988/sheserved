import re
import os

file_path = '/Users/dave_macmini/sheserved/lib/features/consultation/presentation/pages/health_program_request_dashboard.dart'
chip_path = '/Users/dave_macmini/sheserved/lib/features/consultation/presentation/widgets/dashboard/dashboard_stat_chip.dart'

with open(file_path, 'r', encoding='utf-8') as f:
    content = f.read()

chip_widget_code = """import 'package:flutter/material.dart';

class DashboardStatChipWidget extends StatelessWidget {
  final String label;
  final int count;
  final IconData icon;
  final Color accent;

  const DashboardStatChipWidget({
    super.key,
    required this.label,
    required this.count,
    required this.icon,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.15),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withOpacity(0.25)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: accent, size: 16),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                '$count',
                style: TextStyle(
                  color: accent,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
"""

with open(chip_path, 'w', encoding='utf-8') as f:
    f.write(chip_widget_code)

# Replace _statChip usage in the main file
content = content.replace("import '../widgets/dashboard/availability_toggle_button.dart';", "import '../widgets/dashboard/availability_toggle_button.dart';\nimport '../widgets/dashboard/dashboard_stat_chip.dart';")
content = content.replace("_statChip('ทั้งหมด', _total, Icons.list_alt, Colors.white)", "DashboardStatChipWidget(label: 'ทั้งหมด', count: _total, icon: Icons.list_alt, accent: Colors.white)")
content = content.replace("_statChip(\n                      'รอดำเนินการ',\n                      _pending,\n                      Icons.pending_outlined,\n                      AppColors.warning,\n                    )", "DashboardStatChipWidget(label: 'รอดำเนินการ', count: _pending, icon: Icons.pending_outlined, accent: AppColors.warning)")
content = content.replace("_statChip(\n                      'กำลังดำเนินการ',\n                      _inProgress,\n                      Icons.forum_outlined,\n                      AppColors.info,\n                    )", "DashboardStatChipWidget(label: 'กำลังดำเนินการ', count: _inProgress, icon: Icons.forum_outlined, accent: AppColors.info)")
content = content.replace("_statChip(\n                      'เสร็จสิ้น',\n                      _completed,\n                      Icons.check_circle_outline,\n                      AppColors.success,\n                    )", "DashboardStatChipWidget(label: 'เสร็จสิ้น', count: _completed, icon: Icons.check_circle_outline, accent: AppColors.success)")

# Remove the _statChip method
method_pattern = re.compile(r'  Widget _statChip\(String label, int count, IconData icon, Color accent\) \{.*?\n  \}\n', re.DOTALL)
content = method_pattern.sub('\n', content)

with open(file_path, 'w', encoding='utf-8') as f:
    f.write(content)

print("Extracted DashboardStatChipWidget successfully.")
