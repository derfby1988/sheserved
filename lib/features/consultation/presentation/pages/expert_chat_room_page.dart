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
import '../widgets/completion_checklist.dart';
import '../widgets/finish_job_warning_dialog.dart';
import '../../data/models/expert_completion_status.dart';

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

  // Expert completion tracking
  Map<String, dynamic> _completionStatus = {};
  bool _isCheckingCompletion = false;
  
  // Phase 6.8: Completion rules
  ExpertCompletionStatus? _expertCompletionStatus;
  bool _isCheckingExpertCompletion = false;

  @override
  void initState() {
    super.initState();
    _loadMessages();
    _subscribeToMessages();
    _loadCompletionStatus();
    _markReentered();
  }

  @override
  void dispose() {
    _messagesSub?.cancel();
    _msgController.dispose();
    _scrollController.dispose();
    _markLeft();
    super.dispose();
  }

  /// Mark this expert as re-entered the room
  void _markReentered() {
    final authUser = AuthService.instance.currentUser;
    if (authUser == null || widget.entry.id.isEmpty) return;
    final consultRepo = ServiceLocator.instance.consultationRepository;
    consultRepo.markExpertReentered(widget.entry.id, authUser.id).then((_) {
      debugPrint('ExpertChat: marked as re-entered');
    }).catchError((e) {
      debugPrint('ExpertChat: _markReentered error: $e');
    });
  }

  /// Mark this expert as left the room
  void _markLeft() {
    final authUser = AuthService.instance.currentUser;
    if (authUser == null || widget.entry.id.isEmpty) return;
    final consultRepo = ServiceLocator.instance.consultationRepository;
    consultRepo.markExpertLeft(widget.entry.id, authUser.id).then((_) {
      debugPrint('ExpertChat: marked as left');
    }).catchError((e) {
      debugPrint('ExpertChat: _markLeft error: $e');
    });
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
    final patientId = widget.entry.patientId;

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
        // Room doesn't exist yet — create it with both provider and patient
        await supabase
            .from('chat_rooms')
            .insert({
              'id': roomId,
              'participant_ids': [providerId, patientId],
              'room_type': 'consultation',
              'consultation_id': widget.entry.id,
              'package_id': widget.entry.packageId,
              'title': widget.entry.packageName,
              'last_message': null,
              'is_active': true,
              'updated_at': DateTime.now().toIso8601String(),
            })
            .timeout(const Duration(seconds: 5));
        debugPrint('ExpertChat: Created room $roomId');
      } else {
        // Room exists — add provider to participants if not already in
        final participants = List<String>.from(
          existing['participant_ids'] ?? [],
        );
        if (!participants.contains(patientId)) {
          participants.add(patientId);
        }
        if (!participants.contains(providerId)) {
          participants.add(providerId);
        }

        final updates = <String, dynamic>{
          'participant_ids': participants,
          'room_type': 'consultation',
          'consultation_id': widget.entry.id,
          'package_id': widget.entry.packageId,
          'title': widget.entry.packageName,
          'is_active': true,
          'updated_at': DateTime.now().toIso8601String(),
        };

        if ((existing['participant_ids'] as List?)?.length != participants.length ||
            (existing['room_type'] ?? existing['roomType']) != 'consultation') {
          await supabase
              .from('chat_rooms')
              .update(updates)
              .eq('id', roomId)
              .timeout(const Duration(seconds: 5));
          debugPrint('ExpertChat: Updated room $roomId with participants=$participants');
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

  /// โหลดสถานะการเสร็จงานของ experts ทั้งหมดใน consultation นี้
  Future<void> _loadCompletionStatus() async {
    if (widget.entry.id.isEmpty) return;
    setState(() => _isCheckingCompletion = true);
    try {
      final repo = ServiceLocator.instance.consultationRepository;
      final status = await repo.getExpertCompletionStatus(widget.entry.id);
      if (mounted) {
        setState(() {
          _completionStatus = status;
          _isCheckingCompletion = false;
        });
      }
    } catch (e) {
      debugPrint('ExpertChat: _loadCompletionStatus error: $e');
      if (mounted) setState(() => _isCheckingCompletion = false);
    }
  }

  /// Phase 6.8: โหลดสถานะการทำงานของ expert (completion rules)
  Future<void> _loadExpertCompletionStatus() async {
    if (widget.entry.id.isEmpty) return;
    setState(() => _isCheckingExpertCompletion = true);
    try {
      final authUser = AuthService.instance.currentUser;
      if (authUser == null) return;
      
      final repo = ServiceLocator.instance.consultationRepository;
      final result = await repo.getMyCompletionStatus(widget.entry.id, authUser.id);
      
      if (mounted) {
        setState(() {
          _expertCompletionStatus = ExpertCompletionStatus.fromJson(result);
          _isCheckingExpertCompletion = false;
        });
      }
    } catch (e) {
      debugPrint('ExpertChat: _loadExpertCompletionStatus error: $e');
      if (mounted) setState(() => _isCheckingExpertCompletion = false);
    }
  }

  // Provider เสร็จงาน → mark expert ตัวเองว่าเสร็จ รอทุกคนเสร็จถึงจะปิด consultation
  Future<void> _finishJob() async {
    debugPrint('ExpertChat: _finishJob START');

    final authUser = AuthService.instance.currentUser;
    if (authUser == null) {
      debugPrint('ExpertChat: authUser is null');
      return;
    }

    // Phase 6.8: ตรวจสอบเงื่อนไขการปิดงานก่อน
    await _loadExpertCompletionStatus();
    
    if (_expertCompletionStatus != null && !_expertCompletionStatus!.canFinish) {
      // ยังไม่ครบเงื่อนไข → แสดง warning dialog
      final override = await showDialog<bool>(
        context: context,
        builder: (ctx) => FinishJobWarningDialog(
          missingRequirements: _expertCompletionStatus!.missingRequirements,
          onOverride: () {
            // จบงานโดยไม่สนใจ (log ไว้สำหรับ audit)
            debugPrint('ExpertChat: overriding completion rules');
          },
        ),
      );
      
      if (override != true) {
        debugPrint('ExpertChat: user cancelled after seeing requirements');
        return;
      }
    }

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

    debugPrint('ExpertChat: dialog confirm=$confirm');
    if (confirm != true) {
      debugPrint('ExpertChat: user cancelled');
      return;
    }

    final userRepo = UserRepository(Supabase.instance.client);
    final consultRepo = ServiceLocator.instance.consultationRepository;
    debugPrint('ExpertChat: calling markExpertFinished consultationId=${widget.entry.id} providerId=${authUser.id}');

    try {
      // Mark expert ตัวเองว่าเสร็จ คืนค่าว่าทุกคนเสร็จหรือยัง
      final result = await consultRepo.markExpertFinished(
        widget.entry.id,
        authUser.id,
      );

      debugPrint('ExpertChat: markExpertFinished result=$result');

      final allFinished = result['all_finished'] as bool? ?? false;
      final finishedCount = result['finished_count'] as int? ?? 0;
      final totalCount = result['total_count'] as int? ?? 1;
      final remainingCount = result['remaining_count'] as int? ?? 0;

      debugPrint('ExpertChat: allFinished=$allFinished finishedCount=$finishedCount totalCount=$totalCount remaining=$remainingCount');

      // คืนสถานะ provider → online (ตัวเองเสร็จแล้ว ไม่ว่าคนอื่นจะเสร็จหรือยัง)
      await userRepo.setAvailabilityStatus(authUser.id, 'online');

      // Reload completion status
      await _loadCompletionStatus();

      if (mounted) {
        if (allFinished) {
          // ทุกคนเสร็จแล้ว → consultation จบจริง
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ เสร็จสิ้น! ทุกผู้เชี่ยวชาญจบงานแล้ว'),
              backgroundColor: AppColors.success,
              behavior: SnackBarBehavior.floating,
            ),
          );
          Navigator.pop(context);
        } else {
          // ยังมีคนไม่เสร็จ → แจ้งว่ารอคนอื่น
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'คุณจบงานแล้ว รอผู้เชี่ยวชาญอีก $remainingCount คน '
                '($finishedCount / $totalCount)',
              ),
              backgroundColor: AppColors.info,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e, st) {
      debugPrint('ExpertChat: _finishJob error: $e');
      debugPrint('ExpertChat: _finishJob stack: $st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('เกิดข้อผิดพลาด: $e'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 5),
          ),
        );
      }
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
          
          // Phase 6.8: Expert completion checklist
          if (_expertCompletionStatus != null)
            CompletionChecklist(
              status: _expertCompletionStatus!,
              onClose: () => setState(() => _expertCompletionStatus = null),
            ),

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
    final totalCount = _completionStatus['total_count'] as int? ?? 0;
    final finishedCount = _completionStatus['finished_count'] as int? ?? 0;
    final remainingCount = _completionStatus['remaining_count'] as int? ?? 0;
    final hasMultipleExperts = totalCount > 1;
    final allFinished = _completionStatus['all_finished'] as bool? ?? false;

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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Patient info row
          Row(
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
          // Expert completion status (only if multiple experts)
          if (hasMultipleExperts && !_isCheckingCompletion) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: allFinished
                    ? const Color(0xFFE8F5E9)
                    : const Color(0xFFFFF3E0),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: allFinished
                      ? const Color(0xFF4CAF50).withOpacity(0.3)
                      : const Color(0xFFFF9800).withOpacity(0.3),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    allFinished
                        ? Icons.check_circle_outline
                        : Icons.pending_actions_outlined,
                    color: allFinished
                        ? const Color(0xFF4CAF50)
                        : const Color(0xFFFF9800),
                    size: 16,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      allFinished
                          ? 'ทุกผู้เชี่ยวชาญจบงานแล้ว'
                          : 'รอผู้เชี่ยวชาญจบงาน: $remainingCount / $totalCount คน',
                      style: TextStyle(
                        fontSize: 11,
                        color: allFinished
                            ? const Color(0xFF2E7D32)
                            : const Color(0xFFE65100),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    '$finishedCount / $totalCount',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: allFinished
                          ? const Color(0xFF2E7D32)
                          : const Color(0xFFE65100),
                    ),
                  ),
                ],
              ),
            ),
          ],
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
                decoration: InputDecoration(
                  hintText: 'ให้คำแนะนำด้านสุขภาพ...',
                  hintStyle: TextStyle(color: Colors.grey.shade500, fontSize: 14),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 13),
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

