import 'package:flutter/material.dart';
import 'offline_indicator_widget.dart';
import 'bottom_tabs_widget.dart';
import 'rescue_control_panel_widget.dart';
import 'rescue_accept_panel_widget.dart';

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
    this.isChatVisible = false,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        ignoring: !isUiVisible,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: onToggleUi,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 300),
            opacity: isUiVisible ? 1.0 : 0.0,
            child: SafeArea(
              left: false,
              right: false,
              child: Column(
                children: [
                  if (!isConnected) const OfflineIndicatorWidget(),

                  // Removed top bar chat button from here

                  // Main Split Content based on Tab
                  Expanded(
                    child: GestureDetector(
                      onTap: onToggleUi,
                      behavior: HitTestBehavior.translucent,
                      child: SingleChildScrollView(
                        child: content,
                      ),
                    ),
                  ),

                  // Rescue Control Panel
                  if (currentResponseId != null && selectedTab == 0)
                    RescueControlPanelWidget(
                      onOpenInMaps: onOpenInMaps,
                      onUpdateStatus: onUpdateStatus,
                    ),

                  // Rescue Accept Panel
                  if (isEligibleResponder && selectedTab == 0)
                    RescueAcceptPanelWidget(
                      onAccept: onAcceptRescue,
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
                  ),
                  const SizedBox(height: 12),
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
          color: Colors.black.withValues(alpha: 0.5),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
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
