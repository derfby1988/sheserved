import 'package:flutter/material.dart';
import '../../../../chat/presentation/pages/chat_room_page.dart';

Future<void> showGroupChatPopup(
  BuildContext context, {
  required String groupId,
  required String groupName,
  int? memberCount,
  String? mentionTargetName,
}) {
  return showDialog(
    context: context,
    barrierDismissible: true,
    barrierColor: Colors.black54,
    builder: (dialogCtx) {
      final size = MediaQuery.sizeOf(dialogCtx);
      final isCompact = size.width < 600;
      final width = size.width * 0.92 > 560 ? 560.0 : size.width * 0.92;
      final height = size.height * (isCompact ? 0.58 : 0.55);
      final bottomInset = MediaQuery.viewInsetsOf(dialogCtx).bottom;

      return AnimatedPadding(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        padding: EdgeInsets.only(bottom: bottomInset),
        child: Center(
          child: SizedBox(
            width: width,
            height: height,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Material(
                elevation: 8,
                borderRadius: BorderRadius.circular(20),
                child: ChatRoomPage(
                  roomId: 'group_$groupId',
                  isPopup: true,
                  titleOverride: groupName,
                  subtitleOverride: memberCount != null
                      ? 'สมาชิก $memberCount คน'
                      : null,
                  mentionTargetName: mentionTargetName,
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}
