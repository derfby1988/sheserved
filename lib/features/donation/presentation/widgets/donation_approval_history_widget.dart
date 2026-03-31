import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import '../../data/repositories/donation_repository.dart';
import '../../../../core/constants/app_text_styles.dart';

/// Widget แสดงประวัติการอนุมัติ (Approval History Timeline) ของคำร้องบริจาค
/// ใช้งานได้ทั้งในแถบ "คำร้องของฉัน" ใน Profile และแถบ "อนุมัติบริจาค" ของผู้ดูแล
class DonationApprovalHistoryWidget extends StatefulWidget {
  final String requestId;
  final DonationRepository repository;

  const DonationApprovalHistoryWidget({
    super.key,
    required this.requestId,
    required this.repository,
  });

  @override
  State<DonationApprovalHistoryWidget> createState() =>
      _DonationApprovalHistoryWidgetState();
}

class _DonationApprovalHistoryWidgetState
    extends State<DonationApprovalHistoryWidget> {
  List<Map<String, dynamic>> _history = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  @override
  void didUpdateWidget(covariant DonationApprovalHistoryWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.requestId != widget.requestId) {
      _loadHistory();
    }
  }

  Future<void> _loadHistory() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final data = await widget.repository.getRequestApprovals(widget.requestId);
      if (mounted) {
        setState(() {
          _history = data;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('DonationApprovalHistoryWidget: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Header ──
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.deepPurple.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.history_edu, size: 16, color: Colors.deepPurple),
            ),
            const SizedBox(width: 8),
            Text(
              'ประวัติการอนุมัติ',
              style: AppTextStyles.bodyMedium.copyWith(
                fontWeight: FontWeight.bold,
                color: Colors.deepPurple.shade700,
              ),
            ),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.refresh, size: 16, color: Colors.deepPurple),
              tooltip: 'โหลดใหม่',
              onPressed: _loadHistory,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // ── Content ──
        if (_isLoading)
          _buildShimmer()
        else if (_history.isEmpty)
          _buildEmpty()
        else
          _buildTimeline(),
      ],
    );
  }

  Widget _buildShimmer() {
    return Shimmer.fromColors(
      baseColor: Colors.deepPurple.shade100.withOpacity(0.5),
      highlightColor: Colors.white,
      child: Column(
        children: List.generate(
          2,
          (i) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                // Dot
                Container(
                  width: 36,
                  height: 36,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        height: 12,
                        width: 120,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        height: 10,
                        width: 200,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.hourglass_empty, color: Colors.grey.shade400, size: 20),
          const SizedBox(width: 8),
          Text(
            'ยังไม่มีรายการอนุมัติ — รอการพิจารณาจากกลุ่มอาชีพ',
            style: AppTextStyles.bodySmall.copyWith(color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeline() {
    return Column(
      children: List.generate(_history.length, (index) {
        final item = _history[index];
        final isLast = index == _history.length - 1;
        final profMap = item['profession'] as Map<String, dynamic>?;
        final approverMap = item['approver'] as Map<String, dynamic>?;

        final profName = profMap?['name']?.toString() ?? 'ไม่ทราบวิชาชีพ';
        final firstName = approverMap?['first_name']?.toString() ?? '';
        final lastName = approverMap?['last_name']?.toString() ?? '';
        final approverName = '${firstName} ${lastName}'.trim().isNotEmpty
            ? '${firstName} ${lastName}'.trim()
            : 'ไม่ทราบชื่อ';

        final rawDate = item['approved_at']?.toString();
        String dateStr = '';
        if (rawDate != null) {
          final dt = DateTime.tryParse(rawDate)?.toLocal();
          if (dt != null) {
            dateStr =
                '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year + 543}  ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')} น.';
          }
        }

        final isApproved = (item['status']?.toString() ?? 'approved') == 'approved';

        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Left: Icon + Line ──
              Column(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: isApproved
                          ? Colors.green.withOpacity(0.1)
                          : Colors.red.withOpacity(0.1),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isApproved ? Colors.green : Colors.red,
                        width: 1.5,
                      ),
                    ),
                    child: Icon(
                      isApproved ? Icons.check_rounded : Icons.close_rounded,
                      size: 18,
                      color: isApproved ? Colors.green : Colors.red,
                    ),
                  ),
                  if (!isLast)
                    Expanded(
                      child: Container(
                        width: 2,
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        color: Colors.deepPurple.shade100,
                      ),
                    ),
                ],
              ),

              const SizedBox(width: 12),

              // ── Right: Info ──
              Expanded(
                child: Container(
                  margin: EdgeInsets.only(bottom: isLast ? 0 : 16),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isApproved
                        ? Colors.green.withOpacity(0.04)
                        : Colors.red.withOpacity(0.04),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isApproved
                          ? Colors.green.withOpacity(0.2)
                          : Colors.red.withOpacity(0.2),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isApproved ? 'อนุมัติแล้ว' : 'ปฏิเสธ',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: isApproved ? Colors.green.shade700 : Colors.red,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$approverName · $profName',
                        style: AppTextStyles.bodyMedium.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (dateStr.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          dateStr,
                          style: AppTextStyles.bodySmall.copyWith(
                            color: Colors.grey.shade500,
                          ),
                        ),
                      ],
                      if (item['note'] != null &&
                          item['note'].toString().isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          'หมายเหตุ: ${item['note']}',
                          style: AppTextStyles.bodySmall.copyWith(
                            color: Colors.grey.shade600,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }
}
