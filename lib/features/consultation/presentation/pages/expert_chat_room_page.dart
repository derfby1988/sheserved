import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../services/service_locator.dart';
import '../../../../services/auth_service.dart';
import '../../../../features/auth/data/repositories/user_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../chat/data/models/chat_models.dart';
import '../../data/repositories/consultation_repository.dart';
import '../../../../shared/widgets/widgets.dart';

// ─── Model: Rich consultation entry with patient info ─────────────────────────
import '../../data/models/consultation_entry.dart';
import '../../data/models/local_chat_message.dart';

class ExpertChatRoomPage extends StatefulWidget {
  final ConsultationEntry entry;
  const ExpertChatRoomPage({super.key, required this.entry});

  @override
  State<ExpertChatRoomPage> createState() => _ExpertChatRoomPageState();
}

class _ExpertChatRoomPageState extends State<ExpertChatRoomPage> {
  final _chatRepo = ServiceLocator.instance.chatRepository;
  final _currentUser = ServiceLocator.instance.currentUser;

  final TextEditingController _msgController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  List<LocalChatMessage> _messages = [];
  bool _isLoading = true;
  bool _isSending = false;
  StreamSubscription? _messagesSub;

  @override
  void initState() {
    super.initState();
    _loadMessages();
    _subscribeToMessages();
  }

