import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';

class ChatInputBarWidget extends StatelessWidget {
  final TextEditingController controller;
  final bool isProvider;
  final bool isChatActive;
  final ValueListenable<bool> isSending;
  final ValueListenable<bool> isRecording;
  final bool readOnly;
  final String? readOnlyLabel;
  final VoidCallback onSend;
  final VoidCallback onStartRecording;
  final VoidCallback onStopRecording;
  final VoidCallback onPickImage;
  final VoidCallback onShowAttachmentMenu;
  final VoidCallback? onShowQuickReplies;
  final ValueChanged<String>? onTextChanged;
  final String? activeBodyPartIconName;
  final VoidCallback? onClearBodyPart;

  const ChatInputBarWidget({
    super.key,
    required this.controller,
    required this.isProvider,
    required this.isChatActive,
    required this.isSending,
    required this.isRecording,
    required this.readOnly,
    this.readOnlyLabel,
    required this.onSend,
    required this.onStartRecording,
    required this.onStopRecording,
    required this.onPickImage,
    required this.onShowAttachmentMenu,
    this.onShowQuickReplies,
    this.onTextChanged,
    this.activeBodyPartIconName,
    this.onClearBodyPart,
  });

  @override
  Widget build(BuildContext context) {
    final hasText = controller.text.trim().isNotEmpty;

    Widget buildInputIconButton({
      required IconData icon,
      required VoidCallback onTap,
      String? tooltip,
    }) {
      return GestureDetector(
        onTap: onTap,
        child: Tooltip(
          message: tooltip ?? '',
          child: Container(
            height: 38,
            width: 38,
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Icon(icon, color: Colors.grey.shade700, size: 20),
          ),
        ),
      );
    }

    Widget buildActionButton({
      required Key key,
      required IconData icon,
      required Color color,
      required Color bgColor,
      required VoidCallback onTap,
      bool isLoading = false,
    }) {
      return GestureDetector(
        key: key,
        onTap: onTap,
        child: Container(
          height: 44,
          width: 44,
          decoration: BoxDecoration(
            color: bgColor,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: bgColor.withOpacity(0.4),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: isLoading
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                )
              : Icon(icon, color: color, size: 20),
        ),
      );
    }

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Opacity(
          opacity: isChatActive ? 1.0 : 0.3,
          child: AbsorbPointer(
            absorbing: !isChatActive,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (isProvider) ...[
                  buildInputIconButton(
                    icon: Icons.bolt,
                    tooltip: 'ข้อความด่วน',
                    onTap: onShowQuickReplies ?? () {},
                  ),
                  const SizedBox(width: 4),
                  buildInputIconButton(
                    icon: Icons.attach_file,
                    tooltip: 'เครื่องมือแพทย์',
                    onTap: onShowAttachmentMenu,
                  ),
                  const SizedBox(width: 4),
                ] else ...[
                  buildInputIconButton(
                    icon: Icons.image_outlined,
                    tooltip: 'ส่งรูปภาพ',
                    onTap: onPickImage,
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Container(
                    height: 44,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(
                        color: const Color(0xFF4A8B2C).withOpacity(0.3),
                        width: 1.5,
                      ),
                    ),
                    child: Row(
                      children: [
                        if (activeBodyPartIconName != null) ...[
                          _bodyPartIcon(activeBodyPartIconName!),
                          const SizedBox(width: 4),
                          GestureDetector(
                            onTap: onClearBodyPart,
                            child: Icon(Icons.close, size: 14, color: Colors.orange.shade700),
                          ),
                          const SizedBox(width: 6),
                        ],
                        Expanded(
                          child: TextField(
                      controller: controller,
                      style: const TextStyle(color: Colors.black87, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'ถามผู้เชี่ยวชาญ...',
                        hintStyle: TextStyle(
                          color: Colors.grey.shade500,
                          fontSize: 14,
                        ),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      onChanged: onTextChanged,
                      onSubmitted: (_) => onSend(),
                    ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                AnimatedBuilder(
                  animation: Listenable.merge([isSending, isRecording]),
                  builder: (context, child) {
                    final sending = isSending.value;
                    final recording = isRecording.value;
                    return AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: child),
                      child: hasText
                          ? buildActionButton(
                              key: const ValueKey('send'),
                              icon: Icons.send_rounded,
                              color: Colors.white,
                              bgColor: const Color(0xFF4A8B2C),
                              onTap: onSend,
                              isLoading: sending,
                            )
                          : GestureDetector(
                              key: const ValueKey('mic'),
                              onLongPressStart: (_) => onStartRecording(),
                              onLongPressEnd: (_) => onStopRecording(),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                height: 44,
                                width: 44,
                                decoration: BoxDecoration(
                                  color: recording
                                      ? Colors.redAccent
                                      : const Color(0xFF4A8B2C),
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: (recording
                                              ? Colors.redAccent
                                              : const Color(0xFF4A8B2C))
                                          .withOpacity(0.3),
                                      blurRadius: 10,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Icon(
                                  recording ? Icons.stop_rounded : Icons.mic,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              ),
                            ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
        if (!isProvider && !readOnly && !isChatActive)
          Positioned.fill(
            child: Container(
              color: Colors.white.withOpacity(0.1),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.orange.shade200),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.lock_outline, size: 14, color: Colors.orange.shade800),
                      const SizedBox(width: 6),
                      Text(
                        'กดยืนยันเพื่อเริ่มต้นการแชท',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.orange.shade800,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        if (readOnly)
          Positioned.fill(
            child: Container(
              color: Colors.grey.shade100.withOpacity(0.85),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.visibility_outlined,
                          size: 18, color: Colors.grey.shade600),
                      const SizedBox(width: 8),
                      Text(
                        readOnlyLabel ?? 'โหมดดูอย่างเดียว — กดรับงานเพื่อเข้าร่วม',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade700,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// Convert Material icon name string → Icon widget
  Widget _bodyPartIcon(String iconName) {
    IconData? iconData;
    switch (iconName) {
      case 'face': iconData = Icons.face; break;
      case 'face_retouching_natural': iconData = Icons.face_retouching_natural; break;
      case 'remove_red_eye_outlined': iconData = Icons.remove_red_eye_outlined; break;
      case 'hearing_outlined': iconData = Icons.hearing_outlined; break;
      case 'record_voice_over_outlined': iconData = Icons.record_voice_over_outlined; break;
      case 'compress': iconData = Icons.compress; break;
      case 'accessibility_new': iconData = Icons.accessibility_new; break;
      case 'horizontal_rule': iconData = Icons.horizontal_rule; break;
      case 'monitor_heart_outlined': iconData = Icons.monitor_heart_outlined; break;
      case 'fitness_center': iconData = Icons.fitness_center; break;
      case 'favorite_border': iconData = Icons.favorite_border; break;
      case 'restaurant_menu': iconData = Icons.restaurant_menu; break;
      case 'adjust': iconData = Icons.adjust; break;
      case 'radio_button_checked': iconData = Icons.radio_button_checked; break;
      case 'pan_tool_alt_outlined': iconData = Icons.pan_tool_alt_outlined; break;
      case 'water_drop_outlined': iconData = Icons.water_drop_outlined; break;
      case 'watch_outlined': iconData = Icons.watch_outlined; break;
      case 'trip_origin': iconData = Icons.trip_origin; break;
      case 'back_hand_outlined': iconData = Icons.back_hand_outlined; break;
      case 'directions_walk': iconData = Icons.directions_walk; break;
      case 'directions_run': iconData = Icons.directions_run; break;
      case 'lens_outlined': iconData = Icons.lens_outlined; break;
      case 'linear_scale': iconData = Icons.linear_scale; break;
      case 'align_vertical_bottom': iconData = Icons.align_vertical_bottom; break;
      case 'radio_button_unchecked': iconData = Icons.radio_button_unchecked; break;
      case 'run_circle_outlined': iconData = Icons.run_circle_outlined; break;
      case 'linear_scale_outlined': iconData = Icons.linear_scale_outlined; break;
    }
    if (iconData == null) return const SizedBox.shrink();
    return Icon(iconData, size: 18, color: Colors.orange.shade700);
  }
}
