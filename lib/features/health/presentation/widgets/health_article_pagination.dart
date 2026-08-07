import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';

/// Pagination section for the health article comments.
class HealthArticlePagination extends StatelessWidget {
  final int currentPage;
  final int totalRootComments;
  final int totalComments;
  final ValueChanged<int> onPageChanged;

  const HealthArticlePagination({
    super.key,
    required this.currentPage,
    required this.totalRootComments,
    required this.totalComments,
    required this.onPageChanged,
  });

  @override
  Widget build(BuildContext context) {
    final int totalPages = (totalRootComments / 10).ceil();
    if (totalPages <= 1) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
      child: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildPageIcon(
                  Icons.first_page,
                  currentPage > 1,
                  () => onPageChanged(1),
                ),
                _buildPageIcon(
                  Icons.chevron_left,
                  currentPage > 1,
                  () => onPageChanged(currentPage - 1),
                ),
                _buildPageButton('1', currentPage == 1, () => onPageChanged(1)),
                if (currentPage > 3) _buildPageButton('...', false, null),
                ...List.generate(3, (index) {
                  final page = currentPage - 1 + index;
                  if (page <= 1 || page >= totalPages)
                    return const SizedBox.shrink();
                  return _buildPageButton(
                    page.toString(),
                    currentPage == page,
                    () => onPageChanged(page),
                  );
                }),
                if (currentPage < totalPages - 2)
                  _buildPageButton('...', false, null),
                if (totalPages > 1)
                  _buildPageButton(
                    totalPages.toString(),
                    currentPage == totalPages,
                    () => onPageChanged(totalPages),
                  ),
                _buildPageIcon(
                  Icons.chevron_right,
                  currentPage < totalPages,
                  () => onPageChanged(currentPage + 1),
                ),
                _buildPageIcon(
                  Icons.last_page,
                  currentPage < totalPages,
                  () => onPageChanged(totalPages),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'แสดง ${(currentPage - 1) * 10 + 1}-${(currentPage * 10).clamp(0, totalRootComments)} จากทั้งหมด $totalRootComments หัวข้อสนทนา ($totalComments ความคิดเห็น)',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
              const SizedBox(width: 16),
              Container(
                height: 32,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white30),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<int>(
                    value: currentPage,
                    dropdownColor: const Color(0xFF5D9CDB),
                    items: List.generate(totalPages, (index) => index + 1)
                        .map(
                          (page) => DropdownMenuItem(
                            value: page,
                            child: Text(
                              'หน้า $page',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value != null) onPageChanged(value);
                    },
                    icon: const Icon(
                      Icons.arrow_drop_down,
                      size: 16,
                      color: Colors.white,
                    ),
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPageIcon(IconData icon, bool enabled, VoidCallback onTap) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade200),
              borderRadius: BorderRadius.circular(12),
              color: enabled ? Colors.white : Colors.grey.shade50,
            ),
            child: Icon(
              icon,
              size: 20,
              color: enabled ? Colors.black87 : Colors.grey.shade300,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPageButton(String text, bool isActive, VoidCallback? onTap) {
    final bool isEllipsis = text == '...';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isEllipsis ? null : onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isActive ? AppColors.primary : Colors.transparent,
              border: isActive
                  ? null
                  : Border.all(
                      color: isEllipsis
                          ? Colors.transparent
                          : Colors.grey.shade200,
                    ),
              borderRadius: BorderRadius.circular(12),
              boxShadow: isActive
                  ? [
                      BoxShadow(
                        color: AppColors.primary.withOpacity(0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : null,
            ),
            child: Text(
              text,
              style: TextStyle(
                color: isActive
                    ? Colors.white
                    : (isEllipsis ? Colors.grey : Colors.black87),
                fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                fontSize: 13,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
