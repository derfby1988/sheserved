import 'package:flutter/material.dart';
import 'offline_indicator_widget.dart';
import 'bottom_tabs_widget.dart';
import 'rescue_control_panel_widget.dart';
import 'rescue_accept_panel_widget.dart';

import '../../../../../shared/widgets/tlz_bottom_navigation_bar.dart';

class EmergencyUiOverlay extends StatelessWidget {
  final bool isUiVisible;
  final bool isConnected;
  final int selectedTab;
  final bool isThaiMhungReporting;
  final Widget content;
  final String? currentResponseId;
  final bool isEligibleResponder;
  final AnimationController liveBlinkController;
  final bool hasVideo;
  final Function(int) onTabSelected;
  final VoidCallback onEmergencyTabSelected;
  final VoidCallback onOpenInMaps;
  final Function(String) onUpdateStatus;
  final VoidCallback onAcceptRescue;
  final VoidCallback onToggleUi;
  final VoidCallback onToggleChat;
  final VoidCallback onDeclineRescue;
  final bool isChatVisible;

  const EmergencyUiOverlay({
    super.key,
    required this.isUiVisible,
    required this.isConnected,
    required this.selectedTab,
    required this.isThaiMhungReporting,
    required this.content,
    required this.currentResponseId,
    required this.isEligibleResponder,
    required this.liveBlinkController,
    required this.hasVideo,
    required this.onTabSelected,
    required this.onEmergencyTabSelected,
    required this.onOpenInMaps,
    required this.onUpdateStatus,
    required this.onAcceptRescue,
    required this.onToggleUi,
    required this.onToggleChat,
    required this.onDeclineRescue,
    this.isChatVisible = false,
  });

  @override
  Widget build(BuildContext context) {
    final bool showAcceptPanel = isEligibleResponder && selectedTab == 0;

    return Positioned.fill(
      child: IgnorePointer(
        ignoring: !isUiVisible,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: showAcceptPanel ? onDeclineRescue : onToggleUi,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 300),
            opacity: isUiVisible ? 1.0 : 0.0,
            child: SafeArea(
              left: false,
              right: false,
              child: Column(
                children: [
                  if (!isConnected) const OfflineIndicatorWidget(),

                  // Main Split Content based on Tab
                  Expanded(
                    child: GestureDetector(
                      onTap: showAcceptPanel ? onDeclineRescue : onToggleUi,
                      behavior: HitTestBehavior.translucent,
                      child: SingleChildScrollView(
                        child: content,
                      ),
                    ),
                  ),

                  // Bottom Right Actions (Chat Button)
                  if (selectedTab != 2 && !isThaiMhungReporting && hasVideo)
                    Padding(
                      padding: const EdgeInsets.only(right: 20, bottom: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          _buildChatButton(),
                        ],
                      ),
                    ),

                  // Tabs
                  BottomTabsWidget(
                    selectedTab: selectedTab,
                    blinkAnimation: liveBlinkController,
                    showThaiMhung: hasVideo, 
                    onTabSelected: onTabSelected,
                    onEmergencyTabSelected: onEmergencyTabSelected,
                    isChatVisible: isChatVisible,
                    isEligibleResponder: isEligibleResponder,
                    isThaiMhungReporting: isThaiMhungReporting,
                  ),
                  if (!hasVideo && selectedTab == 0) ...[
                    const SizedBox(height: 48),
                    TlzBottomNavigationBar(
                      currentIndex: 2,
                      isVisible: true,
                      onIndexChanged: (index) {
                        Navigator.of(context).pop(index);
                      },
                      onAddPressed: onEmergencyTabSelected,
                    ),
                  ] else ...[
                    const SizedBox(height: 12),
                  ]
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildChatButton() {
    if (isChatVisible) return const SizedBox.shrink(); // ⬅️ ซ่อนปุ่มถ้าแชทเปิดอยู่

    return GestureDetector(
      onTap: onToggleChat,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.5),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withOpacity(0.2)),
        ),
        child: const Stack(
          clipBehavior: Clip.none,
          children: [
            Icon(
              Icons.forum_outlined,
              color: Colors.white,
              size: 24,
            ),
          ],
        ),
      ),
    );
  }
}
