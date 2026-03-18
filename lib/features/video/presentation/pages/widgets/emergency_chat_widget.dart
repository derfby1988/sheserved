import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../../../../config/app_config.dart';
import '../../../../../services/websocket_service.dart';

class EmergencyChatWidget extends StatefulWidget {
  final String videoId;
  final String userId;
  final String userName;
  final String role;
  final String? profileImageUrl;
  final VoidCallback onClose;

  const EmergencyChatWidget({
    super.key,
    required this.videoId,
    required this.userId,
    required this.userName,
    required this.role,
    this.profileImageUrl,
    required this.onClose,
  });

  @override
  State<EmergencyChatWidget> createState() => _EmergencyChatWidgetState();
}

class _EmergencyChatWidgetState extends State<EmergencyChatWidget> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<Map<String, dynamic>> _messages = [];
  late StreamSubscription _chatSubscription;
  bool _isLoadingHistory = true;

  @override
  void initState() {
    super.initState();

    _loadChatHistory();

    _chatSubscription = WebSocketService().emergencyChatStream.listen((data) {
      if (data['videoId'] == widget.videoId) {
        final incoming = Map<String, dynamic>.from(data);
        final isDuplicate = _messages.any((m) => m['id'] != null && m['id'] == incoming['id']);
        if (!isDuplicate) {
          setState(() => _messages.add(incoming));
          _scrollToBottom();
        }
      }
    });

    WebSocketService().joinEmergencyChat(widget.videoId, widget.userId, widget.role);
  }

  Future<void> _loadChatHistory() async {
    try {
      final url = '${AppConfig.localApiUrl}/api/videos/${widget.videoId}/chat';
      final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200 && mounted) {
        final List<dynamic> data = jsonDecode(response.body);
        setState(() {
          _messages.clear();
          _messages.addAll(data.map((e) => Map<String, dynamic>.from(e)));
          _isLoadingHistory = false;
        });
        _scrollToBottom();
      } else {
        if (mounted) setState(() => _isLoadingHistory = false);
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingHistory = false);
    }
  }

  @override
  void dispose() {
    WebSocketService().leaveEmergencyChat(widget.videoId);
    _chatSubscription.cancel();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _sendMessage() {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;
    WebSocketService().sendEmergencyChatMessage(
      videoId: widget.videoId,
      userId: widget.userId,
      role: widget.role,
      userName: widget.userName,
      content: text,
      profileImageUrl: widget.profileImageUrl,
    );
    _messageController.clear();
  }

  Color _roleColor(String role) {
    switch (role) {
      case 'reporter':   return const Color(0xFFFF9500); // Orange
      case 'responder':  return const Color(0xFF007AFF); // Blue
      case 'thaimhung':  return const Color(0xFFFF2D78); // Pink
      default:           return const Color(0xFF8E8E93); // Grey
    }
  }

  String _roleLabel(String role) {
    switch (role) {
      case 'reporter':  return 'ผู้แจ้งเหตุ';
      case 'responder': return 'เจ้าหน้าที่';
      case 'thaimhung': return 'ไทยมุง';
      default:          return 'ผู้ชม';
    }
  }

  String _formatTimestamp(String? ts) {
    if (ts == null) return '';
    try {
      final dt = DateTime.parse(ts).toLocal();
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    // โปร่งใสสมบูรณ์ ไม่มีพื้นหลัง ไม่มี blur
    return Column(
      children: [
        // ── Close button แบบลอย ──
        Align(
          alignment: Alignment.topRight,
          child: GestureDetector(
            onTap: widget.onClose,
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.45),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 8),
                ],
              ),
              child: const Icon(Icons.close, color: Colors.white, size: 16),
            ),
          ),
        ),
        const SizedBox(height: 4),

        // ── รายการข้อความ ──
        Expanded(child: _buildMessageList()),

        // ── Input bar ──
        _buildInputArea(),
      ],
    );
  }

  Widget _buildMessageList() {
    if (_isLoadingHistory) {
      return const Center(
        child: SizedBox(
          width: 22, height: 22,
          child: CircularProgressIndicator(color: Colors.white54, strokeWidth: 2),
        ),
      );
    }

    if (_messages.isEmpty) {
      return Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            'ยังไม่มีการสนทนา',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 12),
          ),
        ),
      );
    }

    return Scrollbar(
      controller: _scrollController,
      thumbVisibility: true,
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        itemCount: _messages.length,
        itemBuilder: (context, index) {
          final msg = _messages[index];
          final isMe = msg['userId'] == widget.userId;
          return _buildBubble(msg, isMe);
        },
      ),
    );
  }

  // ── Chat Bubble ลอยบนแผนที่ ──
  Widget _buildBubble(Map<String, dynamic> msg, bool isMe) {
    final role = msg['role'] ?? 'viewer';
    final color = _roleColor(role);
    final label = _roleLabel(role);
    final name = msg['userName'] ?? 'Unknown';
    final content = msg['content'] ?? '';
    final time = _formatTimestamp(msg['timestamp']);

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Column(
          crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── sender label ──
            if (!isMe)
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.85),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        label,
                        style: const TextStyle(fontFamily: 'Sukhumvit Set', color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      name,
                      style: TextStyle(
                        fontFamily: 'Sukhumvit Set',
                        color: Colors.white.withValues(alpha: 0.9),
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        shadows: [Shadow(color: Colors.black.withValues(alpha: 0.8), blurRadius: 4)],
                      ),
                    ),
                  ],
                ),
              ),

            // ── bubble body ──
            Container(
              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.56),
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
              decoration: BoxDecoration(
                // พื้นหลังแค่เล็กน้อยเพื่อให้อ่านได้ ไม่บังแผนที่
                color: isMe
                    ? color.withValues(alpha: 0.15)
                    : Colors.black.withValues(alpha: 0.52),
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(14),
                  topRight: const Radius.circular(14),
                  bottomLeft: isMe ? const Radius.circular(14) : Radius.zero,
                  bottomRight: isMe ? Radius.zero : const Radius.circular(14),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.35),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
                border: Border.all(
                  color: isMe ? color.withValues(alpha: 0.4) : Colors.white.withValues(alpha: 0.12),
                  width: 0.5,
                ),
              ),
              child: Text(
                content,
                style: TextStyle(
                  fontFamily: 'Sukhumvit Set',
                  color: color, // ⬅️ เปลี่ยนสีตัวอักษรตามกลุ่ม
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  height: 1.15,
                  shadows: const [Shadow(color: Colors.black54, blurRadius: 3)],
                ),
              ),
            ),

            // ── timestamp + my role badge ──
            Padding(
              padding: const EdgeInsets.only(top: 2, left: 4, right: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isMe) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.75),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        label,
                        style: const TextStyle(fontFamily: 'Sukhumvit Set', color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(width: 4),
                  ],
                  Text(
                    time,
                    style: TextStyle(
                      fontFamily: 'Sukhumvit Set',
                      color: Colors.white.withValues(alpha: 0.55),
                      fontSize: 9,
                      shadows: [Shadow(color: Colors.black.withValues(alpha: 0.7), blurRadius: 3)],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Input area ลอยบนแผนที่ ──
  Widget _buildInputArea() {
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white, // เปลี่ยนพื้นหลังเป็นสีขาวเพื่อให้ตัวหนังสือสีดำเห็นชัด
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withValues(alpha: 0.8)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 12, offset: const Offset(0, 3)),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _messageController,
              style: const TextStyle(fontFamily: 'Sukhumvit Set', color: Colors.black, fontSize: 13), // เปลี่ยนตัวอักษรเป็นสีดำ
              maxLines: 1,
              decoration: InputDecoration(
                hintText: 'พิมพ์ข้อความ...',
                hintStyle: TextStyle(fontFamily: 'Sukhumvit Set', color: Colors.black54, fontSize: 13), // เปลี่ยนสี hint เป็นเทาเข้ม
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
              ),
              onSubmitted: (_) => _sendMessage(),
            ),
          ),
          GestureDetector(
            onTap: _sendMessage,
            child: Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF007AFF), Color(0xFF0051D5)],
                ),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(color: const Color(0xFF007AFF).withValues(alpha: 0.4), blurRadius: 8),
                ],
              ),
              child: const Icon(Icons.send_rounded, color: Colors.white, size: 17),
            ),
          ),
        ],
      ),
    );
  }
}
