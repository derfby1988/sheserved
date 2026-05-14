import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../services/service_locator.dart';
import '../../../../services/auth_service.dart';
import '../../data/models/consultation_request_model.dart';
import 'package:intl/intl.dart';

class MyConsultationsPage extends StatefulWidget {
  final bool isEmbedded;

  const MyConsultationsPage({super.key, this.isEmbedded = false});

  @override
  State<MyConsultationsPage> createState() => _MyConsultationsPageState();
}

class _MyConsultationsPageState extends State<MyConsultationsPage> {
  bool _isLoading = true;
  List<ConsultationRequestModel> _requests = [];

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    try {
      final userId = AuthService.instance.currentUser?.id;
      if (userId == null) return;

      final repo = ServiceLocator.instance.consultationRepository;
      final history = await repo.getUserRequests(userId);

      if (mounted) {
        setState(() {
          _requests = history;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading history: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _formatStatus(String status) {
    switch (status) {
      case 'pending':
        return 'รอแพทย์รับเคส';
      case 'active':
        return 'กำลังให้คำปรึกษา';
      case 'completed':
        return 'เสร็จสิ้น';
      case 'cancelled':
        return 'ยกเลิก';
      default:
        return status;
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'pending':
        return Colors.orange;
      case 'active':
        return Colors.blue;
      case 'completed':
        return Colors.green;
      case 'cancelled':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final body = _isLoading
        ? const Center(child: CircularProgressIndicator())
        : _requests.isEmpty
            ? _buildEmptyState()
            : RefreshIndicator(
                onRefresh: _loadHistory,
                child: Scrollbar(
                  thumbVisibility: true,
                  thickness: 6.0,
                  radius: const Radius.circular(8.0),
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _requests.length,
                    itemBuilder: (context, index) {
                      final req = _requests[index];
                      return _buildHistoryCard(req);
                    },
                  ),
                ),
              );

    if (widget.isEmbedded) {
      return body;
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text(
          'ประวัติการปรึกษา',
          style: TextStyle(color: Colors.black87),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black87),
      ),
      body: body,
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.history, size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(
            'ยังไม่มีประวัติการปรึกษา',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 16),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryCard(ConsultationRequestModel req) {
    final statusColor = _getStatusColor(req.status);
    final dateStr = req.createdAt != null
        ? DateFormat('dd/MM/yyyy HH:mm').format(req.createdAt!)
        : '-';

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 2,
      shadowColor: Colors.black12,
      child: InkWell(
        onTap: () {
          final roomId = req.roomId ?? 'consult_${req.id}';
          // ถ้าสถานะเป็น completed ให้เปิดดูแชทย้อนหลัง (Read-only)
          // ถ้าเป็น active ให้เปิดแชทปกติ
          if (req.status == 'completed' || req.status == 'cancelled') {
             // ไปหน้า read-only chat history
             Navigator.pushNamed(context, '/consultation-history-chat', arguments: req.id);
          } else if (req.status == 'active' || req.status == 'in_progress') {
             Navigator.pushNamed(context, '/chat-room', arguments: roomId);
          }
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      req.packageName ?? 'ปรึกษาแพทย์',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _formatStatus(req.status),
                      style: TextStyle(
                        color: statusColor,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(Icons.access_time, size: 16, color: Colors.grey),
                  const SizedBox(width: 8),
                  Text(
                    'วันที่: $dateStr',
                    style: const TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                ],
              ),
              if (req.price != null && req.price! > 0) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.payment, size: 16, color: Colors.grey),
                    const SizedBox(width: 8),
                    Text(
                      'ค่าบริการ: ฿${req.price}',
                      style: const TextStyle(color: Colors.grey, fontSize: 13),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
