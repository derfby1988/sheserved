import 'package:flutter/material.dart';
import 'package:sheserved/core/constants/app_colors.dart';
import 'package:sheserved/features/sport_club/presentation/widgets/cost/session_cost_items_view.dart';
import 'package:sheserved/features/sport_club/presentation/widgets/sport_club_utils.dart';
import 'package:sheserved/shared/widgets/glass/glass_dialog.dart';
import 'package:sheserved/shared/widgets/glass/glass_primitives.dart';

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
    return GlassDialog.show<void>(
      context: context,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      panelBorderRadius: 24,
      panelBlurSigma: 18,
      panelFillOpacity: 0.10,
      panelAccentColor: AppColors.primary,
      panelAccentStrength: 0.12,
      panelGlowOpacity: 0.14,
      panelRimWidth: 2.4,
      panelShadowOpacity: 0.30,
      contentPadding: EdgeInsets.zero,
      builder: (_) => _GroupSessionHistoryDialog(
        groupName: groupName,
        groupOwnerId: groupOwnerId,
        sessions: sessions,
        confirmedMembersBySession: confirmedMembersBySession,
      ),
    );
  }
}

class _GroupSessionHistoryDialog extends StatefulWidget {
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

  @override
  State<_GroupSessionHistoryDialog> createState() =>
      _GroupSessionHistoryDialogState();
}

class _GroupSessionHistoryDialogState
    extends State<_GroupSessionHistoryDialog> {
  /// จำนวนรอบที่แสดงต่อหนึ่งหน้า (โหลดเพิ่มเมื่อเลื่อนถึงท้าย)
  static const _pageSize = 5;

  late final ScrollController _scrollController;
  late final List<Map<String, dynamic>> _sessions;
  late int _visibleCount;

  @override
  void initState() {
    super.initState();
    // เรียงรอบนัดจากล่าสุดไปเก่าสุด (รอบล่าสุดอยู่แถวบนสุด)
    _sessions = List.of(widget.sessions)
      ..sort((a, b) {
        final aStart = DateTime.tryParse(a['starts_at']?.toString() ?? '');
        final bStart = DateTime.tryParse(b['starts_at']?.toString() ?? '');
        if (aStart == null && bStart == null) return 0;
        if (aStart == null) return 1; // รอบที่ไม่มีวันเวลาอยู่ท้ายสุด
        if (bStart == null) return -1;
        return bStart.compareTo(aStart);
      });
    _visibleCount = _sessions.length < _pageSize ? _sessions.length : _pageSize;
    _scrollController = ScrollController()..addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients || _visibleCount >= _sessions.length) {
      return;
    }
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  void _loadMore() {
    setState(() {
      _visibleCount = _visibleCount + _pageSize < _sessions.length
          ? _visibleCount + _pageSize
          : _sessions.length;
    });
  }

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
    final role = userId == widget.groupOwnerId
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

  Widget _sessionCard(Map<String, dynamic> session) {
    final sessionId = session['id']?.toString() ?? '';
    final participants =
        widget.confirmedMembersBySession[sessionId] ?? const [];
    return LitGlassSurface.frosted(
      borderRadius: 16,
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
            'รอบ · ${_sessionLabel(session)}',
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
    final hasMore = _visibleCount < _sessions.length;
    if (hasMore) {
      // ถ้าการ์ดที่แสดงอยู่ยังไม่ล้นพื้นที่ (เลื่อนไม่ได้) ให้โหลดหน้าถัดไป
      // ทันที เพื่อให้ dialog กระชับและผู้ใช้เลื่อนโหลดเพิ่มได้เมื่อเนื้อหาล้น
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted ||
            _visibleCount >= _sessions.length ||
            !_scrollController.hasClients) {
          return;
        }
        if (_scrollController.position.maxScrollExtent <= 0) {
          _loadMore();
        }
      });
    }
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                LitGlassSurface(
                  borderRadius: 12,
                  blurSigma: 8,
                  fillOpacity: 0.12,
                  rimWidth: 1.2,
                  shadowOpacity: 0.10,
                  child: const Padding(
                    padding: EdgeInsets.all(9),
                    child: Icon(
                      Icons.history_rounded,
                      color: AppColors.primary,
                    ),
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
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        '${widget.groupName} · ${_sessions.length} รอบที่สิ้นสุดแล้ว',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'ปิด',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: Icon(
                    Icons.close_rounded,
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Divider(height: 1, color: Colors.white.withValues(alpha: 0.15)),
            const SizedBox(height: 10),
            Flexible(
              child: Scrollbar(
                controller: _scrollController,
                thumbVisibility: _sessions.length > _pageSize,
                child: ListView.separated(
                  controller: _scrollController,
                  shrinkWrap: true,
                  itemCount: _visibleCount,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (_, index) => _sessionCard(_sessions[index]),
                ),
              ),
            ),
            if (hasMore) ...[
              const SizedBox(height: 6),
              Center(
                child: Text(
                  'เลื่อนลงเพื่อดูรอบก่อนหน้า',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.white.withValues(alpha: 0.5),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