  @override
  void dispose() {
    _messagesSub?.cancel();
    _msgController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadMessages() async {
    setState(() => _isLoading = true);
    try {
      // Ensure room exists and provider is in participants
      await _ensureProviderInRoom();

      final chatMessages = await _chatRepo.getMessages(widget.entry.roomId);
      if (mounted) {
        final myId = _currentUser?.id;
        setState(() {
          _messages = chatMessages
              .map(
                (m) => LocalChatMessage(
                  content: m.content,
                  isMe: m.senderId == myId,
                  sentAt: m.createdAt,
                  type: m.type,
                ),
              )
              .toList();
          _isLoading = false;
        });
        _scrollToBottom();
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _subscribeToMessages() {
    final roomId = widget.entry.roomId;
    _messagesSub = _chatRepo.streamMessages(roomId).listen((newMessages) {
      if (mounted) {
        final myId = _currentUser?.id;
        setState(() {
          _messages = newMessages
              .map(
                (m) => LocalChatMessage(
                  content: m.content,
                  isMe: m.senderId == myId,
                  sentAt: m.createdAt,
                  type: m.type,
                ),
              )
              .toList();
        });
        _scrollToBottom();
      }
    });
  }

  /// Ensure chat room exists and provider is listed as a participant
  Future<void> _ensureProviderInRoom() async {
    final providerId = _currentUser?.id;
    if (providerId == null) return;

    try {
      final supabase = Supabase.instance.client;
      final roomId = widget.entry.roomId;

      final existing = await supabase
          .from('chat_rooms')
          .select('id, participant_ids')
          .eq('id', roomId)
          .maybeSingle()
          .timeout(const Duration(seconds: 5));

      if (existing == null) {
        // Room doesn't exist yet — create it with provider
        await supabase
            .from('chat_rooms')
            .insert({
              'id': roomId,
              'participant_ids': [providerId],
              'last_message': null,
              'updated_at': DateTime.now().toIso8601String(),
            })
            .timeout(const Duration(seconds: 5));
        debugPrint('ExpertChat: Created room $roomId');
      } else {
        // Room exists — add provider to participants if not already in
        final participants = List<String>.from(
          existing['participant_ids'] ?? [],
        );
        if (!participants.contains(providerId)) {
          participants.add(providerId);
          await supabase
              .from('chat_rooms')
              .update({
                'participant_ids': participants,
                'updated_at': DateTime.now().toIso8601String(),
              })
              .eq('id', roomId)
              .timeout(const Duration(seconds: 5));
          debugPrint('ExpertChat: Added provider $providerId to room $roomId');
        }
      }
    } catch (e) {
      debugPrint('ExpertChat: Could not ensure room (non-blocking): $e');
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage() async {
    final text = _msgController.text.trim();
    if (text.isEmpty || _isSending) return;
    setState(() {
      _isSending = true;
      _messages.add(
        LocalChatMessage(
          content: text,
          isMe: true,
          sentAt: DateTime.now(),
          type: 'text',
        ),
      );
    });
    _msgController.clear();
    _scrollToBottom();

    try {
      final message = ChatMessage(
        id: const Uuid().v4(),
        roomId: widget.entry.roomId,
        senderId: _currentUser?.id ?? 'expert',
        content: text,
        createdAt: DateTime.now(),
        type: 'text',
        status: MessageStatus.sent,
      );
      await _chatRepo.sendMessage(message);
    } catch (e) {
      debugPrint('ExpertChat: send error $e');
    }

    if (mounted) setState(() => _isSending = false);
  }

  // Provider เสร็จงาน → คืนสถานะ online + เปลี่ยน request เป็น completed
  Future<void> _finishJob() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'เสร็จสิ้นการให้บริการ?',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'สถานะของคุณจะกลับเป็น "พร้อมรับงาน" และคำร้องจะถูกปิด',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'ยกเลิก',
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.success,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('เสร็จสิ้น'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final authUser = AuthService.instance.currentUser;
    if (authUser == null) return;

    final userRepo = UserRepository(Supabase.instance.client);
    final consultRepo = ServiceLocator.instance.consultationRepository;

    // อัปเดต request → completed
    await consultRepo.updateStatus(widget.entry.id, 'completed');
    // คืนสถานะ provider → online
    await userRepo.setAvailabilityStatus(authUser.id, 'online');

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ เสร็จสิ้น! สถานะของคุณกลับเป็นพร้อมรับงานแล้ว'),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: Colors.white,
            size: 20,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: Colors.white.withOpacity(0.2),
              child: Text(
                widget.entry.patientName.isNotEmpty
                    ? widget.entry.patientName[0].toUpperCase()
                    : 'P',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.entry.patientName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  Text(
                    widget.entry.packageName,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.7),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          // ปุ่มเสร็จงาน
          TextButton.icon(
            onPressed: _finishJob,
            icon: const Icon(
              Icons.done_all_rounded,
              color: Colors.white,
              size: 18,
            ),
            label: const Text(
              'เสร็จงาน',
              style: TextStyle(color: Colors.white, fontSize: 12),
            ),
          ),
          IconButton(
            icon: const Icon(
              Icons.info_outline_rounded,
              color: Colors.white,
              size: 22,
            ),
            onPressed: _showPatientSheet,
          ),
        ],
      ),
      body: Column(
        children: [
          // Patient info banner
          _buildBanner(),

          // Messages
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.primary),
                  )
                : _messages.isEmpty
                ? _buildEmptyChat()
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    itemCount: _messages.length,
                    itemBuilder: (ctx, i) => _buildBubble(_messages[i]),
                  ),
          ),

          _buildInput(),
        ],
      ),
    ),
    );
  }

  Widget _buildBanner() {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(
            Icons.medical_services_outlined,
            color: AppColors.primary,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: const TextStyle(fontSize: 12, color: Colors.black87),
                children: [
                  TextSpan(
                    text: widget.entry.patientName,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const TextSpan(text: ' · '),
                  TextSpan(
                    text: widget.entry.packageName,
                    style: const TextStyle(color: AppColors.primary),
                  ),
                  const TextSpan(text: ' · '),
                  TextSpan(
                    text: widget.entry.bodyArea,
                    style: const TextStyle(
                      color: AppColors.warning,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBubble(LocalChatMessage msg) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Align(
        alignment: msg.isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.72,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: msg.isMe ? AppColors.primary : Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: Radius.circular(msg.isMe ? 16 : 4),
              bottomRight: Radius.circular(msg.isMe ? 4 : 16),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.07),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: msg.isMe
                ? CrossAxisAlignment.end
                : CrossAxisAlignment.start,
            children: [
              if (!msg.isMe)
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Text(
                    widget.entry.patientName,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              Text(
                msg.content,
                style: TextStyle(
                  color: msg.isMe ? Colors.white : Colors.black87,
                  fontSize: 14,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                DateFormat('HH:mm').format(msg.sentAt),
                style: TextStyle(
                  fontSize: 9,
                  color: msg.isMe
                      ? Colors.white.withOpacity(0.6)
                      : Colors.grey.shade400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyChat() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.chat_bubble_outline,
              color: AppColors.primary,
              size: 36,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'เริ่มต้นการสนทนากับผู้ป่วย',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 15,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'พิมพ์คำแนะนำได้เลยด้านล่างครับ',
            style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildInput() {
    final hasText = _msgController.text.isNotEmpty;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 28),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 10,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 46,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: const Color(0xFFF5F7F5),
                borderRadius: BorderRadius.circular(23),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: TextField(
                controller: _msgController,
                style: const TextStyle(color: Colors.black87, fontSize: 14),
                decoration: const InputDecoration(
                  hintText: 'ให้คำแนะนำด้านสุขภาพ...',
                  hintStyle: TextStyle(color: Colors.grey, fontSize: 14),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(vertical: 13),
                ),
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _sendMessage(),
              ),
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: _sendMessage,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              height: 46,
              width: 46,
              decoration: BoxDecoration(
                color: hasText ? AppColors.primary : Colors.grey.shade300,
                shape: BoxShape.circle,
                boxShadow: hasText
                    ? [
                        BoxShadow(
                          color: AppColors.primary.withOpacity(0.4),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ]
                    : [],
              ),
              child: _isSending
                  ? const Padding(
                      padding: EdgeInsets.all(13),
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(
                      Icons.send_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
            ),
          ),
        ],
      ),
    );
  }

  void _showPatientSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'ข้อมูลผู้ป่วย',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            const SizedBox(height: 16),
            _infoTile(
              Icons.person_outline,
              'ชื่อ-นามสกุล',
              widget.entry.patientName,
            ),
            _infoTile(
              Icons.spa_outlined,
              'แพ็คเกจที่เลือก',
              widget.entry.packageName,
            ),
            _infoTile(
              Icons.location_on_outlined,
              'บริเวณที่พบอาการ',
              widget.entry.bodyArea,
            ),
            _infoTile(
              Icons.payments_outlined,
              'ค่าใช้จ่าย',
              '${widget.entry.price.toInt()} บาท',
            ),
            _infoTile(
              Icons.calendar_today_outlined,
              'วันที่ร้องขอ',
              DateFormat('d MMMM yyyy  HH:mm').format(widget.entry.requestedAt),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoTile(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: AppColors.primary, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                ),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

