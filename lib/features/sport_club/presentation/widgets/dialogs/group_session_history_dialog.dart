import 'package:flutter/material.dart';
import 'package:sheserved/core/constants/app_colors.dart';
import 'package:sheserved/features/sport_club/presentation/widgets/cost/session_cost_items_view.dart';
import 'package:sheserved/features/sport_club/presentation/widgets/sport_club_utils.dart';

bool isSportClubSessionEnded(Map<String, dynamic> session, {DateTime? now}) {
  final endsAt = DateTime.tryParse(session['ends_at']?.toString() ?? '');
  return endsAt != null && endsAt.isBefore(now ?? DateTime.now());
}

class GroupSessionHistoryDialog {
  const GroupSessionHistoryDialog._();

  static Future<void> show(
    BuildContext context, {
    required String groupName,
    required String? groupOwnerId,
    required List<Map<String, dynamic>> sessions,
    required Map<String, List<Map<String, dynamic>>> confirmedMembersBySession,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => _GroupSessionHistoryDialog(
        groupName: groupName,
        groupOwnerId: groupOwnerId,
        sessions: sessions,
        confirmedMembersBySession: confirmedMembersBySession,
      ),
    );
  }
}

class _GroupSessionHistoryDialog extends StatelessWidget {
  const _GroupSessionHistoryDialog({
    required this.groupName,
    required this.groupOwnerId,
    required this.sessions,
    required this.confirmedMembersBySession,
  });

  final String groupName;
  final String? groupOwnerId;
  final List<Map<String, dynamic>> sessions;
  final Map<String, List<Map<String, dynamic>>> confirmedMembersBySession;

  String _sessionLabel(Map<String, dynamic> session) {
    final startsAt = DateTime.tryParse(session['starts_at']?.toString() ?? '');
    final endsAt = DateTime.tryParse(session['ends_at']?.toString() ?? '');
    if (startsAt == null || endsAt == null) return 'ไม่ระบุเวลารอบนัด';
    return formatThaiSessionRange(startsAt.toLocal(), endsAt.toLocal());
  }

  String _memberName(Map<String, dynamic> member) {
    final user = member['user'];
    final userData = user is Map ? user : const <String, dynamic>{};
    final firstName = userData['first_name']?.toString().trim() ?? '';
    final lastName = userData['last_name']?.toString().trim() ?? '';
    final name = '$firstName $lastName'.trim();
    return name.isNotEmpty ? name : 'ไม่ระบุชื่อ';
  }

  Widget _participantTile(Map<String, dynamic> member) {
    final user = member['user'];
    final userData = user is Map ? user : const <String, dynamic>{};
    final image = userData['profile_image_url']?.toString() ?? '';
    final userId = userData['id']?.toString() ?? member['user_id']?.toString();
    final role = userId == groupOwnerId
        ? 'เจ้าของก๊วน'
        : member['role']?.toString() == 'admin'
        ? 'ผู้ดูแล'
        : 'สมาชิก';
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
      leading: CircleAvatar(
        radius: 18,
        backgroundImage: image.isNotEmpty ? NetworkImage(image) : null,
        child: image.isEmpty ? const Icon(Icons.person) : null,
      ),
      title: Text(_memberName(member)),
      subtitle: Text('$role · ยืนยันแล้ว'),
    );
  }

  Widget _sessionCard(Map<String, dynamic> session, int index) {
    final sessionId = session['id']?.toString() ?? '';
    final participants = confirmedMembersBySession[sessionId] ?? const [];
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: Colors.white.withValues(alpha: 0.88),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Theme(
        data: ThemeData(
          dividerColor: Colors.transparent,
          colorScheme: ColorScheme.fromSeed(seedColor: AppColors.primary),
        ),
        child: ExpansionTile(
          initiallyExpanded: false,
          tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          leading: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: Colors.grey.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.history_rounded,
              color: Colors.grey,
              size: 20,
            ),
          ),
          title: Text(
            'รอบที่ ${index + 1} · ${_sessionLabel(session)}',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1E293B),
            ),
          ),
          subtitle: Text(
            '${participants.length} คน · สิ้นสุดแล้ว',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
          children: [
            SessionMetaView(session: session),
            SessionCostItemsView(session: session),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'ผู้เข้าร่วมรอบนี้ ${participants.length} คน',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade700,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            if (participants.isEmpty)
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 4, 16, 16),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('ไม่มีข้อมูลผู้เข้าร่วมรอบนี้'),
                ),
              )
            else
              ...participants.map(_participantTile),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.of(context).size.height * 0.82;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      color: Colors.grey.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.history_rounded,
                      color: AppColors.primaryDark,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'ประวัติรอบนัดของก๊วน',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '$groupName · ${sessions.length} รอบที่สิ้นสุดแล้ว',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'ปิด',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Divider(height: 1, color: Colors.grey.shade200),
              const SizedBox(height: 10),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: sessions.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (_, index) =>
                      _sessionCard(sessions[index], index),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('ปิด'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
