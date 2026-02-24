import 'dart:async';
import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../config/app_config.dart'; // Import config
import '../../data/models/consultation_request_model.dart';

class VegaAiChatPage extends StatefulWidget {
  final ConsultationRequestModel request;

  const VegaAiChatPage({super.key, required this.request});

  @override
  State<VegaAiChatPage> createState() => _VegaAiChatPageState();
}

class _VegaAiChatPageState extends State<VegaAiChatPage> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<Map<String, dynamic>> _messages = [];
  bool _isTyping = false;
  int _queryCount = 0; // Track queries for session limit

  @override
  void initState() {
    super.initState();
    if (AppConfig.vegaAiKillSwitch) {
      _addBotMessage("⚠️ **[SYSTEM] ระบบ AI ปิดใช้งานชั่วคราว** เพื่อควบคุมค่าใช้จ่ายตามนโยบาย Free Tier");
      return;
    }
    // Initial greeting from Vega
    _addBotMessage("สวัสดีค่ะ ฉันคือ **Vega AI** ผู้ช่วยวิเคราะห์อาการเบื้องต้นของคุณในวันนี้");
    if (AppConfig.vegaAiMode == VegaAiMode.mock) {
      _addBotMessage("💡 *[Dev Mode: กำลังใช้ข้อมูลจำลอง - ไม่มีการเรียกจริงไปยัง API]*");
    }
    _addBotMessage("จากการระบุพื้นที่ที่คุณกังวล ฉันได้เตรียมข้อมูลคัดกรองเบื้องต้นไว้แล้ว คุณต้องการเริ่มปรึกษาเลยไหมคะ?");
  }

  void _addBotMessage(String text) {
    setState(() {
      _messages.add({
        'isMe': false,
        'text': text,
        'time': DateTime.now(),
      });
    });
    _scrollToBottom();
  }

  void _addUserMessage(String text) {
    setState(() {
      _messages.add({
        'isMe': true,
        'text': text,
        'time': DateTime.now(),
      });
    });
    _scrollToBottom();
    _handleAIResponse(text);
  }

  Future<void> _handleAIResponse(String userText) async {
    if (AppConfig.vegaAiKillSwitch) {
      _addBotMessage("ขออภัยค่ะ ระบบ AI ปิดให้บริการชั่วคราวตามนโยบายควบคุมค่าใช้จ่าย คุณสามารถกดปุ่มด้านล่างเพื่อปรึกษาแพทย์ได้ทันทีค่ะ");
      return;
    }

    if (_queryCount >= AppConfig.maxDailyVegaQueries) {
      _addBotMessage("⚠️ คุณใช้งาน AI ครบตามโควตา Free Tier ของวันนี้แล้วค่ะ เพื่อป้องกันค่าใช้จ่ายส่วนเกิน กรุณากดปุ่มด้านล่างเพื่อพูดคุยกับคุณหมอต่อได้เลยนะคะ");
      return;
    }

    setState(() {
      _isTyping = true;
      _queryCount++;
    });
    
    // Simulate API delay / Network Call
    await Future.delayed(const Duration(seconds: 2));
    
    if (mounted) {
      setState(() => _isTyping = false);
      _addBotMessage("ขอบคุณสำหรับข้อมูลค่ะ จากข้อมูลที่คุณระบุว่ามีอาการบริเวณ '${widget.request.symptoms.isNotEmpty ? widget.request.symptoms.first.displayLabel : 'ร่างกาย'}' ฉันขอแนะนำให้คุณประเมินระดับความเจ็บปวดเพิ่มเติมในขั้นตอนถัดไป เพื่อให้คุณหมอสามารถวินิจฉัยได้แม่นยำที่สุดค่ะ");
    }
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Row(
          children: [
            CircleAvatar(
              backgroundColor: AppColors.primary.withOpacity(0.1),
              child: const Icon(Icons.auto_awesome, color: AppColors.primary, size: 20),
            ),
            const SizedBox(width: 12),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Vega AI Consultation',
                  style: TextStyle(color: Colors.black, fontSize: 16, fontWeight: FontWeight.bold),
                ),
                Text(
                  'AI Assistance Powered by Eidy',
                  style: TextStyle(color: Colors.grey, fontSize: 10),
                ),
              ],
            ),
          ],
        ),
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.grey),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(20),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final msg = _messages[index];
                final isMe = msg['isMe'] as bool;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Row(
                    mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (!isMe)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: CircleAvatar(
                            radius: 12,
                            backgroundColor: AppColors.primary.withOpacity(0.1),
                            child: const Icon(Icons.auto_awesome, size: 12, color: AppColors.primary),
                          ),
                        ),
                      Flexible(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: isMe ? AppColors.primary : Colors.grey.shade100,
                            borderRadius: BorderRadius.only(
                              topLeft: const Radius.circular(20),
                              topRight: const Radius.circular(20),
                              bottomLeft: Radius.circular(isMe ? 20 : 4),
                              bottomRight: Radius.circular(isMe ? 4 : 20),
                            ),
                          ),
                          child: Text(
                            msg['text'],
                            style: TextStyle(
                              color: isMe ? Colors.white : Colors.black87,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          if (_isTyping)
            const Padding(
              padding: EdgeInsets.only(left: 44, bottom: 16),
              child: Row(
                children: [
                  Text("Vega กำลังพิมพ์...", style: TextStyle(color: Colors.grey, fontSize: 12, fontStyle: FontStyle.italic)),
                ],
              ),
            ),
          
          // Action Buttons
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, -5)),
              ],
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(25),
                        ),
                        child: TextField(
                          controller: _controller,
                          decoration: const InputDecoration(
                            hintText: 'พิมพ์ข้อความ...',
                            border: InputBorder.none,
                          ),
                          onSubmitted: (val) {
                            if (val.trim().isNotEmpty) {
                              _addUserMessage(val);
                              _controller.clear();
                            }
                          },
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    GestureDetector(
                      onTap: () {
                        if (_controller.text.trim().isNotEmpty) {
                          _addUserMessage(_controller.text);
                          _controller.clear();
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: const BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.send, color: Colors.white, size: 20),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: ElevatedButton(
                    onPressed: () {
                      // Navigate to Doctor Chat (Chart Board)
                      Navigator.pushReplacementNamed(context, '/chart-board', arguments: widget.request);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 50),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
                    ),
                    child: const Text('เสร็จสิ้นและปรึกษาแพทย์ต่อ', style: TextStyle(fontWeight: FontWeight.bold)),
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
