// completion_checklist.dart
// Phase 6.8: Expert Completion Rules

import 'package:flutter/material.dart';
import '../../../consultation/data/models/expert_completion_status.dart';

class CompletionChecklist extends StatelessWidget {
  final ExpertCompletionStatus status;
  final VoidCallback? onClose;

  const CompletionChecklist({
    super.key,
    required this.status,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: status.canFinish
              ? const Color(0xFF4CAF50).withOpacity(0.3)
              : const Color(0xFFFF9800).withOpacity(0.3),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with progress
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: status.canFinish
                      ? const Color(0xFF4CAF50).withOpacity(0.1)
                      : const Color(0xFFFF9800).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  status.canFinish ? Icons.fact_check : Icons.pending_actions,
                  color: status.canFinish ? const Color(0xFF4CAF50) : const Color(0xFFFF9800),
                  size: 18,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      status.canFinish ? 'ครบเงื่อนไขการปิดงาน' : 'ยังไม่ครบเงื่อนไข',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: status.canFinish ? const Color(0xFF2E7D32) : const Color(0xFFE65100),
                      ),
                    ),
                    const SizedBox(height: 2),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: status.progress / 100,
                        backgroundColor: Colors.grey.shade200,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          status.canFinish ? const Color(0xFF4CAF50) : const Color(0xFFFF9800),
                        ),
                        minHeight: 4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${status.progress}%',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: status.canFinish ? const Color(0xFF2E7D32) : const Color(0xFFE65100),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Divider(height: 1),
          const SizedBox(height: 10),
          // Checklist items
          _buildItem(
            icon: Icons.chat_bubble_outline,
            label: 'สนทนาทั่วไป',
            value: '${status.generalMessageCount}',
            isDone: status.generalMessageCount > 0,
            color: const Color(0xFF607D8B),
          ),
          _buildItem(
            icon: Icons.medication_outlined,
            label: 'ออกใบสั่งยา',
            value: '${status.prescriptionCount}',
            isDone: status.prescriptionCount > 0,
            color: const Color(0xFF4CAF50),
          ),
          _buildItem(
            icon: Icons.verified_outlined,
            label: 'อนุมัติใบสั่งยา',
            value: '${status.approvedCount}',
            isDone: status.approvedCount > 0,
            color: const Color(0xFFFF9800),
          ),
          _buildItem(
            icon: Icons.help_outline,
            label: 'คำถามบังคับ',
            value: '${status.questionCount}',
            isDone: status.questionCount > 0,
            color: const Color(0xFF2196F3),
          ),
          _buildItem(
            icon: Icons.question_answer_outlined,
            label: 'คำตอบครบ',
            value: '${status.answeredCount}/${status.questionCount}',
            isDone: status.unansweredCount == 0 && status.questionCount > 0,
            color: const Color(0xFF9C27B0),
          ),
          _buildItem(
            icon: Icons.video_camera_front_outlined,
            label: 'Video call',
            value: status.hasVideoCall ? '✓' : '-',
            isDone: status.hasVideoCall,
            color: const Color(0xFFE91E63),
          ),
          _buildItem(
            icon: Icons.health_and_safety_outlined,
            label: 'Health assessment',
            value: status.hasAssessment ? '✓' : '-',
            isDone: status.hasAssessment,
            color: const Color(0xFF00BCD4),
          ),
        ],
      ),
    );
  }

  Widget _buildItem({
    required IconData icon,
    required String label,
    required String value,
    required bool isDone,
    required Color color,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(
            isDone ? Icons.check_circle : Icons.radio_button_unchecked,
            size: 14,
            color: isDone ? color : Colors.grey.shade400,
          ),
          const SizedBox(width: 6),
          Icon(icon, size: 12, color: isDone ? color : Colors.grey.shade400),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: isDone ? const Color(0xFF1A1A2E) : Colors.grey.shade500,
                fontWeight: isDone ? FontWeight.w500 : FontWeight.normal,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: isDone ? color : Colors.grey.shade400,
            ),
          ),
        ],
      ),
    );
  }
}
