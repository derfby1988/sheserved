class LocalChatMessage {
  final String content;
  final bool isMe;
  final DateTime sentAt;
  final String type;

  LocalChatMessage({
    required this.content,
    required this.isMe,
    required this.sentAt,
    required this.type,
  });
}
