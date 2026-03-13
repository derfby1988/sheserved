import 'package:flutter/material.dart';
import '../../widgets/glassmorphism_button.dart';

class BottomTabsWidget extends StatelessWidget {
  final int selectedTab;
  final Animation<double> blinkAnimation;
  final bool showThaiMhung;
  final Function(int) onTabSelected;
  final VoidCallback onEmergencyTabSelected;

  const BottomTabsWidget({
    super.key,
    required this.selectedTab,
    required this.blinkAnimation,
    this.showThaiMhung = true,
    required this.onTabSelected,
    required this.onEmergencyTabSelected,
  });

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final maxButtonSize = screenHeight * 0.1; // จำกัดขนาดไม่เกิน 10% ของจอ

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Live Tab
          if (showThaiMhung) ...[
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: maxButtonSize,
                    maxWidth: maxButtonSize,
                  ),
                  child: GlassTabButton(
                    label: 'ไทยมุง',
                    isActive: selectedTab == 0,
                    leading: AnimatedBuilder(
                      animation: blinkAnimation,
                      builder: (context, child) {
                        return Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Color.lerp(
                              Colors.red,
                              Colors.red.withValues(alpha: 0.3),
                              blinkAnimation.value,
                            ),
                          ),
                        );
                      },
                    ),
                    onTap: () => onTabSelected(0),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          // ความสัมพันธ์ Tab
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: maxButtonSize,
                  maxWidth: maxButtonSize,
                ),
                child: GlassTabButton(
                  label: 'เกี่ยวดอง',
                  isActive: selectedTab == 1,
                  onTap: () => onTabSelected(1),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // แจ้งเหตุ Tab
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: maxButtonSize,
                  maxWidth: maxButtonSize,
                ),
                child: GlassTabButton(
                  label: 'แจ้งเหตุ\nฉุกเฉิน',
                  isActive: selectedTab == 2,
                  trailing: Icon(
                    Icons.error_outline,
                    size: 18,
                    color: selectedTab == 2 ? Colors.red : Colors.grey,
                  ),
                  onTap: onEmergencyTabSelected,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
