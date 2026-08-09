import 'package:flutter/material.dart';
import '../../widgets/glassmorphism_button.dart';

class BottomTabsWidget extends StatelessWidget {
  final int selectedTab;
  final Animation<double> blinkAnimation;
  final bool showThaiMhung;
  final Function(int) onTabSelected;
  final VoidCallback onEmergencyTabSelected;
  final bool isChatVisible;
  final bool isEligibleResponder;
  final bool isThaiMhungReporting;
  final bool showEmergency;
  final int triageBadgeCount;
  final VoidCallback? onTriageTabSelected;

  const BottomTabsWidget({
    super.key,
    required this.selectedTab,
    required this.blinkAnimation,
    this.showThaiMhung = true,
    required this.onTabSelected,
    required this.onEmergencyTabSelected,
    this.isChatVisible = false,
    this.isEligibleResponder = false,
    this.isThaiMhungReporting = false,
    this.showEmergency = true,
    this.triageBadgeCount = 0,
    this.onTriageTabSelected,
  });

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width - 32; // หัก Padding ซ้าย-ขวา
    final maxButtonSize = screenHeight * 0.1; // จำกัดขนาดไม่เกิน 10% ของจอ
    
    int totalButtons = 0;
    if (showThaiMhung && !isThaiMhungReporting) totalButtons++;
    if (showThaiMhung && !(selectedTab == 2 || isThaiMhungReporting)) totalButtons++;
    if (showEmergency && !isThaiMhungReporting) totalButtons++;
    
    // คำนวณความกว้างของแต่ละช่อง (เมื่อไม่เปิดแชท ให้แบ่งเท่าๆ กัน)
    final double cellWidth = totalButtons > 0 ? screenWidth / totalButtons : screenWidth;
    
    // เมื่อเปิดแชท บีบให้ช่องกว้างเท่าปุ่มพอดี
    final double activeCellWidth = isChatVisible ? maxButtonSize + 8 : cellWidth;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Live Tab (ไทยมุง)
          if (showThaiMhung && !isThaiMhungReporting)
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              width: activeCellWidth,
              alignment: isChatVisible ? Alignment.centerLeft : Alignment.center,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxButtonSize, maxWidth: maxButtonSize),
                child: GlassTabButton(
                  label: 'ไทยมุง',
                  isActive: selectedTab == 0,
                  leading: AnimatedBuilder(
                    animation: blinkAnimation,
                    builder: (context, child) {
                      return Container(
                        width: 8, height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Color.lerp(Colors.red, Colors.red.withOpacity(0.3), blinkAnimation.value),
                        ),
                      );
                    },
                  ),
                  onTap: () => onTabSelected(0),
                ),
              ),
            ),

          // ความสัมพันธ์ Tab (เกี่ยวดอง) — เปิด Triage Sheet, ทุกคนเห็นได้
          if (showThaiMhung && !(selectedTab == 2 || isThaiMhungReporting))
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              width: activeCellWidth,
              alignment: isChatVisible ? Alignment.centerLeft : Alignment.center,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxButtonSize, maxWidth: maxButtonSize),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    GlassTabButton(
                      label: 'เกี่ยวดอง',
                      isActive: selectedTab == 1,
                      onTap: onTriageTabSelected ?? () => onTabSelected(1),
                    ),
                    if (triageBadgeCount > 0)
                      Positioned(
                        right: -4,
                        top: -4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: Colors.red,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.white, width: 1),
                          ),
                          child: Text(
                            '$triageBadgeCount',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),

          // แจ้งเหตุ Tab (ซ่อนเมื่ออยู่โหมดแชท)
          if (showEmergency && !isThaiMhungReporting)
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              width: isChatVisible ? 0 : activeCellWidth,
              alignment: Alignment.center,
              child: ClipRect(
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 200),
                  opacity: isChatVisible ? 0.0 : 1.0,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: maxButtonSize, maxWidth: maxButtonSize),
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
            ),

        ],
      ),
    );
  }
}
