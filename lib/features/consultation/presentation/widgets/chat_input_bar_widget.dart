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
  final VoidCallback onSend;
  final VoidCallback onStartRecording;
  final VoidCallback onStopRecording;
  final VoidCallback onPickImage;
  final VoidCallback onShowAttachmentMenu;
  final VoidCallback? onShowQuickReplies;
  final ValueChanged<String>? onTextChanged;

  const ChatInputBarWidget({
    super.key,
    required this.controller,
    required this.isProvider,
    required this.isChatActive,
    required this.isSending,
    required this.isRecording,
    required this.readOnly,
    required this.onSend,
    required this.onStartRecording,
    required this.onStopRecording,
    required this.onPickImage,
    required this.onShowAttachmentMenu,
    this.onShowQuickReplies,
    this.onTextChanged,
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
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(
                        color: const Color(0xFF4A8B2C).withOpacity(0.3),
                        width: 1.5,
                      ),
                    ),
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
                        'โหมดดูอย่างเดียว — กดรับงานเพื่อเข้าร่วม',
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
}
