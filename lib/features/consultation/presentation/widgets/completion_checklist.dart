// completion_checklist.dart
// Phase 6.8: Expert Completion Rules

import 'package:flutter/material.dart';
import '../../../consultation/data/models/expert_completion_status.dart';
import '../../../consultation/data/models/profession_package_rule.dart';

class CompletionChecklist extends StatelessWidget {
  final ExpertCompletionStatus status;
  final ProfessionPackageRule? rule;
  final VoidCallback? onClose;

  const CompletionChecklist({
    super.key,
    required this.status,
    this.rule,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    // Determine which conditions are required based on the profession package rule
    final r = rule;
    final bool reqGeneral = r == null || r.minGeneralMessages > 0;
    final bool reqPrescribe = r == null || r.mustPrescribe;
    final bool reqApproval = r == null || r.requiresPrescriptionApproval;
    final bool reqQuestions = r == null || r.canSetRequiredQuestions || r.minRequiredQuestions > 0;
    final bool reqAnswers = r == null || r.mustAnswerAllQuestions;
    final bool reqVideo = r == null || r.requiresVideoCall;
    final bool reqHealth = r == null || r.requiresHealthAssessment;

    // Stepper items — only required conditions
    final steps = <_Step>[
      if (reqGeneral) _Step(icon: Icons.chat_bubble_outline, label: 'สนทนา', isDone: status.generalMessageCount > 0, color: const Color(0xFF607D8B)),
      if (reqPrescribe) _Step(icon: Icons.medication_outlined, label: 'สั่งยา', isDone: status.prescriptionCount > 0, color: const Color(0xFF4CAF50)),
      if (reqApproval) _Step(icon: Icons.verified_outlined, label: 'อนุมัติ', isDone: status.approvedCount > 0, color: const Color(0xFFFF9800)),
      if (reqQuestions) _Step(icon: Icons.help_outline, label: 'คำถาม', isDone: status.questionCount > 0, color: const Color(0xFF2196F3)),
      if (reqAnswers) _Step(icon: Icons.question_answer_outlined, label: 'ตอบ', isDone: status.unansweredCount == 0 && status.questionCount > 0, color: const Color(0xFF9C27B0)),
      if (reqVideo) _Step(icon: Icons.video_camera_front_outlined, label: 'Video', isDone: status.hasVideoCall, color: const Color(0xFFE91E63)),
      if (reqHealth) _Step(icon: Icons.health_and_safety_outlined, label: 'Health', isDone: status.hasAssessment, color: const Color(0xFF00BCD4)),
    ];

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
          // Header with stepper
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
                    const SizedBox(height: 6),
                    if (steps.isNotEmpty) _buildStepper(steps),
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
          // Checklist items — only required conditions
          if (reqGeneral) _buildItem(
            icon: Icons.chat_bubble_outline,
            label: 'สนทนาทั่วไป',
            value: r != null && r.minGeneralMessages > 0
                ? 'บังคับ ${r.minGeneralMessages} ผ่านแล้ว ${status.generalMessageCount}'
                : 'ผ่านแล้ว ${status.generalMessageCount}',
            isDone: status.generalMessageCount > 0 && (r == null || status.generalMessageCount >= r.minGeneralMessages),
            color: const Color(0xFF607D8B),
          ),
          if (reqPrescribe) _buildItem(
            icon: Icons.medication_outlined,
            label: 'ออกใบสั่งยา',
            value: r != null && r.minPrescriptionItems > 0
                ? 'บังคับ ${r.minPrescriptionItems} ผ่านแล้ว ${status.prescriptionCount}'
                : 'ผ่านแล้ว ${status.prescriptionCount}',
            isDone: status.prescriptionCount > 0 && (r == null || status.prescriptionCount >= r.minPrescriptionItems),
            color: const Color(0xFF4CAF50),
          ),
          if (reqApproval) _buildItem(
            icon: Icons.verified_outlined,
            label: 'อนุมัติใบสั่งยา',
            value: status.approvedCount > 0 ? 'ผ่านแล้ว ${status.approvedCount}' : 'ยังไม่ผ่าน',
            isDone: status.approvedCount > 0,
            color: const Color(0xFFFF9800),
          ),
          if (reqQuestions) _buildItem(
            icon: Icons.help_outline,
            label: 'คำถามบังคับ',
            value: r != null && r.minRequiredQuestions > 0
                ? 'บังคับ ${r.minRequiredQuestions} ผ่านแล้ว ${status.questionCount}'
                : 'ผ่านแล้ว ${status.questionCount}',
            isDone: status.questionCount > 0 && (r == null || status.questionCount >= r.minRequiredQuestions),
            color: const Color(0xFF2196F3),
          ),
          if (reqAnswers) _buildItem(
            icon: Icons.question_answer_outlined,
            label: 'คำตอบครบ',
            value: r != null && r.minRequiredQuestions > 0
                ? 'บังคับ ${r.minRequiredQuestions} ผ่านแล้ว ${status.answeredCount}/${status.questionCount}'
                : 'ผ่านแล้ว ${status.answeredCount}/${status.questionCount}',
            isDone: status.unansweredCount == 0 && status.questionCount > 0,
            color: const Color(0xFF9C27B0),
          ),
          if (reqVideo) _buildItem(
            icon: Icons.video_camera_front_outlined,
            label: 'Video call',
            value: status.hasVideoCall ? '✓' : '-',
            isDone: status.hasVideoCall,
            color: const Color(0xFFE91E63),
          ),
          if (reqHealth) _buildItem(
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

  Widget _buildStepper(List<_Step> steps) {
    return Row(
      children: steps.asMap().entries.map((entry) {
        final index = entry.key;
        final step = entry.value;
        final isLast = index == steps.length - 1;
        return Expanded(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  children: [
                    Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: step.isDone ? step.color : Colors.grey.shade200,
                        border: Border.all(
                          color: step.isDone ? step.color : Colors.grey.shade400,
                          width: 1.5,
                        ),
                      ),
                      child: Center(
                        child: step.isDone
                            ? const Icon(Icons.check, size: 12, color: Colors.white)
                            : Icon(step.icon, size: 11, color: Colors.grey.shade500),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      step.label,
                      style: TextStyle(
                        fontSize: 8,
                        color: step.isDone ? step.color : Colors.grey.shade500,
                        fontWeight: step.isDone ? FontWeight.w600 : FontWeight.normal,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    height: 2,
                    margin: const EdgeInsets.only(bottom: 14),
                    color: steps[index + 1].isDone
                        ? const Color(0xFF4CAF50).withOpacity(0.4)
                        : Colors.grey.shade200,
                  ),
                ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class _Step {
  final IconData icon;
  final String label;
  final bool isDone;
  final Color color;

  const _Step({
    required this.icon,
    required this.label,
    required this.isDone,
    required this.color,
  });
}
