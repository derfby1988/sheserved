import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:audioplayers/audioplayers.dart';
import '../../../../services/service_locator.dart';
import '../../../../core/constants/app_colors.dart';
import '../../data/models/chat_models.dart';
import 'package:uuid/uuid.dart';

class ChatRoomPage extends StatefulWidget {
  final String roomId;
  const ChatRoomPage({super.key, required this.roomId});

  @override
  State<ChatRoomPage> createState() => _ChatRoomPageState();
}

class _ChatRoomPageState extends State<ChatRoomPage> {
  final _chatRepository = ServiceLocator.instance.chatRepository;
  final _currentUser = ServiceLocator.instance.currentUser;
  final _webSocketService = ServiceLocator.instance.webSocketService;
  final TextEditingController _msgController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  
  StreamSubscription? _callInviteSub;
  StreamSubscription? _callAcceptSub;
  
  List<ChatMessage> _messages = [];
  bool _isLoading = true;
  List<ChatParticipant> _otherParticipants = [];
  bool _isOtherTyping = false;
  Timer? _typingTimer;

  final _audioRecorder = AudioRecorder();
  bool _isRecording = false;
  String? _recordingPath;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
    _listenForCalls();
  }

  Future<void> _loadInitialData() async {
    // 1. Load messages
    final msgs = await _chatRepository.getMessages(widget.roomId);
    
    // 2. Fetch other participants info
    final rooms = await _chatRepository.getChatRooms(_currentUser?.id ?? '');
    final room = rooms.firstWhere((r) => r.id == widget.roomId);
    final otherIds = room.participantIds.where((id) => id != _currentUser?.id).toList();
    
    final infos = <ChatParticipant>[];
    for (var id in otherIds) {
      final info = await _chatRepository.getParticipantInfo(id);
      if (info != null) infos.add(info);
    }

    if (mounted) setState(() => _otherParticipants = infos);

    if (mounted) {
      setState(() {
        _messages = msgs;
        _isLoading = false;
      });
      _scrollToBottom();
      _markMessagesAsRead(msgs);
    }
  }

  void _markMessagesAsRead(List<ChatMessage> messages) {
    if (_currentUser == null) return;
    for (var msg in messages) {
      if (msg.senderId != _currentUser!.id && !msg.readBy.containsKey(_currentUser!.id)) {
        _chatRepository.markMessageAsRead(msg.id, _currentUser!.id);
      }
    }
  }

  Future<void> _pickAndSendImage() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
    
    if (image != null && _currentUser != null) {
      final file = File(image.path);
      
      // Show loading indicator
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กำลังอัปโหลดรูปภาพ...')),
      );

      final url = await _chatRepository.uploadFile(file, 'chat/${widget.roomId}');
      
      if (url != null) {
        final newMessage = ChatMessage(
          id: const Uuid().v4(),
          roomId: widget.roomId,
          senderId: _currentUser!.id,
          content: '[รูปภาพ]',
          createdAt: DateTime.now(),
          type: 'image',
          attachmentUrl: url,
          attachmentType: 'image/jpeg',
          status: MessageStatus.sent,
        );

        final success = await _chatRepository.sendMessage(newMessage);
        if (!success && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('ส่งรูปภาพไม่สำเร็จ')),
          );
        }
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('อัปโหลดรูปภาพไม่สำเร็จ')),
        );
      }
    }
  }

  void _listenForCalls() {
    _callInviteSub = _webSocketService.callInviteStream.listen((data) {
      if (data['roomId'] == widget.roomId && data['callerId'] != _currentUser?.id) {
        _showIncomingCallDialog(data);
      }
    });

    _callAcceptSub = _webSocketService.callAcceptStream.listen((data) {
      if (data['roomId'] == widget.roomId && data['calleeId'] == _otherParticipant?.id) {
        // Navigate to LiveVdoPage as caller
        Navigator.pushNamed(context, '/live-vdo', arguments: {
          'roomId': widget.roomId,
          'isCaller': true,
          'otherParticipantName': _otherParticipant?.fullName ?? 'Expert',
        });
      }
    });
  }

  Future<void> _startRecording() async {
    try {
      if (await _audioRecorder.hasPermission()) {
        final directory = await getApplicationDocumentsDirectory();
        _recordingPath = '${directory.path}/record_${DateTime.now().millisecondsSinceEpoch}.m4a';
        
        const config = RecordConfig();
        await _audioRecorder.start(config, path: _recordingPath!);
        
        setState(() => _isRecording = true);
      }
    } catch (e) {
      debugPrint('Error starting record: $e');
    }
  }

  Future<void> _stopRecording() async {
    try {
      final path = await _audioRecorder.stop();
      setState(() => _isRecording = false);

      if (path != null && _currentUser != null) {
        final file = File(path);
        
        // Upload to Supabase
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('กำลังส่งข้อความเสียง...')),
        );

        final url = await _chatRepository.uploadFile(file, 'chat/${widget.roomId}');
        
        if (url != null) {
          final newMessage = ChatMessage(
            id: const Uuid().v4(),
            roomId: widget.roomId,
            senderId: _currentUser!.id,
            content: '[ข้อความเสียง]',
            createdAt: DateTime.now(),
            type: 'voice',
            attachmentUrl: url,
            attachmentType: 'audio/m4a',
            status: MessageStatus.sent,
          );

          await _chatRepository.sendMessage(newMessage);
        }
      }
    } catch (e) {
      debugPrint('Error stopping record: $e');
    }
  }

  void _showIncomingCallDialog(Map<String, dynamic> data) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('สายเรียกเข้า'),
        content: Text('${data['callerName']} กำลังเรียกวิดีโอ...'),
        actions: [
          TextButton(
            onPressed: () {
              _webSocketService.rejectCall(widget.roomId, _currentUser!.id);
              Navigator.pop(context);
            },
            child: const Text('ปฏิเสธ', style: TextStyle(color: Colors.red)),
          ),
          ElevatedButton(
            onPressed: () {
              _webSocketService.acceptCall(widget.roomId, _currentUser!.id);
              Navigator.pop(context);
              Navigator.pushNamed(context, '/live-vdo', arguments: {
                'roomId': widget.roomId,
                'isCaller': false,
                'otherParticipantName': data['callerName'],
              });
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: const Text('รับสาย'),
          ),
        ],
      ),
    );
  }

  void _startVideoCall() {
    if (_currentUser == null || _otherParticipant == null) return;
    
    _webSocketService.sendCallInvite(
      widget.roomId,
      _currentUser!.id,
      '${_currentUser!.firstName} ${_currentUser!.lastName}',
      _currentUser!.profileImageUrl,
    );

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('กำลังเรียกสาย...')),
    );
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

  Future<void> _sendMessage() async {
    if (_msgController.text.trim().isEmpty || _currentUser == null) return;

    final content = _msgController.text.trim();
    _msgController.clear();

    final newMessage = ChatMessage(
      id: const Uuid().v4(),
      roomId: widget.roomId,
      senderId: _currentUser!.id,
      content: content,
      createdAt: DateTime.now(),
      status: MessageStatus.sent,
    );

    final success = await _chatRepository.sendMessage(newMessage);
    if (!success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ส่งข้อความไม่สำเร็จ')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F7),
      appBar: AppBar(
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: Colors.white24,
              backgroundImage: (_otherParticipants.isNotEmpty && _otherParticipants.first.profileImageUrl != null)
                  ? NetworkImage(_otherParticipants.first.profileImageUrl!)
                  : null,
              child: (_otherParticipants.isEmpty || _otherParticipants.first.profileImageUrl == null)
                  ? const Icon(Icons.group, color: Colors.white, size: 20)
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _otherParticipants.length > 1 
                      ? 'แชทกลุ่ม (${_otherParticipants.length + 1})'
                      : _otherParticipants.isNotEmpty 
                        ? _otherParticipants.first.fullName 
                        : 'Expert Chat',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    _isOtherTyping 
                      ? 'ใครบางคนกำลังพิมพ์...' 
                      : _otherParticipants.length > 1 
                        ? _otherParticipants.map((p) => p.firstName).join(', ')
                        : 'Online',
                    style: TextStyle(
                      fontSize: 11,
                      color: _isOtherTyping ? Colors.white : Colors.greenAccent,
                      fontStyle: _isOtherTyping ? FontStyle.italic : FontStyle.normal,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: _startVideoCall,
            icon: const Icon(Icons.videocam),
            tooltip: 'วิดีโอคอล',
          ),
          IconButton(onPressed: () {}, icon: const Icon(Icons.more_vert)),
        ],
        backgroundColor: AppColors.primary,
        elevation: 0,
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                StreamBuilder<List<ChatMessage>>(
                  stream: _chatRepository.streamMessages(widget.roomId),
                  builder: (context, snapshot) {
                    if (snapshot.hasData) {
                      _messages = snapshot.data!;
                      _scrollToBottom();
                      _markMessagesAsRead(_messages);
                    }

                    if (_isLoading && _messages.isEmpty) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    return ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                      itemCount: _messages.length,
                      itemBuilder: (context, index) {
                        final msg = _messages[index];
                        final isMe = msg.senderId == _currentUser?.id;
                        return _MessageBubble(
                          message: msg, 
                          isMe: isMe,
                          otherParticipants: _otherParticipants,
                        );
                      },
                    );
                  },
                ),
                // Typing Indicator Stream
                if (_currentUser != null)
                  StreamBuilder<bool>(
                    stream: _chatRepository.streamAnyTyping(widget.roomId, _currentUser!.id),
                    builder: (context, snapshot) {
                      if (snapshot.hasData && snapshot.data != _isOtherTyping) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted) setState(() => _isOtherTyping = snapshot.data!);
                        });
                      }
                      return const SizedBox.shrink();
                    },
                  ),
              ],
            ),
          ),
          _buildInputArea(),
        ],
      ),
    );
  }

  Widget _buildInputArea() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            offset: const Offset(0, -2),
            blurRadius: 10,
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            IconButton(
              onPressed: _pickAndSendImage,
              icon: const Icon(Icons.add_circle_outline, color: AppColors.primary),
            ),
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0F0F0),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: TextField(
                  controller: _msgController,
                  decoration: const InputDecoration(
                    hintText: 'พิมพ์ข้อความ...',
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    fillColor: Colors.transparent,
                  ),
                  onChanged: (text) {
                    if (_currentUser == null) return;
                    _chatRepository.sendTypingStatus(widget.roomId, _currentUser!.id, true);
                    _typingTimer?.cancel();
                    _typingTimer = Timer(const Duration(seconds: 2), () {
                      _chatRepository.sendTypingStatus(widget.roomId, _currentUser!.id, false);
                    });
                  },
                  onSubmitted: (_) => _sendMessage(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            if (_msgController.text.isEmpty)
              GestureDetector(
                onLongPressStart: (_) => _startRecording(),
                onLongPressEnd: (_) => _stopRecording(),
                child: Container(
                  height: 48,
                  width: 48,
                  decoration: BoxDecoration(
                    color: _isRecording ? Colors.red : AppColors.primary,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _isRecording ? Icons.stop : Icons.mic,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              )
            else
              Container(
                decoration: const BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  onPressed: () {
                    _sendMessage();
                    if (_currentUser != null) {
                      _chatRepository.sendTypingStatus(widget.roomId, _currentUser!.id, false);
                    }
                  },
                  icon: const Icon(Icons.send, color: Colors.white, size: 20),
                ),
              ),
          ],
        ),
      ),
    );
  }
  void dispose() {
    _typingTimer?.cancel();
    _callInviteSub?.cancel();
    _callAcceptSub?.cancel();
    if (_currentUser != null) {
      _chatRepository.sendTypingStatus(widget.roomId, _currentUser!.id, false);
    }
    _msgController.dispose();
    _scrollController.dispose();
    _audioRecorder.dispose();
    super.dispose();
  }
}

