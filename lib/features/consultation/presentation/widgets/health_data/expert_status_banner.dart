import 'package:flutter/material.dart';
import '../../../../../core/constants/app_colors.dart';
import '../../../../admin/models/profession.dart';
import '../../utils/expert_status_helpers.dart';

class ExpertStatusBanner extends StatelessWidget {
  final List<Map<String, dynamic>> expertStatuses;
  final List<Profession> professions;
  final void Function(String providerId)? onAvatarTap;

  const ExpertStatusBanner({
    super.key,
    required this.expertStatuses,
    required this.professions,
    this.onAvatarTap,
  });

  @override
  Widget build(BuildContext context) {
    debugPrint('[ExpertStatusBanner] expertStatuses.length=${expertStatuses.length}');
    for (final e in expertStatuses) {
      debugPrint('[ExpertStatusBanner]   expert name=${e['name']} status=${e['status']} availability=${e['availabilityStatus']} leftAt=${e['leftAt']} finishedAt=${e['finishedAt']} hasPrescription=${e['hasPrescription']} avatar=${e['providerAvatarUrl']} icon=${e['expertGroupIcon']}');
    }
    final hasWaitingRequired = expertStatuses.any(
      (e) => (e['isRequired'] == true) && (e['status'] == 'waiting'),
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey.shade100)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                hasWaitingRequired ? Icons.info_outline : Icons.groups_outlined,
                size: 14,
                color: hasWaitingRequired ? Colors.orange : Colors.grey,
              ),
              const SizedBox(width: 6),
              Text(
                hasWaitingRequired
                    ? 'รอผู้เชี่ยวชาญที่จำเป็นเข้าร่วมเพื่อเริ่มนับเวลา'
                    : 'ทีมผู้เชี่ยวชาญในเซสชั่นนี้',
                style: TextStyle(
                  color: hasWaitingRequired
                      ? Colors.orange.shade800
                      : Colors.grey.shade600,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (expertStatuses.isEmpty)
            Text(
              'ยังไม่มีข้อมูลผู้เชี่ยวชาญสำหรับเซสชั่นนี้ (debug: empty)',
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey.shade400,
                fontStyle: FontStyle.italic,
              ),
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: expertStatuses.map((expert) {
                  return _buildExpertItem(expert);
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildExpertItem(Map<String, dynamic> expert) {
    final isJoined = expert['status'] == 'joined';
    final isRequired = expert['isRequired'] == true;
    final avatarUrl = expert['providerAvatarUrl']?.toString();
    final iconRaw = expert['expertGroupIcon'];
    final prof = findProfessionByNameOrRole(
      professions,
      expert['name']?.toString(),
      expert['role']?.toString(),
    );
    final categoryIcon = parseExpertGroupIcon(prof?.iconName ?? iconRaw) ??
        getDefaultIconForRole(expert['role']);
    final profColor = hexToColor(prof?.colorHex);

    String displayName = expert['name']?.toString() ?? '';
    final profName = prof?.name;
    final availability = expert['availabilityStatus'] as String? ?? 'offline';
    final leftAt = expert['leftAt'];
    final finishedAt = expert['finishedAt'];
    final hasPrescription = expert['hasPrescription'] == true;

    String? groupName;
    if (isJoined) {
      groupName = profName ?? expert['expertGroupName']?.toString();
    } else {
      groupName = expert['expertGroupName']?.toString() ?? profName;
      if (profName != null && profName.isNotEmpty) {
        displayName = profName;
      }
    }

    // Status determination — แสดงเฉพาะ 4 สถานะ: จบงาน(ฟ้า), ออกห้อง(เหลือง), ออฟไลน์(เทา), จ่ายยา(ชมพู)
    final bool showStatusOverlay;
    final Color overlayColor;
    final IconData? overlayIcon;
    final String? overlayText;
    final bool isPrescriptionStatus;
    if (finishedAt != null) {
      showStatusOverlay = true;
      overlayColor = const Color(0xFF29B6F6); // ฟ้าอ่อน
      overlayIcon = Icons.check_circle;
      overlayText = 'จบงาน';
      isPrescriptionStatus = false;
    } else if (leftAt != null) {
      showStatusOverlay = true;
      overlayColor = const Color(0xFFFFCA28); // เหลือง
      overlayIcon = Icons.exit_to_app;
      overlayText = 'ออกจากห้อง';
      isPrescriptionStatus = false;
    } else if (hasPrescription) {
      showStatusOverlay = true;
      overlayColor = const Color(0xFFF06292); // ชมพู
      overlayIcon = Icons.medication_liquid;
      overlayText = 'จ่ายยา';
      isPrescriptionStatus = true;
    } else if (availability == 'offline') {
      showStatusOverlay = true;
      overlayColor = Colors.grey;
      overlayIcon = Icons.circle;
      overlayText = 'ออฟไลน์';
      isPrescriptionStatus = false;
    } else {
      showStatusOverlay = false;
      overlayColor = Colors.transparent;
      overlayIcon = null;
      overlayText = null;
      isPrescriptionStatus = false;
    }

    final providerId = expert['providerId']?.toString();
    final isCurrentUserTap = isJoined && onAvatarTap != null && providerId != null && providerId.isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(right: 10),
      width: 60,
      child: Column(
        mainAxisSize: MainAxisSize.max,
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          // Name — hide if non-joined and would duplicate the profession below
          if (isJoined || groupName == null || displayName != groupName)
            Text(
              displayName,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: isJoined
                    ? (profColor ?? AppColors.primary)
                    : (isRequired ? Colors.grey.shade700 : Colors.grey.shade600),
                fontSize: 10,
                fontWeight: isJoined || isRequired ? FontWeight.bold : FontWeight.normal,
                height: 1.2,
              ),
            )
          else
            const SizedBox.shrink(),
          const SizedBox(height: 2),
          // Avatar with colored filter overlay + status badge
          Stack(
            alignment: Alignment.center,
            children: [
              // Main avatar
              GestureDetector(
                onTap: isCurrentUserTap ? () => onAvatarTap!(providerId!) : null,
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isJoined
                          ? (profColor?.withOpacity(0.4) ?? AppColors.primary.withOpacity(0.3))
                          : Colors.grey.shade300,
                      width: 1.5,
                    ),
                  ),
                  child: ClipOval(
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        // Base image
                        isJoined && avatarUrl != null && avatarUrl.isNotEmpty
                            ? Image.network(
                                avatarUrl,
                                width: 44,
                                height: 44,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => _fallbackAvatar(categoryIcon, profColor, isJoined, isRequired),
                              )
                            : _fallbackAvatar(categoryIcon, profColor, isJoined, isRequired),
                        // Colored transparent filter overlay (เฉพาะ 3 สถานะ)
                        if (showStatusOverlay)
                          Container(
                            color: overlayColor.withOpacity(0.35),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              // Required indicator (*) — top-right corner
              if (isRequired)
                const Positioned(
                  top: -1,
                  right: -1,
                  child: Text(
                    '*',
                    style: TextStyle(
                      color: Colors.red,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      height: 1.0,
                    ),
                  ),
                ),
              // Status badge overlay (bottom-right) — เฉพาะ 3 สถานะ
              if (isJoined && showStatusOverlay && overlayIcon != null)
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: overlayColor,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white, width: 1),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          overlayIcon,
                          size: 7,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 1),
                        Text(
                          overlayText!,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 7,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          if (groupName != null && groupName.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              groupName,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.visible,
              softWrap: false,
              style: TextStyle(
                color: Colors.grey.shade500,
                fontSize: 7,
                fontWeight: FontWeight.w500,
                height: 1.0,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _fallbackAvatar(IconData? icon, Color? profColor, bool isJoined, bool isRequired) {
    return Container(
      width: 44,
      height: 44,
      color: isJoined
          ? (profColor?.withOpacity(0.1) ?? AppColors.primary.withOpacity(0.1))
          : Colors.grey.shade100,
      child: Icon(
        icon ?? Icons.person_outline,
        size: 20,
        color: isJoined
            ? (profColor ?? AppColors.primary)
            : (isRequired ? Colors.grey.shade600 : Colors.grey.shade400),
      ),
    );
  }
}
