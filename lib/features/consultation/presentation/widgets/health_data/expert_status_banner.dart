import 'package:flutter/material.dart';
import '../../../../../core/constants/app_colors.dart';
import '../../../../admin/models/profession.dart';
import '../../utils/expert_status_helpers.dart';

class ExpertStatusBanner extends StatelessWidget {
  final List<Map<String, dynamic>> expertStatuses;
  final List<Profession> professions;

  const ExpertStatusBanner({
    super.key,
    required this.expertStatuses,
    required this.professions,
  });

  @override
  Widget build(BuildContext context) {
    debugPrint('[ExpertStatusBanner] expertStatuses.length=${expertStatuses.length}');
    for (final e in expertStatuses) {
      debugPrint('[ExpertStatusBanner]   expert name=${e['name']} status=${e['status']} avatar=${e['providerAvatarUrl']} icon=${e['expertGroupIcon']}');
    }
    final hasWaitingRequired = expertStatuses.any(
      (e) => (e['isRequired'] == true) && (e['status'] == 'waiting'),
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
                size: 16,
                color: hasWaitingRequired ? Colors.orange : Colors.grey,
              ),
              const SizedBox(width: 8),
              Text(
                hasWaitingRequired
                    ? 'รอผู้เชี่ยวชาญที่จำเป็นเข้าร่วมเพื่อเริ่มนับเวลา'
                    : 'ทีมผู้เชี่ยวชาญในเซสชั่นนี้',
                style: TextStyle(
                  color: hasWaitingRequired
                      ? Colors.orange.shade800
                      : Colors.grey.shade600,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
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
                children: expertStatuses.map((expert) {
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

                  return Container(
                    margin: const EdgeInsets.only(right: 12),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: isJoined
                          ? (profColor?.withOpacity(0.08) ?? AppColors.primary.withOpacity(0.08))
                          : (isRequired ? Colors.grey.shade100 : Colors.grey.shade50),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isJoined
                            ? (profColor?.withOpacity(0.3) ?? AppColors.primary.withOpacity(0.2))
                            : (isRequired ? Colors.grey.shade300 : Colors.grey.shade200),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isJoined && avatarUrl != null && avatarUrl.isNotEmpty)
                          CircleAvatar(
                            radius: 12,
                            backgroundImage: NetworkImage(avatarUrl),
                            backgroundColor: Colors.grey.shade200,
                            onBackgroundImageError: (_, __) {},
                          )
                        else if (categoryIcon != null)
                          Icon(
                            categoryIcon,
                            size: 20,
                            color: isJoined
                                ? (profColor ?? AppColors.primary)
                                : (isRequired ? Colors.grey.shade600 : Colors.grey.shade400),
                          )
                        else
                          Icon(
                            isJoined
                                ? Icons.check_circle
                                : (isRequired ? Icons.priority_high : Icons.hourglass_empty),
                            size: 16,
                            color: isJoined
                                ? (profColor ?? AppColors.primary)
                                : (isRequired ? Colors.grey.shade600 : Colors.grey),
                          ),
                        const SizedBox(width: 6),
                        Builder(
                          builder: (context) {
                            String displayName = expert['name']?.toString() ?? '';
                            final profName = prof?.name;
                            
                            if (isJoined) {
                              final groupName = profName ?? expert['expertGroupName']?.toString();
                              if (groupName != null && groupName.isNotEmpty && groupName != displayName) {
                                displayName = '$displayName ($groupName)';
                              }
                            } else {
                              // If waiting, show the profession name (กลุ่มอาชีพ) instead of group name (ชื่อหน้ากลุ่ม)
                              if (profName != null && profName.isNotEmpty) {
                                displayName = profName;
                              }
                            }

                            if (isRequired) {
                              displayName += ' *';
                            }
                            return Text(
                              displayName,
                              style: TextStyle(
                                color: isJoined
                                    ? (profColor ?? AppColors.primary)
                                    : (isRequired ? Colors.grey.shade700 : Colors.grey.shade600),
                                fontSize: 12,
                                fontWeight: isJoined || isRequired ? FontWeight.bold : FontWeight.normal,
                              ),
                            );
                          }
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }
}
