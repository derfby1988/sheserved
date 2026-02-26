import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:uuid/uuid.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../services/service_locator.dart';
import '../../data/models/consultation_request_model.dart';
import '../../../../features/chat/data/models/chat_models.dart';

class ChartBoardPage extends StatefulWidget {
  final ConsultationRequestModel request;

  const ChartBoardPage({super.key, required this.request});

  @override
  State<ChartBoardPage> createState() => _ChartBoardPageState();
}

class _ChartBoardPageState extends State<ChartBoardPage>
    with TickerProviderStateMixin {
  final _chatRepository = ServiceLocator.instance.chatRepository;
  final _currentUser = ServiceLocator.instance.currentUser;
  final TextEditingController _msgController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final _audioRecorder = AudioRecorder();

  String? _consultationRoomId;

  List<ChatMessage> _messages = [];
  bool _isChatLoading = true;
  bool _isRecording = false;
  bool _isSending = false;
  StreamSubscription? _messagesSub;

  // Animation controllers
  late AnimationController _fadeController;
  late AnimationController _slideController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  // Pain level options
  final List<Map<String, dynamic>> painLevels = [
    {'label': 'ไม่มี', 'color': const Color(0xFF4CAF50), 'icon': Icons.sentiment_very_satisfied},
    {'label': 'เล็กน้อย', 'color': const Color(0xFF8BC34A), 'icon': Icons.sentiment_satisfied},
    {'label': 'ปานกลาง', 'color': const Color(0xFFFFC107), 'icon': Icons.sentiment_neutral},
    {'label': 'มาก', 'color': const Color(0xFFFF9800), 'icon': Icons.sentiment_dissatisfied},
    {'label': 'มากที่สุด', 'color': const Color(0xFFF44336), 'icon': Icons.sentiment_very_dissatisfied},
  ];
  String? _selectedPain;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _slideController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
    _fadeAnimation =
        CurvedAnimation(parent: _fadeController, curve: Curves.easeIn);
    _slideAnimation = Tween<Offset>(
            begin: const Offset(0, 0.3), end: Offset.zero)
        .animate(
            CurvedAnimation(parent: _slideController, curve: Curves.easeOut));

    _initChat();
  }

  Future<void> _initChat() async {
    setState(() => _isChatLoading = true);

    try {
      final currentUserId = _currentUser?.id;
      if (currentUserId == null) {
        // No user logged in — show chat in offline demo mode
        setState(() {
          _messages = [];
          _isChatLoading = false;
        });
        _fadeController.forward();
        _slideController.forward();
        return;
      }

      // Use the current user's ID if the request hasn't been saved with a UID yet
      final patientId = widget.request.userId.isNotEmpty 
          ? widget.request.userId 
          : currentUserId;
      final roomId = 'consult_${patientId.substring(0, 8)}';
      debugPrint('ChartBoardPage: Entering roomId: $roomId for patientId: $patientId');

      // Ensure the chat room record exists in the DB
      await _ensureConsultationRoom(roomId, currentUserId);

      // Load messages (with fallback to empty if room doesn't exist yet)
      List<ChatMessage> messages = [];
      try {
        messages = await _chatRepository.getMessages(roomId);
      } catch (_) {
        messages = [];
      }

      if (mounted) {
        setState(() {
          _consultationRoomId = roomId;
          _messages = messages;
          _isChatLoading = false;
        });

        // Subscribe to realtime updates
        _messagesSub = _chatRepository
            .streamMessages(roomId)
            .listen((updatedMessages) {
          if (mounted) {
            setState(() => _messages = updatedMessages);
            _scrollToBottom();
          }
        }, onError: (_) {});

        _fadeController.forward();
        _slideController.forward();
        _scrollToBottom();
      }
    } catch (e) {
      debugPrint('ChartBoardPage: Init error: $e');
      if (mounted) {
        setState(() => _isChatLoading = false);
        _fadeController.forward();
        _slideController.forward();
      }
    }
  }

  /// Ensure the consultation chat room exists in chat_rooms table
  Future<void> _ensureConsultationRoom(String roomId, String currentUserId) async {
    try {
      final supabase = Supabase.instance.client;
      // Check if room already exists
      final existing = await supabase
          .from('chat_rooms')
          .select('id')
          .eq('id', roomId)
          .maybeSingle()
          .timeout(const Duration(seconds: 5));

      if (existing == null) {
        // Create room with the patient's ID as participant
        await supabase.from('chat_rooms').insert({
          'id': roomId,
          'participant_ids': [currentUserId],
          'last_message': null,
          'updated_at': DateTime.now().toIso8601String(),
        }).timeout(const Duration(seconds: 5));
        debugPrint('ChartBoardPage: Created consultation room: $roomId');
      } else {
        debugPrint('ChartBoardPage: Room already exists: $roomId');
      }
    } catch (e) {
      debugPrint('ChartBoardPage: Could not ensure room (non-blocking): $e');
      // Non-blocking — messages can still be sent even if room record fails
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage() async {
    final text = _msgController.text.trim();
    if (text.isEmpty || _isSending) return;

    setState(() => _isSending = true);

    final roomId = _consultationRoomId ?? 'consultation_demo';

    final message = ChatMessage(
      id: const Uuid().v4(),
      roomId: roomId,
      senderId: _currentUser?.id ?? 'demo_user',
      content: text,
      createdAt: DateTime.now(),
      type: 'text',
      status: MessageStatus.sent,
    );

    _msgController.clear();
    setState(() {
      // Optimistic update — show immediately
      _messages = [..._messages, message];
    });
    _scrollToBottom();

    try {
      await _chatRepository.sendMessage(message);
    } catch (e) {
      debugPrint('Send error: $e');
      // Keep message shown even if send fails (offline mode)
    }

    if (mounted) setState(() => _isSending = false);
  }

  Future<void> _pickAndSendImage() async {
    final picker = ImagePicker();
    final image =
        await picker.pickImage(source: ImageSource.gallery, imageQuality: 70);

    if (image != null && mounted) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('กำลังอัปโหลดรูปภาพ...'),
          duration: Duration(seconds: 2),
        ),
      );

      final file = File(image.path);
      final roomId = _consultationRoomId ?? 'consultation_demo';
      final url = await _chatRepository.uploadFile(file, 'chat/$roomId');

      if (url != null) {
        final message = ChatMessage(
          id: const Uuid().v4(),
          roomId: roomId,
          senderId: _currentUser?.id ?? 'demo_user',
          content: '[รูปภาพ]',
          createdAt: DateTime.now(),
          type: 'image',
          attachmentUrl: url,
          status: MessageStatus.sent,
        );
        await _chatRepository.sendMessage(message);
        if (mounted) setState(() => _messages = [..._messages, message]);
        _scrollToBottom();
      }
    }
  }

  Future<void> _startRecording() async {
    try {
      if (await _audioRecorder.hasPermission()) {
        final directory = await getTemporaryDirectory();
        final path =
            '${directory.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
        await _audioRecorder.start(const RecordConfig(), path: path);
        if (mounted) setState(() => _isRecording = true);
      }
    } catch (e) {
      debugPrint('Record start error: $e');
    }
  }

  Future<void> _stopRecording() async {
    try {
      final path = await _audioRecorder.stop();
      if (mounted) setState(() => _isRecording = false);

      if (path != null && _currentUser != null) {
        final file = File(path);
        final roomId = _consultationRoomId ?? 'consultation_demo';
        final url = await _chatRepository.uploadFile(file, 'chat/$roomId');

        if (url != null) {
          final message = ChatMessage(
            id: const Uuid().v4(),
            roomId: roomId,
            senderId: _currentUser!.id,
            content: '[ข้อความเสียง]',
            createdAt: DateTime.now(),
            type: 'voice',
            attachmentUrl: url,
            status: MessageStatus.sent,
          );
          await _chatRepository.sendMessage(message);
          if (mounted) setState(() => _messages = [..._messages, message]);
          _scrollToBottom();
        }
      }
    } catch (e) {
      debugPrint('Record stop error: $e');
    }
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _slideController.dispose();
    _msgController.dispose();
    _scrollController.dispose();
    _audioRecorder.dispose();
    _messagesSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'ระบุอาการ',
          style: TextStyle(
            color: Color(0xFF2D5A1B),
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: AppColors.primary, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          // === TOP SECTION: Pain Level Selector ===
          Expanded(
            flex: 5,
            child: Container(
              color: const Color(0xFFF5F7FA),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF4A8B2C).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.medical_services_outlined,
                              color: Color(0xFF4A8B2C), size: 20),
                        ),
                        const SizedBox(width: 10),
                        const Text(
                          'คุณรู้สึกเจ็บปวดระดับใด?',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF2D5A1B),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Pain Level Buttons
                    Expanded(
                      child: GridView.count(
                        crossAxisCount: 3,
                        childAspectRatio: 1.5,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                        physics: const NeverScrollableScrollPhysics(),
                        padding: EdgeInsets.zero,
                        children: [
                          ...painLevels.map((level) {
                            final isSelected = _selectedPain == level['label'];
                            final color = level['color'] as Color;
                            return GestureDetector(
                              onTap: () =>
                                  setState(() => _selectedPain = level['label']),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                curve: Curves.easeOut,
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? color.withOpacity(0.15)
                                      : Colors.white,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color:
                                        isSelected ? color : Colors.grey.shade200,
                                    width: isSelected ? 2 : 1,
                                  ),
                                  boxShadow: isSelected
                                      ? [
                                          BoxShadow(
                                            color: color.withOpacity(0.3),
                                            blurRadius: 8,
                                            offset: const Offset(0, 3),
                                          )
                                        ]
                                      : [
                                          BoxShadow(
                                            color: Colors.black.withOpacity(0.04),
                                            blurRadius: 4,
                                            offset: const Offset(0, 2),
                                          )
                                        ],
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      level['icon'] as IconData,
                                      color: isSelected ? color : Colors.grey,
                                      size: 22,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      level['label'] as String,
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: isSelected
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                        color: isSelected ? color : Colors.grey.shade600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }),
                        ],
                      ),
                    ),

                    // Selected state indicator
                    if (_selectedPain != null)
                      AnimatedOpacity(
                        opacity: _selectedPain != null ? 1 : 0,
                        duration: const Duration(milliseconds: 300),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF4A8B2C).withOpacity(0.08),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.check_circle,
                                  color: Color(0xFF4A8B2C), size: 16),
                              const SizedBox(width: 8),
                              Text(
                                'เลือกแล้ว: ความเจ็บปวดระดับ "$_selectedPain"',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF4A8B2C),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),

          // === BOTTOM SECTION: Chat Panel ===
          Expanded(
            flex: 6,
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF4A8B2C),
                    Color(0xFF2D6A1F),
                    Color(0xFF1A4D10),
                  ],
                ),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(32),
                  topRight: Radius.circular(32),
                ),
              ),
              child: ClipRRect(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(32),
                  topRight: Radius.circular(32),
                ),
                child: Column(
                  children: [
                    // Chat Header
                    _buildChatHeader(),

                    // Messages List
                    Expanded(child: _buildMessagesList()),

                    // Input Area
                    _buildChatInput(),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChatHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        border: Border(
          bottom: BorderSide(color: Colors.white.withOpacity(0.1)),
        ),
      ),
      child: Row(
        children: [
          // Avatar stack
          SizedBox(
            width: 48,
            height: 32,
            child: Stack(
              children: [
                Positioned(
                  left: 0,
                  child: CircleAvatar(
                    radius: 14,
                    backgroundColor: Colors.white.withOpacity(0.9),
                    child: const Icon(Icons.person, size: 14, color: Color(0xFF4A8B2C)),
                  ),
                ),
                Positioned(
                  left: 18,
                  child: CircleAvatar(
                    radius: 14,
                    backgroundColor: Colors.greenAccent.withOpacity(0.9),
                    child: const Icon(Icons.medical_services, size: 12, color: Color(0xFF2D6A1F)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'แชทกลุ่มปรึกษาผู้เชี่ยวชาญ',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                Text(
                  'Expert Group · ปลอดภัยและเป็นส่วนตัว',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.7),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          // Online indicator
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.greenAccent.withOpacity(0.2),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.greenAccent.withOpacity(0.4)),
            ),
            child: Row(
              children: [
                Container(
                  width: 6, height: 6,
                  decoration: const BoxDecoration(
                    color: Colors.greenAccent, shape: BoxShape.circle),
                ),
                const SizedBox(width: 4),
                const Text(
                  'ออนไลน์',
                  style: TextStyle(color: Colors.greenAccent, fontSize: 10, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessagesList() {
    if (_isChatLoading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(
              valueColor:
                  AlwaysStoppedAnimation<Color>(Colors.white.withOpacity(0.8)),
              strokeWidth: 2,
            ),
            const SizedBox(height: 12),
            Text(
              'กำลังเชื่อมต่อห้องแชท...',
              style: TextStyle(
                  color: Colors.white.withOpacity(0.7), fontSize: 13),
            ),
          ],
        ),
      );
    }

    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          itemCount: _messages.length + 1, // +1 for payment card at bottom
          itemBuilder: (context, index) {
            if (index == _messages.length) {
              return _buildPaymentCard();
            }
            if (_messages.isEmpty) return const SizedBox.shrink();
            final msg = _messages[index];
            final isMe = msg.senderId == (_currentUser?.id ?? 'demo_user');
            return _buildMessageBubble(msg, isMe);
          },
        ),
      ),
    );
  }

  Widget _buildMessageBubble(ChatMessage message, bool isMe) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Row(
          mainAxisAlignment:
              isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (!isMe) ...[
              CircleAvatar(
                radius: 14,
                backgroundColor: Colors.white.withOpacity(0.9),
                child: const Icon(Icons.medical_services,
                    size: 12, color: Color(0xFF4A8B2C)),
              ),
              const SizedBox(width: 6),
            ],
            Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.62,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                color: isMe
                    ? Colors.white
                    : Colors.white.withOpacity(0.15),
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomLeft: Radius.circular(isMe ? 18 : 4),
                  bottomRight: Radius.circular(isMe ? 4 : 18),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment:
                    isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: [
                  if (message.type == 'image' && message.attachmentUrl != null)
                    ClipRRect(
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
                              child: CircularProgressIndicator(strokeWidth: 2)),
                        ),
                      ),
                    )
                  else if (message.type == 'voice' &&
                      message.attachmentUrl != null)
                    _MiniVoicePlayer(
                        url: message.attachmentUrl!, isMe: isMe)
                  else
                    Text(
                      message.content,
                      style: TextStyle(
                        color: isMe ? Colors.black87 : Colors.white,
                        fontSize: 14,
                        height: 1.4,
                      ),
                    ),
                  const SizedBox(height: 3),
                  Text(
                    '${message.createdAt.hour}:${message.createdAt.minute.toString().padLeft(2, '0')}',
                    style: TextStyle(
                      fontSize: 9,
                      color: isMe
                          ? Colors.grey.shade500
                          : Colors.white.withOpacity(0.55),
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

  Widget _buildPaymentCard() {
    final bool isReady = _selectedPain != null;
    final color = isReady ? const Color(0xFF4A8B2C) : Colors.white;
    final textColor = isReady ? Colors.white : Colors.black;

    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 16),
      child: InkWell(
        onTap: isReady ? _submitConsultationRequest : null,
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: isReady 
                    ? const Color(0xFF4A8B2C).withOpacity(0.3) 
                    : Colors.black.withOpacity(0.05),
                blurRadius: 15,
                offset: const Offset(0, 8),
              ),
            ],
            border: Border.all(
              color: isReady 
                  ? const Color(0xFF4A8B2C).withOpacity(0.5)
                  : Colors.grey.shade200,
            ),
          ),
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: isReady ? Colors.white.withOpacity(0.2) : Colors.grey.shade100,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isReady ? Icons.check_circle : Icons.check_circle_outline,
                  color: isReady ? Colors.white : Colors.grey.shade300,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${widget.request.price.toInt()} บาท',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: textColor,
                      ),
                    ),
                    Text(
                      isReady 
                          ? 'ยืนยันและส่งคำรักษา' 
                          : 'กรุณาเลือกระดับความเจ็บปวดก่อน',
                      style: TextStyle(
                        fontSize: 13,
                        color: isReady 
                            ? Colors.white.withOpacity(0.9) 
                            : Colors.orange.shade800,
                        fontWeight: isReady ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios_rounded,
                color: isReady ? Colors.white.withOpacity(0.5) : Colors.grey.shade300,
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChatInput() {
    final hasText = _msgController.text.isNotEmpty;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        border: Border(
          top: BorderSide(color: Colors.white.withOpacity(0.1)),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Image button
          _buildInputIconButton(
            icon: Icons.image_outlined,
            onTap: _pickAndSendImage,
          ),
          const SizedBox(width: 8),

          // Text input
          Expanded(
            child: Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(22),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  )
                ],
              ),
              child: TextField(
                controller: _msgController,
                style: const TextStyle(color: Colors.black87, fontSize: 14),
                decoration: const InputDecoration(
                  hintText: 'ถามผู้เชี่ยวชาญ...',
                  hintStyle:
                      TextStyle(color: Colors.grey, fontSize: 14),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(vertical: 12),
                ),
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _sendMessage(),
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Send / Mic button
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            transitionBuilder: (child, anim) =>
                ScaleTransition(scale: anim, child: child),
            child: hasText
                ? _buildActionButton(
                    key: const ValueKey('send'),
                    icon: Icons.send_rounded,
                    color: Colors.white,
                    bgColor: const Color(0xFF4A8B2C),
                    onTap: _sendMessage,
                    isLoading: _isSending,
                  )
                : GestureDetector(
                    key: const ValueKey('mic'),
                    onLongPressStart: (_) => _startRecording(),
                    onLongPressEnd: (_) => _stopRecording(),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      height: 44,
                      width: 44,
                      decoration: BoxDecoration(
                        color: _isRecording
                            ? Colors.redAccent
                            : Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: (_isRecording ? Colors.redAccent : Colors.black)
                                .withOpacity(0.2),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          )
                        ],
                      ),
                      child: Icon(
                        _isRecording ? Icons.stop_rounded : Icons.mic,
                        color: _isRecording
                            ? Colors.white
                            : const Color(0xFF4A8B2C),
                        size: 20,
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputIconButton({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 40,
        width: 40,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.15),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withOpacity(0.2)),
        ),
        child: Icon(icon, color: Colors.white, size: 20),
      ),
    );
  }

  Widget _buildActionButton({
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
                offset: const Offset(0, 2))
          ],
        ),
        child: isLoading
            ? const Padding(
                padding: EdgeInsets.all(12),
                child: CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 2),
              )
            : Icon(icon, color: color, size: 20),
      ),
    );
  }

  void _submitConsultationRequest() async {
    if (_selectedPain == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('กรุณาระบุระดับความรู้สึกเจ็บปวดก่อนครับ'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Show loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: CircularProgressIndicator(color: Colors.white),
      ),
    );

    try {
      final currentUserId = _currentUser?.id;
      if (currentUserId == null) {
        throw Exception('กรุณาเลือกเข้าสู่ระบบใหม่อีกครั้ง');
      }

      // 1. Prepare final data
      final finalSymptomsChart = Map<String, dynamic>.from(widget.request.symptomsChart);
      finalSymptomsChart['pain_level'] = _selectedPain;

      // 2. Save to Repository
      final repo = ServiceLocator.instance.consultationRepository;
      await repo.createRequest(
        userId: currentUserId,
        packageId: widget.request.packageId,
        packageName: widget.request.packageName,
        price: widget.request.price,
        bodyArea: widget.request.bodyArea,
        symptomsChart: finalSymptomsChart,
        symptoms: widget.request.symptoms,
      );

      if (mounted) {
        Navigator.pop(context); // Close loading
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('ส่งคำปรึกษาสำเร็จ! กรุณารอผู้เชี่ยวชาญเข้าห้องแชทครับ'),
            backgroundColor: Color(0xFF4A8B2C),
          ),
        );
        // STAY in the current page instead of redirecting to home
        setState(() {
          // You might want to update a UI flag here to show "Waiting for Expert"
        });
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Close loading
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('เกิดข้อผิดพลาด: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }
}

// ────────────────────────────────────────────
// Mini Voice Player
// ────────────────────────────────────────────

class _MiniVoicePlayer extends StatefulWidget {
  final String url;
  final bool isMe;
  const _MiniVoicePlayer({required this.url, required this.isMe});

  @override
  State<_MiniVoicePlayer> createState() => _MiniVoicePlayerState();
}

class _MiniVoicePlayerState extends State<_MiniVoicePlayer> {
  late AudioPlayer _audioPlayer;
  bool _isPlaying = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;

  @override
  void initState() {
    super.initState();
    _audioPlayer = AudioPlayer();

    _audioPlayer.onPlayerStateChanged.listen((state) {
      if (mounted)
        setState(() => _isPlaying = state == PlayerState.playing);
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

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final iconColor = widget.isMe ? Colors.black87 : Colors.white;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: () async {
            if (_isPlaying) {
              await _audioPlayer.pause();
            } else {
              await _audioPlayer.play(UrlSource(widget.url));
            }
          },
          child: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: (widget.isMe ? Colors.black : Colors.white).withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(
              _isPlaying ? Icons.pause : Icons.play_arrow,
              color: iconColor,
              size: 18,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 100,
              child: LinearProgressIndicator(
                value: _duration.inMilliseconds > 0
                    ? _position.inMilliseconds / _duration.inMilliseconds
                    : 0.0,
                backgroundColor: iconColor.withOpacity(0.2),
                valueColor: AlwaysStoppedAnimation<Color>(iconColor),
                minHeight: 3,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 3),
            Text(
              _fmt(_isPlaying ? _position : _duration),
              style: TextStyle(
                  fontSize: 9,
                  color: iconColor.withOpacity(0.7)),
            ),
          ],
        ),
      ],
    );
  }
}
