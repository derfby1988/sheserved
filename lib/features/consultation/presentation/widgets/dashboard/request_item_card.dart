import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../../core/constants/app_colors.dart';
import '../../data/models/consultation_entry.dart';
import '../../../../../shared/widgets/widgets.dart';

class RequestItemCardWidget extends StatelessWidget {
  final ConsultationEntry e;
  final int index;
  final bool isProvider;
  final String availabilityStatus;
  final String? currentUserId;
  final String? highlightedId;
  final GlobalKey cardKey;
  final Future<void> Function(ConsultationEntry) onAcceptJob;
  final void Function(ConsultationEntry) onOpenChat;

  const RequestItemCardWidget({
    super.key,
    required this.e,
    required this.index,
    required this.isProvider,
    required this.availabilityStatus,
    this.currentUserId,
    this.highlightedId,
    required this.cardKey,
    required this.onAcceptJob,
    required this.onOpenChat,
  });

  @override
  Widget build(BuildContext context) {
    final myUserId = currentUserId;
    final isMyJob = e.providerId == myUserId;
    final isBusy = e.isAssigned && !isMyJob; // งานถูก provider อื่นรับแล้ว
    final isHighlighted = e.id == highlightedId;

    return TweenAnimationBuilder<double>(
      key: cardKey,
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 300 + index * 60),
      curve: Curves.easeOut,
      builder: (ctx, v, child) => Opacity(
        opacity: v,
        child: Transform.translate(
          offset: Offset(0, 20 * (1 - v)),
          child: child,
        ),
      ),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 350),
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: isHighlighted
              ? Border.all(color: AppColors.primary, width: 2.5)
              : isMyJob
                  ? Border.all(
                      color: AppColors.primary.withOpacity(0.5),
                      width: 1.5,
                    )
                  : null,
          boxShadow: [
            if (isHighlighted)
              BoxShadow(
                color: AppColors.primary.withOpacity(0.35),
                blurRadius: 20,
                spreadRadius: 3,
                offset: const Offset(0, 4),
              )
            else
              BoxShadow(
                color: isMyJob
                    ? AppColors.primary.withOpacity(0.12)
                    : Colors.black.withOpacity(0.07),
                blurRadius: 12,
                spreadRadius: isMyJob ? 2 : 0,
                offset: const Offset(0, 4),
              ),
          ],
        ),

        child: Column(
          children: [
            // Header row
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: Row(
                children: [
                  _avatar(e),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          e.patientName,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          DateFormat('d MMM yyyy  HH:mm').format(e.requestedAt),
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      _statusBadge(e.status),
                      if (isMyJob) ...[
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            'งานของคุณ',
                            style: TextStyle(
                              fontSize: 9,
                              color: AppColors.primary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),

            // Info section
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 14),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FBF8),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  _infoRow(
                    Icons.spa_outlined,
                    'แพ็คเกจ',
                    e.packageName,
                    AppColors.primary,
                  ),
                  const SizedBox(height: 8),
                  _infoRow(
                    Icons.location_on_outlined,
                    'บริเวณที่พบอาการ',
                    e.bodyArea,
                    AppColors.warning,
                  ),
                  const SizedBox(height: 8),
                  _infoRow(
                    Icons.payments_outlined,
                    'ราคา',
                    '${e.price.toInt()} บาท',
                    AppColors.info,
                  ),
                ],
              ),
            ),

            // Action buttons
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
              child: _buildActionRow(e, isMyJob: isMyJob, isBusy: isBusy, context: context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _avatar(ConsultationEntry e) {
    if (e.patientAvatar != null && e.patientAvatar!.isNotEmpty) {
      return CircleAvatar(
        radius: 24,
        backgroundImage: NetworkImage(e.patientAvatar!),
        backgroundColor: Colors.grey.shade200,
      );
    }
    return CircleAvatar(
      radius: 24,
      backgroundColor: AppColors.primary.withOpacity(0.15),
      child: Text(
        e.patientName.isNotEmpty ? e.patientName[0].toUpperCase() : '?',
        style: const TextStyle(
          color: AppColors.primary,
          fontWeight: FontWeight.bold,
          fontSize: 18,
        ),
      ),
    );
  }

  Widget _statusBadge(String status) {
    Color color;
    String label;
    IconData icon;

    switch (status) {
      case 'pending':
        color = AppColors.warning;
        label = 'รอดำเนินการ';
        icon = Icons.pending_outlined;
        break;
      case 'in_progress':
        color = AppColors.info;
        label = 'กำลังดำเนินการ';
        icon = Icons.forum_outlined;
        break;
      case 'completed':
        color = AppColors.success;
        label = 'เสร็จสิ้น';
        icon = Icons.check_circle_outline;
        break;
      default:
        color = Colors.grey;
        label = status;
        icon = Icons.help_outline;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value, Color color) {
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
        const Spacer(),
        Text(
          value,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
        ),
      ],
    );
  }

  Widget _buildActionRow(
    ConsultationEntry e, {
    required bool isMyJob,
    required bool isBusy,
    required BuildContext context,
  }) {
    // 1. ถ้าไม่ใช่ Provider -> รอ Provider รับงาน หรือเข้าดูสถานะ
    if (!isProvider) {
      return Row(
        children: [
          Expanded(
            child: TlzButton(type: TlzButtonType.primary, isFullWidth: true, 
              text: 'ดูรายละเอียด/แชท',
              onPressed: () => onOpenChat(e),
            ),
          ),
        ],
      );
    }

    // 2. ถ้าเป็น Provider
    if (e.status == 'pending' && !isBusy) {
      return Row(
        children: [
          Expanded(
            child: TlzButton(type: TlzButtonType.outline, isFullWidth: true, 
              text: 'ดูรายละเอียด',
              onPressed: () {},
              textColor: AppColors.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: availabilityStatus == 'available'
                ? TlzButton(type: TlzButtonType.primary, isFullWidth: true, 
                    text: 'รับให้คำปรึกษา',
                    onPressed: () => onAcceptJob(e),
                  )
                : TlzButton(type: TlzButtonType.outline, isFullWidth: true, 
                    text: 'ออฟไลน์อยู่',
                    onPressed: () {},
                    textColor: Colors.grey,
                  ),
          ),
        ],
      );
    }

    if (isMyJob && e.status == 'in_progress') {
      return Row(
        children: [
          Expanded(
            child: TlzButton(type: TlzButtonType.primary, isFullWidth: true, 
              text: 'เข้าห้องแชทเพื่อให้คำปรึกษา',
              icon: Icons.chat_rounded,
              onPressed: () => onOpenChat(e),
            ),
          ),
        ],
      );
    }

    return Row(
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Center(
              child: Text(
                e.status == 'completed'
                    ? 'รายการนี้เสร็จสิ้นแล้ว'
                    : 'ถูกรับงานไปแล้ว',
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