class _MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final bool isMe;
  final List<ChatParticipant> otherParticipants;

  const _MessageBubble({
    required this.message, 
    required this.isMe,
    required this.otherParticipants,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        decoration: BoxDecoration(
          color: isMe ? AppColors.primary : Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isMe ? 16 : 0),
            bottomRight: Radius.circular(isMe ? 0 : 16),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              offset: const Offset(0, 1),
              blurRadius: 4,
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (message.type == 'image' && message.attachmentUrl != null)
              _buildImageContent(context),
            if (message.type == 'voice' && message.attachmentUrl != null)
              _VoiceMessageBubble(url: message.attachmentUrl!, isMe: isMe),
            if (message.type == 'text' || (message.content.isNotEmpty && message.content != '[รูปภาพ]' && message.content != '[ข้อความเสียง]'))
              Text(
                message.content,
                style: TextStyle(
                  color: isMe ? Colors.white : Colors.black87,
                  fontSize: 15,
                ),
              ),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${message.createdAt.hour}:${message.createdAt.minute.toString().padLeft(2, '0')}',
                  style: TextStyle(
                    color: (isMe ? Colors.white : Colors.black54).withOpacity(0.6),
                    fontSize: 10,
                  ),
                ),
                if (isMe) ...[
                  const SizedBox(width: 4),
                  Icon(
                    message.readBy.isNotEmpty ? Icons.done_all : Icons.done,
                    size: 12,
                    color: message.readBy.isNotEmpty ? Colors.blueAccent : Colors.white70,
                  ),
                ],
              ],
            ),
            if (isMe && message.readBy.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4.0),
                child: Text(
                  'อ่านโดย: ${_getReaderNames()}',
                  style: const TextStyle(fontSize: 9, color: Colors.blueAccent, fontWeight: FontWeight.bold),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _getReaderNames() {
    if (message.readBy.isEmpty) return '';
    final names = <String>[];
    for (var userId in message.readBy.keys) {
      final p = otherParticipants.firstWhere((p) => p.id == userId, orElse: () => ChatParticipant(id: userId, firstName: 'User', lastName: ''));
      names.add(p.firstName);
    }
    return names.join(', ');
  }

  Widget _buildImageContent(BuildContext context) {
    return GestureDetector(
      onTap: () {
        // TODO: Open full screen image
      },
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8.0),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: CachedNetworkImage(
            imageUrl: message.attachmentUrl!,
            placeholder: (context, url) => Container(
              height: 200,
              width: 200,
              color: Colors.grey[200],
              child: const Center(child: CircularProgressIndicator()),
            ),
            errorWidget: (context, url, error) => const Icon(Icons.error),
            fit: BoxFit.cover,
          ),
        ),
      ),
    );
  }
}

