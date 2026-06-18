import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../../../../core/constants/app_colors.dart';
import '../../../../chat/data/models/chat_models.dart';
import '../mini_voice_player.dart';
import 'prescription_card.dart';
import 'summary_card.dart';
import 'body_map_chat_bar.dart';

class MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final bool isMe;
  final VoidCallback? onViewPrescription;
  final VoidCallback? onViewSummary;
  final bool hideBodyPart;
  final String? bodyPartIconName;
  final String? senderAvatarUrl;

  const MessageBubble({
    super.key,
    required this.message,
    required this.isMe,
    this.onViewPrescription,
    this.onViewSummary,
    this.hideBodyPart = false,
    this.bodyPartIconName,
    this.senderAvatarUrl,
  });

  @override
  Widget build(BuildContext context) {
    final isRequired = message.type == 'required_question';
    final bgColor = isRequired
        ? Colors.transparent
        : (isMe ? AppColors.primary : Colors.white);
    final borderColor = isRequired
        ? Colors.green.shade600.withOpacity(0.5)
        : (isMe ? AppColors.primary : Colors.white);
    final textColor = isRequired
        ? Colors.black87
        : (isMe ? Colors.white : Colors.black87);
    final labelColor = isRequired
        ? Colors.red.shade600
        : (isMe ? Colors.white : Colors.red.shade600);
    final timeColor = isRequired
        ? Colors.grey.shade500
        : (isMe ? Colors.white.withOpacity(0.7) : Colors.grey.shade500);
    final iconColor = isRequired
        ? Colors.grey.shade500
        : (isMe ? Colors.white.withOpacity(0.7) : Colors.grey.shade500);

    Widget bubble = Container(
      constraints: BoxConstraints(
        maxWidth: isRequired
            ? MediaQuery.of(context).size.width * 0.85
            : MediaQuery.of(context).size.width * 0.62,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(18),
          topRight: const Radius.circular(18),
          bottomLeft: Radius.circular(isMe ? 18 : 4),
          bottomRight: Radius.circular(isMe ? 4 : 18),
        ),
        border: isRequired ? Border.all(color: borderColor, width: 1.5) : null,
        boxShadow: isRequired
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          _buildMessageBody(textColor, labelColor, timeColor),
          const SizedBox(height: 3),
          if (!isRequired)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (message.bodyPart != null && !hideBodyPart) ...[
                  Icon(
                    iconNameToIconData(bodyPartIconName) ?? Icons.circle,
                    size: 9,
                    color: iconColor,
                  ),
                  const SizedBox(width: 4),
                ],
                Text(
                  '${message.createdAt.hour}:${message.createdAt.minute.toString().padLeft(2, '0')}',
                  style: TextStyle(
                    fontSize: 9,
                    color: timeColor,
                  ),
                ),
                if (isMe && senderAvatarUrl != null) ...[
                  const SizedBox(width: 4),
                  Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      image: DecorationImage(
                        image: CachedNetworkImageProvider(senderAvatarUrl!),
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ],
              ],
            ),
        ],
      ),
    );

    // Required question bubbles expand to fill available width
    if (isRequired) {
      bubble = Expanded(child: bubble);
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Row(
          mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (!isMe && message.type == 'required_question' && senderAvatarUrl != null) ...[
              CircleAvatar(
                radius: 14,
                backgroundImage: CachedNetworkImageProvider(senderAvatarUrl!),
              ),
              const SizedBox(width: 6),
            ],
            bubble,
          ],
        ),
      ),
    );
  }

  Widget _buildMessageBody(Color textColor, Color labelColor, Color timeColor) {
    switch (message.type) {
      case 'image':
        if (message.attachmentUrl != null) {
          return ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: CachedNetworkImage(
              imageUrl: message.attachmentUrl!,
              width: 160,
              fit: BoxFit.cover,
              placeholder: (_, __) => Container(
                width: 160,
                height: 120,
                color: Colors.grey.shade200,
                child: const Center(
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          );
        }
        return _buildTextContent(textColor);
      case 'voice':
        if (message.attachmentUrl != null) {
          return MiniVoicePlayer(url: message.attachmentUrl!, isMe: isMe);
        }
        return _buildTextContent(textColor);
      case 'prescription':
        return PrescriptionCard(
          message: message,
          onViewDetails: onViewPrescription,
        );
      case 'summary':
        return SummaryCard(
          message: message,
          onViewDetails: onViewSummary,
        );
      case 'required_question':
        final questionCrossAxis = isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start;
        return Column(
          crossAxisAlignment: questionCrossAxis,
          children: [
            // [Label removed — clean minimal design]
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: RichText(
                    text: TextSpan(
                      style: TextStyle(
                        color: textColor,
                        fontSize: 14,
                        height: 1.4,
                      ),
                      children: [
                        if (message.bodyPart != null && bodyPartIconName != null)
                          WidgetSpan(
                            child: Icon(
                              iconNameToIconData(bodyPartIconName) ?? Icons.circle,
                              size: 14,
                              color: textColor.withOpacity(0.7),
                            ),
                            alignment: PlaceholderAlignment.middle,
                          ),
                        if (message.bodyPart != null && bodyPartIconName != null)
                          const WidgetSpan(
                            child: SizedBox(width: 4),
                          ),
                        TextSpan(text: message.content),
                        const WidgetSpan(
                          child: SizedBox(width: 4),
                        ),
                        TextSpan(
                          text: '${message.createdAt.hour}:${message.createdAt.minute.toString().padLeft(2, '0')}',
                          style: TextStyle(
                            fontSize: 9,
                            color: timeColor,
                          ),
                        ),
                      ],
                    ),
                    textAlign: isMe ? TextAlign.right : TextAlign.left,
                  ),
                ),
                if (isMe && senderAvatarUrl != null) ...[
                  const SizedBox(width: 4),
                  Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      image: DecorationImage(
                        image: CachedNetworkImageProvider(senderAvatarUrl!),
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            if (message.requiredAnswer != null) ...[
              const SizedBox(height: 8),
              Align(
                alignment: isMe ? Alignment.centerLeft : Alignment.centerRight,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                    Text(
                      message.requiredAnswer!,
                      style: TextStyle(
                        color: Colors.green.shade800,
                        fontSize: 12,
                      ),
                    ),
                    if (message.requiredAnsweredAt != null) ...[
                      const SizedBox(width: 4),
                      Text(
                        '${message.requiredAnsweredAt!.hour}:${message.requiredAnsweredAt!.minute.toString().padLeft(2, '0')}',
                        style: TextStyle(
                          color: Colors.grey.shade500,
                          fontSize: 9,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ],
        );
      default:
        return _buildTextContent(textColor);
    }
  }

  Widget _buildTextContent(Color textColor) {
    return Text(
      message.content,
      style: TextStyle(
        color: textColor,
        fontSize: 14,
        height: 1.4,
      ),
    );
  }
}
