import 'package:flutter/material.dart';
import 'package:sheserved/services/auth_service.dart';
import 'package:sheserved/features/community/find_buddies/data/fitness_buddies_repository.dart';
import 'package:sheserved/features/sport_club/presentation/widgets/sport_club_utils.dart';

/// Member management actions: remove member, block user, blocklist sheet.
class MemberActionDialogs {
  /// Phase 8: Remove member from group (admin action).
  static Future<void> removeMember(
    BuildContext pageContext,
    BuildContext sheetCtx,
    FitnessBuddiesRepository repo,
    String groupId,
    String memberUserId,
    String memberName,
    StateSetter setSheetState,
  ) async {
    final confirmed = await showDialog<bool>(
      context: sheetCtx,
      builder: (dctx) => AlertDialog(
        title: const Text('ถอดออกจากก๊วนทั้งหมด'),
        content: Text(
          'ต้องการถอด "$memberName" ออกจากก๊วนใช่หรือไม่?\n'
          'ระบบจะยกเลิกการเข้าร่วมทุก upcoming session ของสมาชิกนี้',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dctx, false),
            child: const Text('ยกเลิก'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dctx, true),
            child: const Text(
              'ถอดทั้งก๊วน',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final actorUserId = AuthService.instance.currentUser?.id;
    if (actorUserId == null) return;
    try {
      await repo.leaveGroup(
        groupId: groupId,
        userId: memberUserId,
        actorUserId: actorUserId,
      );
      if (!pageContext.mounted) return;
      ScaffoldMessenger.of(pageContext).showSnackBar(
        SnackBar(content: Text('ถอด "$memberName" ออกจากก๊วนแล้ว')),
      );
      setSheetState(() {});
    } catch (e) {
      if (!pageContext.mounted) return;
      ScaffoldMessenger.of(
        pageContext,
      ).showSnackBar(SnackBar(content: Text('ถอดไม่สำเร็จ: $e')));
    }
  }

  /// Phase 4: Block user dialog.
  static Future<void> blockUser(
    BuildContext pageContext,
    BuildContext sheetCtx,
    FitnessBuddiesRepository repo,
    String groupId,
    String blockedUserId,
    String blockedUserName,
    StateSetter setSheetState, {
    Future<void> Function()? onFeedRefresh,
  }) async {
    final userId = AuthService.instance.currentUser?.id;
    if (userId == null) return;
    final reasonCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: sheetCtx,
      builder: (dctx) => AlertDialog(
        title: const Text('บล็อกผู้ใช้'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'คุณต้องการบล็อก "$blockedUserName" ใช่หรือไม่? ผู้ใช้ที่ถูกบล็อกจะไม่สามารถจองรอบนัดในก๊วนของคุณได้อีก',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reasonCtrl,
              onTapOutside: (_) =>
                  FocusManager.instance.primaryFocus?.unfocus(),
              decoration: const InputDecoration(
                hintText: 'เหตุผล (ไม่บังคับ)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dctx, false),
            child: const Text('ยกเลิก'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dctx, true),
            child: const Text('บล็อก', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await repo.blockUser(
        groupId: groupId,
        blockedUserId: blockedUserId,
        blockedBy: userId,
        reason: reasonCtrl.text.trim().isEmpty ? null : reasonCtrl.text.trim(),
      );
      if (!pageContext.mounted) return;
      ScaffoldMessenger.of(
        pageContext,
      ).showSnackBar(SnackBar(content: Text('บล็อก "$blockedUserName" แล้ว')));
      setSheetState(() {});
      await onFeedRefresh?.call();
    } catch (e) {
      if (!pageContext.mounted) return;
      ScaffoldMessenger.of(
        pageContext,
      ).showSnackBar(SnackBar(content: Text('บล็อกไม่สำเร็จ: $e')));
    }
  }

  /// Phase 4: Blocklist management sheet.
  static Future<void> showBlocklist(
    BuildContext pageContext,
    FitnessBuddiesRepository repo,
    String groupId, {
    required String? groupOwnerId,
  }) async {
    final user = AuthService.instance.currentUser;
    if (user == null || (user.id != groupOwnerId && !user.isAdmin)) return;

    await showModalBottomSheet(
      context: pageContext,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          Future<List<Map<String, dynamic>>> loadBlocked() =>
              repo.listBlockedUsers(groupId, requesterUserId: user.id);

          return SafeArea(
            top: false,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(ctx).size.height * 0.7,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 20,
                ),
                child: FutureBuilder<List<Map<String, dynamic>>>(
                  future: loadBlocked(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      return Center(
                        child: Text('โหลดไม่สำเร็จ: ${snapshot.error}'),
                      );
                    }
                    final blocked = snapshot.data ?? [];
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Center(
                          child: Container(
                            width: 40,
                            height: 4,
                            decoration: BoxDecoration(
                              color: Colors.grey[300],
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            IconButton(
                              tooltip: 'ย้อนกลับไปยังรายละเอียดก๊วน',
                              onPressed: () => Navigator.pop(ctx),
                              icon: const Icon(Icons.arrow_back),
                            ),
                            const Expanded(
                              child: Text(
                                'จัดการบล็อกลิสต์',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'ผู้ใช้ที่ถูกบล็อกจะไม่สามารถจองรอบนัดในก๊วนของคุณได้',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[600],
                          ),
                        ),
                        const SizedBox(height: 16),
                        if (blocked.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 24),
                            child: Center(
                              child: Text('ยังไม่มีผู้ใช้ที่ถูกบล็อก'),
                            ),
                          )
                        else
                          Expanded(
                            child: ListView.separated(
                              shrinkWrap: true,
                              itemCount: blocked.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: 4),
                              itemBuilder: (c, i) {
                                final b = blocked[i];
                                final blockedUser =
                                    (b['blocked_user'] as Map?) ?? {};
                                final name =
                                    '${blockedUser['first_name'] ?? ''} ${blockedUser['last_name'] ?? ''}'
                                        .trim();
                                final image =
                                    blockedUser['profile_image_url']
                                        ?.toString() ??
                                    '';
                                final reason = b['reason']?.toString();
                                final blockedAt = b['created_at']?.toString();
                                final blockedUserId =
                                    b['blocked_user_id']?.toString() ?? '';

                                return ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: CircleAvatar(
                                    backgroundImage: image.isNotEmpty
                                        ? NetworkImage(image)
                                        : null,
                                    child: image.isEmpty
                                        ? const Icon(Icons.person)
                                        : null,
                                  ),
                                  title: Text(
                                    name.isNotEmpty ? name : 'ไม่ระบุชื่อ',
                                  ),
                                  subtitle: Text(
                                    [
                                      if (reason != null && reason.isNotEmpty)
                                        'เหตุผล: $reason',
                                      if (blockedAt != null)
                                        'บล็อกเมื่อ: ${formatThaiBuddhistDateTime(DateTime.parse(blockedAt).toLocal())}',
                                    ].join('\n'),
                                  ),
                                  trailing: TextButton.icon(
                                    onPressed: () async {
                                      try {
                                        await repo.unblockUser(
                                          groupId: groupId,
                                          blockedUserId: blockedUserId,
                                          actorUserId: user.id,
                                        );
                                        if (!pageContext.mounted) return;
                                        ScaffoldMessenger.of(
                                          pageContext,
                                        ).showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              'ปลดบล็อก "$name" แล้ว',
                                            ),
                                          ),
                                        );
                                        setSheetState(() {});
                                      } catch (e) {
                                        if (!pageContext.mounted) return;
                                        ScaffoldMessenger.of(
                                          pageContext,
                                        ).showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              'ปลดบล็อกไม่สำเร็จ: $e',
                                            ),
                                          ),
                                        );
                                      }
                                    },
                                    icon: const Icon(
                                      Icons.lock_open,
                                      size: 16,
                                      color: Colors.green,
                                    ),
                                    label: const Text(
                                      'ปลดบล็อก',
                                      style: TextStyle(
                                        color: Colors.green,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