class _VoiceMessageBubble extends StatefulWidget {
  final String url;
  final bool isMe;

  const _VoiceMessageBubble({required this.url, required this.isMe});

  @override
  State<_VoiceMessageBubble> createState() => _VoiceMessageBubbleState();
}

class _VoiceMessageBubbleState extends State<_VoiceMessageBubble> {
  late AudioPlayer _audioPlayer;
  bool _isPlaying = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;

  @override
  void initState() {
    super.initState();
    _audioPlayer = AudioPlayer();

    _audioPlayer.onPlayerStateChanged.listen((state) {
      if (mounted) setState(() => _isPlaying = state == PlayerState.playing);
    });

    _audioPlayer.onDurationChanged.listen((d) {
      if (mounted) setState(() => _duration = d);
    });

    _audioPlayer.onPositionChanged.listen((p) {
      if (mounted) setState(() => _position = p);
    });

    _audioPlayer.onPlayerComplete.listen((_) {
      if (mounted) setState(() {
        _isPlaying = false;
        _position = Duration.zero;
      });
    });
  }

  Future<void> _togglePlayback() async {
    if (_isPlaying) {
      await _audioPlayer.pause();
    } else {
      await _audioPlayer.play(UrlSource(widget.url));
    }
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.isMe ? Colors.white : AppColors.primary;
    
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          onPressed: _togglePlayback,
          icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow, color: color),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
        ),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 120,
              child: LinearProgressIndicator(
                value: _duration.inMilliseconds > 0 
                  ? _position.inMilliseconds / _duration.inMilliseconds 
                  : 0.0,
                backgroundColor: color.withOpacity(0.2),
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _formatDuration(_isPlaying ? _position : _duration),
              style: TextStyle(color: color.withOpacity(0.7), fontSize: 10),
            ),
          ],
        ),
      ],
    );
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.toString().padLeft(2, '0');
    final seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}
