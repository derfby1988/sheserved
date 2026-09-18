import 'package:flutter/material.dart';
import 'package:sheserved/services/auth_service.dart';
import 'package:sheserved/features/community/find_buddies/data/fitness_buddies_repository.dart';
import 'package:sheserved/features/sport_club/presentation/widgets/dialogs/sport_club_error_mapper.dart';

/// Approve / reject / remove-participant actions for session bookings.
class BookingActionDialogs {
  /// Phase 8: Approve single booking (direct, no dialog needed).
  static Future<void> approveSingle(
    BuildContext pageContext,
    FitnessBuddiesRepository repo,
    String bookingId,
    String userName,
    StateSetter setSheetState,
  ) async {
    final user = AuthService.instance.currentUser;
    if (user == null) return;
    try {
      await repo.approveBooking(bookingId: bookingId, actorUserId: user.id);
      if (!pageContext.mounted) return;
      ScaffoldMessenger.of(
        pageContext,
      ).showSnackBar(SnackBar(content: Text('อนุมัติ "$userName" แล้ว')));
      setSheetState(() {});
    } catch (e) {
      if (!pageContext.mounted) return;
      ScaffoldMessenger.of(
        pageContext,
      ).showSnackBar(SnackBar(content: Text(mapApprovalError(e))));
    }
  }

  /// Phase 8: Reject all pending bookings for a user.
  static Future<void> showRejectAll(
    BuildContext pageContext,
    BuildContext sheetCtx,
    FitnessBuddiesRepository repo,
    List<Map<String, dynamic>> bookings,
    String userName,
    StateSetter setSheetState,
  ) async {
    final currentUser = AuthService.instance.currentUser;
    if (currentUser == null) return;
    final reasonCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: sheetCtx,
      builder: (dctx) => AlertDialog(
        title: const Text('ปฏิเสธคำขอ'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'ต้องการปฏิเสธคำขอทั้งหมดของ "$userName" (${bookings.length} รอบ) ใช่หรือไม่?',
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
            child: const Text('ปฏิเสธ', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final reason = reasonCtrl.text.trim().isEmpty
          ? null
          : reasonCtrl.text.trim();
      for (final b in bookings) {
        await repo.rejectBooking(
          bookingId: b['id'].toString(),
          actorUserId: currentUser.id,
          reason: reason,
        );
      }
      if (!pageContext.mounted) return;
      ScaffoldMessenger.of(
        pageContext,
      ).showSnackBar(SnackBar(content: Text('ปฏิเสธคำขอของ "$userName" แล้ว')));
      setSheetState(() {});
    } catch (e) {
      if (!pageContext.mounted) return;
      ScaffoldMessenger.of(
        pageContext,
      ).showSnackBar(SnackBar(content: Text('ปฏิเสธไม่สำเร็จ: $e')));
    }
  }

  static Future<void> removeParticipantFromSession(
    BuildContext pageContext,
    BuildContext sheetCtx,
    FitnessBuddiesRepository repo,
    String bookingId,
    String memberName,
    String sessionLabel,
    StateSetter setSheetState,
  ) async {
    final confirmed = await showDialog<bool>(
      context: sheetCtx,
      builder: (dctx) => AlertDialog(
        title: const Text('ถอดออกจากรอบนี้'),
        content: Text(
          'ต้องการถอด "$memberName" จากรอบ $sessionLabel ใช่หรือไม่?\n'
          'สมาชิกยังอยู่ในก๊วน และการเข้าร่วมรอบอื่นจะไม่เปลี่ยนแปลง',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dctx, false),
            child: const Text('ยกเลิก'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dctx, true),
            child: const Text('ถอด', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final actorUserId = AuthService.instance.currentUser?.id;
    if (actorUserId == null) return;
    try {
      await repo.removeParticipantFromSession(
        bookingId: bookingId,
        actorUserId: actorUserId,
      );
      if (!pageContext.mounted) return;
      ScaffoldMessenger.of(pageContext).showSnackBar(
        SnackBar(content: Text('ถอด "$memberName" ออกจากรอบนี้แล้ว')),
      );
      setSheetState(() {});
    } catch (e) {
      if (!pageContext.mounted) return;
      ScaffoldMessenger.of(pageContext).showSnackBar(
        SnackBar(content: Text('ถอดจากรอบไม่สำเร็จ: ${mapManagementError(e)}')),
      );
    }
  }
}
