import 'dart:async';
import 'dart:convert';
import 'dart:ui';
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

    // [B] โหลดประวัติแชทก่อนเข้าร่วม room
    _loadChatHistory();

    // ดักฟังข้อความใหม่แบบ Real-time
    _chatSubscription = WebSocketService().emergencyChatStream.listen((data) {
      if (data['videoId'] == widget.videoId) {
        // หลีกเลี่ยง duplicate: ถ้า id ตรงกับที่มีอยู่แล้ว ข้าม
        final incoming = Map<String, dynamic>.from(data);
        final isDuplicate = _messages.any((m) => m['id'] != null && m['id'] == incoming['id']);
        if (!isDuplicate) {
          setState(() => _messages.add(incoming));
          _scrollToBottom();
        }
      }
    });

    // เข้าร่วม socket room ของเหตุการณ์นี้
    WebSocketService().joinEmergencyChat(widget.videoId, widget.userId, widget.role);
  }

  /// [B] ดึงประวัติแชทจาก REST API
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
    } catch (e) {
      // Server offline หรือ DB ไม่พร้อม → ไม่แสดง error, เปิดแชทปกติ
      if (mounted) setState(() => _isLoadingHistory = false);
    }
  }

  @override
  void dispose() {
    // [C] ออกจาก socket room เพื่อไม่ให้เกิด memory leak ฝั่ง Server
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
    if (_messageController.text.trim().isEmpty) return;

    WebSocketService().sendEmergencyChatMessage(
      videoId: widget.videoId,
      userId: widget.userId,
      role: widget.role,
      userName: widget.userName,
      content: _messageController.text.trim(),
      profileImageUrl: widget.profileImageUrl,
    );

    _messageController.clear();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
          ),
          child: Column(
            children: [
              _buildHeader(),
              Expanded(
                child: _buildMessageList(),
              ),
              _buildInputArea(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 15, 20, 15),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.1))),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.forum_outlined, color: Colors.white, size: 20),
                    const SizedBox(width: 8),
                    const Text(
                      'Emergency Live Chat',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  'Incident Communication Channel',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white),
            onPressed: widget.onClose,
          ),
        ],
      ),
    );
  }

  Widget _buildMessageList() {
    // แสดง Loading spinner ขณะดึงประวัติ
    if (_isLoadingHistory) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
              width: 28, height: 28,
              child: CircularProgressIndicator(color: Colors.white54, strokeWidth: 2),
            ),
            const SizedBox(height: 12),
            Text(
              'กำลังโหลดประวัติ...',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 13),
            ),
          ],
        ),
      );
    }

    return _messages.isEmpty
        ? Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.chat_bubble_outline, color: Colors.white.withValues(alpha: 0.2), size: 48),
                const SizedBox(height: 16),
                Text(
                  'ยังไม่มีการสนทนาในขณะนี้',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.4)),
                ),
              ],
            ),
          )
        : ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            itemCount: _messages.length,
            itemBuilder: (context, index) {
              final msg = _messages[index];
              final isMe = msg['userId'] == widget.userId;
              return _buildChatMessage(msg, isMe);
            },
          );
  }

  Widget _buildChatMessage(Map<String, dynamic> msg, bool isMe) {
    final role = msg['role'] ?? 'viewer';
    Color roleColor;
    String roleLabel;

    switch (role) {
      case 'reporter':
        roleColor = Colors.orangeAccent;
        roleLabel = 'ผู้แจ้งเหตุ';
        break;
      case 'responder':
        roleColor = Colors.blueAccent;
        roleLabel = 'เจ้าหน้าที่';
        break;
      case 'thaimhung':
        roleColor = Colors.pinkAccent;
        roleLabel = 'อาสาสมัคร';
        break;
      default:
        roleColor = Colors.grey;
        roleLabel = 'ผู้ชม';
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!isMe) ...[
                if (msg['profileImageUrl'] != null)
                  CircleAvatar(radius: 10, backgroundImage: NetworkImage(msg['profileImageUrl'])),
                const SizedBox(width: 6),
                Text(
                  msg['userName'] ?? 'Unknown',
                  style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 6),
              ],
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: roleColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: roleColor.withValues(alpha: 0.5)),
                ),
                child: Text(
                  roleLabel.toUpperCase(),
                  style: TextStyle(color: roleColor, fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ),
              if (isMe) ...[
                const SizedBox(width: 6),
                const Text(
                  'ฉัน',
                  style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.65),
            decoration: BoxDecoration(
              color: isMe ? roleColor.withValues(alpha: 0.25) : Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16).copyWith(
                topRight: isMe ? Radius.zero : null,
                topLeft: !isMe ? Radius.zero : null,
              ),
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            ),
            child: Text(
              msg['content'] ?? '',
              style: const TextStyle(color: Colors.white, fontSize: 15),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            _formatTimestamp(msg['timestamp']),
            style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 10),
          ),
        ],
      ),
    );
  }

  String _formatTimestamp(String? timestamp) {
    if (timestamp == null) return '';
    try {
      final dt = DateTime.parse(timestamp).toLocal();
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return '';
    }
  }

  Widget _buildInputArea() {
    return Container(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + MediaQuery.of(context).padding.bottom),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.1))),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _messageController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'พิมพ์ข้อความที่นี่...',
                hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.4)),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.08),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide(color: Colors.blueAccent.withValues(alpha: 0.5)),
                ),
              ),
              onSubmitted: (_) => _sendMessage(),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.blueAccent, Colors.blue.shade700],
              ),
              shape: BoxShape.circle,
            ),
            child: IconButton(
              icon: const Icon(Icons.send_rounded, color: Colors.white, size: 22),
              onPressed: _sendMessage,
            ),
          ),
        ],
      ),
    );
  }
}
