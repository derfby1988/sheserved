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
  final String? professionName;
  final VoidCallback onClose;

  const EmergencyChatWidget({
    super.key,
    required this.videoId,
    required this.userId,
    required this.userName,
    required this.role,
    this.profileImageUrl,
    this.professionName,
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

  // ── Anti-spam state ──
  DateTime? _lastMessageTime;
  final int _cooldownSeconds = 3;
  final int _maxChars = 100;
  final Map<int, bool> _expandedMessages = {};

  // ── Filter state ──
  late bool _isFilterActive;

  // ── Scroll-to-bottom button state ──
  bool _showScrollToBottom = false;
  bool _isNearBottom = true;

  @override
  void initState() {
    super.initState();

    // ตั้งค่าเริ่มต้นของตัวกรอง: ให้เปิดขึ้นอัตโนมัติถ้าเป็นกลุ่มสิทธิ์สูง
    _isFilterActive = widget.role == 'reporter' || widget.role == 'responder';

    _loadChatHistory();

    // ตรวจตำแหน่ง scroll เพื่อแสดงปุ่ม "เลื่อน" เมื่ออ่านข้อความเก่า
    _scrollController.addListener(() {
      if (!_scrollController.hasClients) return;
      final position = _scrollController.position;
      final maxScroll = position.maxScrollExtent;
      final currentScroll = position.pixels;
      // ถ้าอยู่ใกล้ล่างสุด (ภายใน 80px) ถือว่าอยู่ล่าง → ซ่อนปุ่ม
      final nearBottom = (maxScroll - currentScroll) <= 80;
      if (nearBottom != _isNearBottom) {
        setState(() {
          _isNearBottom = nearBottom;
          _showScrollToBottom = !nearBottom;
        });
      }
    });

    _chatSubscription = WebSocketService().emergencyChatStream.listen((data) {
      if (data['videoId'] == widget.videoId) {
        final incoming = Map<String, dynamic>.from(data);
        final isDuplicate = _messages.any(
          (m) => m['id'] != null && m['id'] == incoming['id'],
        );
        if (!isDuplicate) {
          setState(() => _messages.add(incoming));
          // ถ้าเปิดฟิลเตอร์อยู่ และข้อความใหม่ไม่ใช่กลุ่มที่ตรงกับฟิลเตอร์ ก็ไม่ต้องเลื่อนจอ
          final isPrivilegedRole =
              incoming['role'] == 'reporter' || incoming['role'] == 'responder';
          if (!_isFilterActive || isPrivilegedRole) {
            _scrollToBottom();
          }
        }
      }
    });

    WebSocketService().joinEmergencyChat(
      widget.videoId,
      widget.userId,
      widget.role,
    );
  }

  @override
  void didUpdateWidget(covariant EmergencyChatWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // หากฐานะ (Role) ของผู้ใช้เปลี่ยนกลางคันเป็นกลุ่มสิทธิ์สูง ให้เปิดฟิลเตอร์แชทอัตโนมัติ
    if (widget.role != oldWidget.role &&
        (widget.role == 'reporter' || widget.role == 'responder')) {
      setState(() {
        _isFilterActive = true;
      });
    }
  }

  void _mergeHistory(List<dynamic> data) {
    if (!mounted) return;

    final merged = <String, Map<String, dynamic>>{
      for (final message in _messages)
        if (message['id'] != null) message['id'].toString(): message,
    };

    for (final message in data) {
      final normalized = Map<String, dynamic>.from(message);
      final id = normalized['id']?.toString();
      if (id != null) {
        merged[id] = normalized;
      } else {
        _messages.add(normalized);
      }
    }

    final messages = merged.values.toList()
      ..sort((a, b) {
        final aTime = DateTime.tryParse(a['timestamp']?.toString() ?? '');
        final bTime = DateTime.tryParse(b['timestamp']?.toString() ?? '');
        return (aTime ?? DateTime.fromMillisecondsSinceEpoch(0)).compareTo(
          bTime ?? DateTime.fromMillisecondsSinceEpoch(0),
        );
      });

    setState(() {
      _messages
        ..clear()
        ..addAll(messages);
      _isLoadingHistory = false;
    });
  }

  Future<void> _loadChatHistory() async {
    try {
      final url = '${AppConfig.localApiUrl}/api/videos/${widget.videoId}/chat';
      debugPrint('[Chat] Loading history from: $url');

      final response = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 6));
      debugPrint(
        '[Chat] Response status: ${response.statusCode}, body length: ${response.body.length}',
      );

      if (response.statusCode == 200 && mounted) {
        final List<dynamic> data = jsonDecode(response.body);
        debugPrint('[Chat] Got ${data.length} active messages');

        if (data.isNotEmpty) {
          _mergeHistory(data);
          _scrollToBottom();
          return;
        }
      }

      final archivedUrl =
          '${AppConfig.localApiUrl}/api/videos/${widget.videoId}/chat/archived';
      debugPrint('[Chat] Trying archived endpoint: $archivedUrl');

      final archivedResponse = await http
          .get(Uri.parse(archivedUrl))
          .timeout(const Duration(seconds: 6));

      if (archivedResponse.statusCode == 200 && mounted) {
        final List<dynamic> archivedData = jsonDecode(archivedResponse.body);
        debugPrint('[Chat] Got ${archivedData.length} archived messages');

        _mergeHistory(archivedData);
        _scrollToBottom();
        return;
      }

      if (mounted) setState(() => _isLoadingHistory = false);
    } catch (e, stack) {
      debugPrint('[Chat] _loadChatHistory ERROR: $e');
      debugPrint('[Chat] Stack: $stack');
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

  Widget _buildScrollToBottomButton() {
    return GestureDetector(
      onTap: () {
        _scrollToBottom();
        setState(() {
          _showScrollToBottom = false;
          _isNearBottom = true;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.6),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white24, width: 1),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.arrow_downward, color: Colors.white, size: 14),
            SizedBox(width: 4),
            Text(
              'เลื่อน',
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _sendMessage() {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    if (text.length > _maxChars) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('ข้อความยาวเกินไป (สูงสุด 100 ตัวอักษร)'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final now = DateTime.now();
    if (_lastMessageTime != null) {
      final difference = now.difference(_lastMessageTime!).inSeconds;
      final requiredCooldown =
          (widget.role == 'reporter' || widget.role == 'responder')
          ? 1
          : _cooldownSeconds;
      if (difference < requiredCooldown) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'กรุณารอ ${requiredCooldown - difference} วินาทีก่อนส่งข้อความถัดไป',
            ),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
    }

    if (widget.role == 'viewer' || widget.role == 'thaimhung') {
      final linkRegex = RegExp(r'(https?:\/\/|www\.)[^\s]+');
      if (linkRegex.hasMatch(text)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('ไม่อนุญาตให้ส่งลิงก์ในห้องแชท'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
    }

    _lastMessageTime = now;

    WebSocketService().sendEmergencyChatMessage(
      videoId: widget.videoId,
      userId: widget.userId,
      role: widget.role,
      userName: widget.userName,
      content: text,
      profileImageUrl: widget.profileImageUrl,
      professionName: widget.professionName,
    );
    _messageController.clear();
  }

  String _formatShortName(String rawName) {
    if (rawName.isEmpty) return 'Unknown';
    final parts = rawName.split(' ');
    if (parts.length > 1) {
      if (parts.last.isNotEmpty) {
        return '${parts[0]} ${parts.last[0]}.';
      }
    }
    return rawName;
  }

  Color _roleColor(String role) {
    switch (role) {
      case 'reporter':
        return const Color(0xFFFF9500); // Orange
      case 'responder':
        return const Color(0xFF007AFF); // Blue
      case 'thaimhung':
        return const Color(0xFFFF2D78); // Pink
      case 'viewer':
        return const Color(0xFFFF2D78); // Pink (โหมดสนับสนุน)
      default:
        return const Color(0xFF8E8E93); // Grey
    }
  }

  String _roleLabel(String role, String shortName, {String? professionName}) {
    switch (role) {
      case 'reporter':
        return 'ผู้แจ้งเหตุ';
      case 'responder':
        return professionName?.isNotEmpty == true
            ? professionName!
            : 'เจ้าหน้าที่';
      case 'thaimhung':
        return shortName;
      case 'viewer':
        return shortName;
      default:
        return shortName;
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
    final isPrivilegedUser =
        widget.role == 'reporter' || widget.role == 'responder';
    const inputHeight = 48.0;

    return Dismissible(
      key: ValueKey('chat_dismiss_${widget.videoId}'),
      direction: DismissDirection.startToEnd, // ปัดไปทางขวาเพื่อปิด
      onDismissed: (_) {
        widget.onClose();
      },
      child: Column(
        // ✅ ใช้ min — เดิมเป็น max ทำให้ Column ยืดขึ้นไปถึงใต้กล่องยอดนิยม
        // (ตาม maxHeight) แม้ไม่มีข้อความ แล้วพื้นที่ล่องหนนั้นดูดกลืนการ tap
        // บังปุ่มส่งกำลังใจ/เปิดรับบริจาคและแผนที่ — ผู้ใช้ต้องปิดแชทก่อน
        // จึงจะกดได้ ด้วย min แชทจะหุ้มเนื้อหาเท่านั้น แตะพื้นที่ว่างผ่านทะลุ
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          // ── Top Bar ──
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              // ── Filter Toggle (สำหรับผู้แจ้งและเจ้าหน้าที่) ──
              if (isPrivilegedUser) ...[
                Container(
                  padding: const EdgeInsets.only(
                    left: 8,
                    right: 2,
                    top: 4,
                    bottom: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.45),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: _isFilterActive
                          ? Colors.lightBlueAccent.withOpacity(0.5)
                          : Colors.white24,
                      width: 0.5,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _isFilterActive
                            ? Icons.filter_alt
                            : Icons.filter_alt_outlined,
                        color: _isFilterActive
                            ? Colors.lightBlueAccent
                            : Colors.white70,
                        size: 14,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'ผู้แจ้ง & จนท.',
                        style: TextStyle(
                          fontFamily: 'Sukhumvit Set',
                          color: _isFilterActive
                              ? Colors.white
                              : Colors.white70,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 2),
                      SizedBox(
                        height: 18,
                        width: 32,
                        child: Transform.scale(
                          scale: 0.55,
                          child: Switch(
                            value: _isFilterActive,
                            activeColor: Colors.white,
                            activeTrackColor: Colors.blueAccent,
                            inactiveThumbColor: Colors.white70,
                            inactiveTrackColor: Colors.white24,
                            onChanged: (val) {
                              setState(() => _isFilterActive = val);
                              if (val) _scrollToBottom();
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
              ],

              // ── Close button ──
              GestureDetector(
                onTap: widget.onClose,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.45),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.3),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                  child: const Icon(Icons.close, color: Colors.white, size: 16),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),

          // ── รายการข้อความ ──
          // รายการข้อความขยายจากบนลงล่าง ฟองข้อความอยู่เหนือ input โดยตรง
          Flexible(child: _buildMessageList()),

          // ── ปุ่ม "เลื่อน" แสดงเมื่อเลื่อนอ่านข้อความเก่าขึ้นไป ──
          if (_showScrollToBottom)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Align(
                alignment: Alignment.center,
                child: _buildScrollToBottomButton(),
              ),
            ),

          // ── Input bar ──
          _buildInputArea(inputHeight),
        ],
      ),
    );
  }

  Widget _buildMessageList() {
    if (_isLoadingHistory) {
      return const Center(
        heightFactor: 1.0,
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              color: Colors.white54,
              strokeWidth: 2,
            ),
          ),
        ),
      );
    }

    final displayMessages = _isFilterActive
        ? _messages
              .where((m) => m['role'] == 'reporter' || m['role'] == 'responder')
              .toList()
        : _messages;

    if (displayMessages.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Align(
          alignment: Alignment.center,
          heightFactor: 1.0,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.35),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              _isFilterActive
                  ? 'ยังไม่มีข้อความจากกลุ่มเจ้าหน้าที่'
                  : 'ยังไม่มีการสนทนา',
              style: TextStyle(
                color: Colors.white.withOpacity(0.6),
                fontSize: 12,
              ),
            ),
          ),
        ),
      );
    }

    return Scrollbar(
      controller: _scrollController,
      thumbVisibility: true,
      child: ListView.builder(
        controller: _scrollController,
        shrinkWrap: true,
        physics: const ClampingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        itemCount: displayMessages.length,
        itemBuilder: (context, index) {
          final msg = displayMessages[index];
          final isMe = msg['userId'] == widget.userId;

          bool showLabel = true;
          if (index > 0) {
            final prevMsg = displayMessages[index - 1];
            if (prevMsg['userId'] == msg['userId']) {
              showLabel = false;
            }
          }

          return _buildBubble(msg, isMe, showLabel, index);
        },
      ),
    );
  }

  // ── Chat Bubble ลอยบนแผนที่ ──
  Widget _buildBubble(
    Map<String, dynamic> msg,
    bool isMe,
    bool showLabel,
    int index,
  ) {
    final role = msg['role'] ?? 'viewer';
    final professionName = msg['professionName'] as String?;
    final rawName = msg['userName'] ?? 'Unknown';
    final shortName = _formatShortName(rawName);

    final color = _roleColor(role);
    final label = _roleLabel(role, shortName, professionName: professionName);
    final content = msg['content'] ?? '';
    final time = _formatTimestamp(msg['timestamp']);

    final bool isViewerOrThaimhung = role == 'viewer' || role == 'thaimhung';

    return Padding(
      padding: EdgeInsets.only(bottom: 2, top: showLabel ? 6 : 0),
      child: Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Column(
          crossAxisAlignment: isMe
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── sender label ──
            if (showLabel)
              Padding(
                padding: EdgeInsets.only(
                  left: isMe ? 0 : 4,
                  right: isMe ? 4 : 0,
                  bottom: 2,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!isMe) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.85),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          label,
                          style: const TextStyle(
                            fontFamily: 'Sukhumvit Set',
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      if (!isViewerOrThaimhung) ...[
                        const SizedBox(width: 4),
                        Text(
                          shortName,
                          style: TextStyle(
                            fontFamily: 'Sukhumvit Set',
                            color: Colors.white.withOpacity(0.9),
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            shadows: [
                              Shadow(
                                color: Colors.black.withOpacity(0.8),
                                blurRadius: 4,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ] else ...[
                      if (!isViewerOrThaimhung) ...[
                        Text(
                          shortName,
                          style: TextStyle(
                            fontFamily: 'Sukhumvit Set',
                            color: Colors.white.withOpacity(0.9),
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            shadows: [
                              Shadow(
                                color: Colors.black.withOpacity(0.8),
                                blurRadius: 4,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 4),
                      ],
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.85),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          label,
                          style: const TextStyle(
                            fontFamily: 'Sukhumvit Set',
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),

            // ── bubble body ──
            // ✅ กว้างพอดีข้อความ (fit-content) — เดิม width: double.infinity
            // ทำให้พื้นหลังฟองเต็มความกว้างแนวนอนเสมอ ตอนนี้จำกัด maxWidth
            // ~78% ของจอ ฟองสั้นหุ้มข้อความพอดี ฟองยาวขยายถึงเพดานแล้วตัดคำ
            ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.78,
              ),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                decoration: BoxDecoration(
                  color: isMe
                      ? color.withOpacity(0.15)
                      : Colors.black.withOpacity(0.52),
                  borderRadius: BorderRadius.only(
                    topLeft: showLabel && !isMe
                        ? Radius.zero
                        : const Radius.circular(14),
                    topRight: showLabel && isMe
                        ? Radius.zero
                        : const Radius.circular(14),
                    bottomLeft: const Radius.circular(14),
                    bottomRight: const Radius.circular(14),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.35),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                  border: Border.all(
                    color: isMe
                        ? color.withOpacity(0.4)
                        : Colors.white.withOpacity(0.12),
                    width: 0.5,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      content,
                      maxLines: _expandedMessages[index] == true ? null : 3,
                      overflow: _expandedMessages[index] == true
                          ? TextOverflow.visible
                          : TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Sukhumvit Set',
                        color: color,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        height: 1.15,
                        shadows: const [
                          Shadow(color: Colors.black54, blurRadius: 3),
                        ],
                      ),
                    ),
                    if (content.length > 60 &&
                        _expandedMessages[index] != true)
                      GestureDetector(
                        onTap: () =>
                            setState(() => _expandedMessages[index] = true),
                        child: const Padding(
                          padding: EdgeInsets.only(top: 4),
                          child: Text(
                            '...อ่านเพิ่มเติม',
                            style: TextStyle(
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

            // ── timestamp ──
            Padding(
              padding: const EdgeInsets.only(top: 2, left: 4, right: 4),
              child: Text(
                time,
                style: TextStyle(
                  fontFamily: 'Sukhumvit Set',
                  color: Colors.white.withOpacity(0.55),
                  fontSize: 9,
                  shadows: [
                    Shadow(color: Colors.black.withOpacity(0.7), blurRadius: 3),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Input area ลอยบนแผนที่ ──
  Widget _buildInputArea(double inputHeight) {
    return Align(
      alignment: Alignment.centerRight,
      child: FractionallySizedBox(
        widthFactor: 0.56,
        child: Container(
          height: inputHeight,
          margin: const EdgeInsets.only(top: 4),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: Colors
                .white, // เปลี่ยนพื้นหลังเป็นสีขาวเพื่อให้ตัวหนังสือสีดำเห็นชัด
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: Colors.white.withOpacity(0.8)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 12,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _messageController,
                  style: const TextStyle(
                    fontFamily: 'Sukhumvit Set',
                    color: Colors.black,
                    fontSize: 13,
                  ), // เปลี่ยนตัวอักษรเป็นสีดำ
                  maxLines: 1,
                  enableInteractiveSelection:
                      false, // 🚫 ป้องกันการกดค้างเพื่อ Paste
                  contextMenuBuilder: (context, editableTextState) =>
                      const SizedBox.shrink(), // 🚫 ซ่อน Context Menu (Cut, Copy, Paste)
                  decoration: InputDecoration(
                    hintText: 'พิมพ์ข้อความ...',
                    hintStyle: const TextStyle(
                      fontFamily: 'Sukhumvit Set',
                      color: Colors.black54,
                      fontSize: 13,
                    ), // เปลี่ยนสี hint เป็นเทาเข้ม
                    counterText: '', // ซ่อน counter default
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                  ),
                  maxLength: _maxChars,
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
                      BoxShadow(
                        color: const Color(0xFF007AFF).withOpacity(0.4),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.send_rounded,
                    color: Colors.white,
                    size: 17,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
