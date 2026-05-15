import 'package:flutter/material.dart';
import '../../../../../core/constants/app_colors.dart';

class DashboardSearchFilterWidget extends StatelessWidget {
  final TextEditingController searchController;
  final String selectedStatusTab;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String> onTabSelected;

  const DashboardSearchFilterWidget({
    super.key,
    required this.searchController,
    required this.selectedStatusTab,
    required this.onSearchChanged,
    required this.onTabSelected,
  });

  @override
  Widget build(BuildContext context) {
    const tabs = [
      {'label': 'ทั้งหมด', 'value': 'all'},
      {'label': 'รอดำเนินการ', 'value': 'pending'},
      {'label': 'กำลังดำเนินการ', 'value': 'in_progress'},
      {'label': 'เสร็จสิ้น', 'value': 'completed'},
    ];

    return Container(
      color: AppColors.background,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        children: [
          // Search bar
          Container(
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: TextField(
              controller: searchController,
              onChanged: onSearchChanged,
              style: const TextStyle(fontSize: 14, color: Colors.black87),
              decoration: InputDecoration(
                hintText: 'ค้นหาผู้ป่วย แพ็คเกจ บริเวณอาการ...',
                hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade400),
                prefixIcon: const Icon(
                  Icons.search,
                  color: AppColors.primary,
                  size: 20,
                ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          const SizedBox(height: 10),
          // Status tabs
          SizedBox(
            height: 32,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: tabs.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (ctx, i) {
                final tab = tabs[i];
                final active = selectedStatusTab == tab['value'];
                return GestureDetector(
                  onTap: () {
                    onTabSelected(tab['value']!);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: active ? AppColors.primary : Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: active
                            ? AppColors.primary
                            : Colors.grey.shade300,
                      ),
                      boxShadow: active
                          ? [
                              BoxShadow(
                                color: AppColors.primary.withOpacity(0.3),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ]
                          : [],
                    ),
                    child: Text(
                      tab['label']!,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: active ? Colors.white : Colors.grey.shade600,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
