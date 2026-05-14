import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../services/service_locator.dart';
import '../../../../services/auth_service.dart';
import '../../data/models/consultation_request_model.dart';
import '../../../chat/data/models/chat_models.dart';
import 'package:intl/intl.dart';

class ConsultationChatHistoryPage extends StatefulWidget {
  final String consultationId;

  const ConsultationChatHistoryPage({super.key, required this.consultationId});

  @override
  State<ConsultationChatHistoryPage> createState() =>
      _ConsultationChatHistoryPageState();
}

class _ConsultationChatHistoryPageState
    extends State<ConsultationChatHistoryPage> {
  ConsultationRequestModel? _request;
  List<ChatMessage> _messages = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    try {
      final repo = ServiceLocator.instance.consultationRepository;

      // We need a method to get single request or we can find it
      // Let's use the repo to get requests and filter
      final userId = AuthService.instance.currentUser?.id;
      if (userId == null) return;

      // Note: In real app, we should add getRequestById in ConsultationRepository
      // For now, we fetch user or provider history and find it
      // We'll try user history first
      var list = await repo.getUserRequests(userId);
      var req = list.where((e) => e.id == widget.consultationId).firstOrNull;

      if (req == null) {
        // Try provider history
        list = await repo.getProviderHistory(userId);
        req = list.where((e) => e.id == widget.consultationId).firstOrNull;
      }

      if (req != null) {
        final roomId = req.roomId ?? 'consult_${req.id}';
        // Load messages
        final chatRepo = ServiceLocator.instance.chatRepository;
        final msgs = await chatRepo.getMessages(roomId);
        if (mounted) {
          setState(() {
            _request = req;
            _messages = msgs;
            _isLoading = false;
          });
        }
      } else {
        if (mounted) {
          setState(() => _isLoading = false);
        }
      }
    } catch (e) {
      debugPrint('Error loading chat history: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Widget _buildMedicalCard(ChatMessage message) {
    final isNote = message.type == 'note';
    final title = isNote
        ? 'บันทึกการตรวจ (Consultation Note)'
        : 'ใบสั่งยา (Prescription)';
    final color = isNote ? Colors.blue : Colors.green;
    final icon = isNote
        ? Icons.description_outlined
        : Icons.medication_outlined;

    return Container(
      margin: const EdgeInsets.only(top: 4, bottom: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'แตะเพื่อดูรายละเอียดข้อมูลการรักษา',
            style: TextStyle(fontSize: 12, color: Colors.black54),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(ChatMessage message) {
    final isMe = message.senderId == AuthService.instance.currentUser?.id;
    final isNoteOrPrescription =
        message.type == 'note' || message.type == 'prescription';

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        padding: const EdgeInsets.all(12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          color: isMe ? AppColors.primary : Colors.white,
          borderRadius: BorderRadius.circular(16).copyWith(
            bottomRight: isMe
                ? const Radius.circular(4)
                : const Radius.circular(16),
            bottomLeft: !isMe
                ? const Radius.circular(4)
                : const Radius.circular(16),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isNoteOrPrescription)
              _buildMedicalCard(message)
            else
              Text(
                message.content,
                style: TextStyle(
                  color: isMe ? Colors.white : Colors.black87,
                  fontSize: 15,
                ),
              ),
            const SizedBox(height: 4),
            Text(
              DateFormat('HH:mm').format(message.createdAt),
              style: TextStyle(
                color: isMe ? Colors.white.withOpacity(0.7) : Colors.black45,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      appBar: AppBar(
        title: const Text(
          'ประวัติการแชท (Read-only)',
          style: TextStyle(color: Colors.black87, fontSize: 16),
        ),
        backgroundColor: Colors.white,
        elevation: 1,
        iconTheme: const IconThemeData(color: Colors.black87),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _request == null
          ? const Center(child: Text('ไม่พบข้อมูลประวัติการแชท'))
          : Column(
              children: [
                // Banner Info
                Container(
                  width: double.infinity,
                  color: Colors.orange.shade50,
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        color: Colors.orange.shade800,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'นี่คือประวัติการสนทนาที่สิ้นสุดแล้ว ไม่สามารถส่งข้อความเพิ่มได้',
                          style: TextStyle(
                            color: Colors.orange.shade800,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      return _buildMessageBubble(_messages[index]);
                    },
                  ),
                ),
              ],
            ),
    );
  }
}
