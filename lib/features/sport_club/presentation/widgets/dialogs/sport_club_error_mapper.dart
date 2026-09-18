import 'dart:async';

import 'package:flutter/material.dart';

OverlayEntry? _floatingManagementErrorEntry;

/// Shows a transient error message above the current page content.
void showFloatingManagementError(BuildContext context, String message) {
  _floatingManagementErrorEntry?.remove();
  _floatingManagementErrorEntry = null;

  final overlay = Overlay.of(context, rootOverlay: true);
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _FloatingManagementError(
      message: message,
      onDismiss: () {
        if (identical(_floatingManagementErrorEntry, entry)) {
          _floatingManagementErrorEntry = null;
        }
        if (entry.mounted) entry.remove();
      },
    ),
  );
  _floatingManagementErrorEntry = entry;
  overlay.insert(entry);
}

class _FloatingManagementError extends StatefulWidget {
  final String message;
  final VoidCallback onDismiss;

  const _FloatingManagementError({
    required this.message,
    required this.onDismiss,
  });

  @override
  State<_FloatingManagementError> createState() =>
      _FloatingManagementErrorState();
}

class _FloatingManagementErrorState extends State<_FloatingManagementError>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  Timer? _dismissTimer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
      reverseDuration: const Duration(milliseconds: 180),
    )..forward();
    _dismissTimer = Timer(const Duration(seconds: 4), _dismiss);
  }

  Future<void> _dismiss() async {
    if (!mounted) return;
    await _controller.reverse();
    if (mounted) widget.onDismiss();
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final animation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    final mediaQuery = MediaQuery.of(context);
    return Positioned(
      bottom: mediaQuery.viewInsets.bottom + mediaQuery.padding.bottom + 24,
      left: 16,
      right: 16,
      child: IgnorePointer(
        child: FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.15),
              end: Offset.zero,
            ).animate(animation),
            child: Semantics(
              container: true,
              liveRegion: true,
              child: Material(
                color: Colors.transparent,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.red.shade700,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black26,
                        blurRadius: 12,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: Colors.white),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          widget.message,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Maps raw database/RPC error strings to user-friendly Thai messages.
String mapManagementError(Object e, {bool sessionContext = false}) {
  final raw = e.toString();
  if (raw.contains('POSITION_REQUIRED')) {
    return 'ต้องระบุตำแหน่งของผู้ดูแลก๊วนสำหรับรอบนัดนี้';
  }
  if (raw.contains('POSITION_FULL')) {
    return 'ตำแหน่งที่เลือกเต็มแล้ว กรุณาเลือกตำแหน่งอื่น';
  }
  if (raw.contains('POSITION_INVALID')) {
    return 'ตำแหน่งที่เลือกไม่ถูกต้องหรือถูกปิดแล้ว';
  }
  if (raw.contains('SESSION_CAPACITY_BELOW_CONFIRMED')) {
    return 'จำนวนคนสูงสุดต้องไม่น้อยกว่าจำนวนผู้ยืนยันแล้วในรอบนี้';
  }
  if (raw.contains('OWNER_AUTO_JOIN_CAPACITY')) {
    return 'ไม่สามารถเปิดเข้าร่วมทุกรอบได้ เพราะมีรอบที่เต็มแล้ว';
  }
  if (raw.contains('GROUP_SESSION_OVERLAP')) {
    return 'รอบนัดนี้มีเวลาทับซ้อนกับรอบอื่นในก๊วน กรุณาเลือกเวลาใหม่';
  }
  if (raw.contains('OWNER_AUTO_JOIN_OVERLAP')) {
    if (sessionContext) {
      return 'รอบนัดนี้มีเวลาทับซ้อนกับรอบอื่นในก๊วน กรุณาเลือกเวลาใหม่';
    }
    return 'ไม่สามารถเปิดเข้าร่วมทุกรอบได้ เพราะมีรอบเวลาทับซ้อนกัน';
  }
  if (raw.contains('OWNER_ONLY')) {
    return 'เฉพาะเจ้าของก๊วนเท่านั้นที่เปลี่ยนการเข้าร่วมอัตโนมัติได้';
  }
  if (raw.contains('SESSION_FULL')) {
    return 'รอบนัดนี้เต็มแล้ว';
  }
  if (raw.contains('BOOKING_NOT_CONFIRMED')) {
    return 'ผู้ใช้นี้ไม่ได้ยืนยันเข้าร่วมรอบนี้แล้ว';
  }
  if (raw.contains('CANNOT_REDUCE_LAYOUT_ACTIVE_BOOKINGS')) {
    return 'ไม่สามารถลดขนาดสนามได้ เนื่องจากมีรอบนัดที่มีการจองตำแหน่งที่ถูกตัดออก';
  }
  if (raw.contains('OWNER_USE_PARTICIPATION_TOGGLE')) {
    return 'เจ้าของก๊วนต้องใช้เมนูการเข้าร่วมของเจ้าของก๊วน';
  }
  if (raw.contains('NOT_GROUP_ADMIN')) {
    return 'คุณไม่มีสิทธิ์จัดการก๊วนนี้';
  }
  if (raw.contains('UNAUTHORIZED')) {
    return 'กรุณาเข้าสู่ระบบใหม่แล้วลองอีกครั้ง';
  }
  return 'ดำเนินการไม่สำเร็จ กรุณาลองใหม่อีกครั้ง';
}

/// Maps booking approval error strings to user-friendly Thai messages.
String mapApprovalError(Object e) {
  final raw = e.toString();
  if (raw.contains('POSITION_FULL')) {
    return 'ตำแหน่งที่ผู้สมัครเลือกเต็มแล้ว ไม่สามารถอนุมัติได้\n'
        '(ระบบคงคำขอไว้เป็น "รออนุมัติ" และแจ้งผู้สมัครให้เลือกตำแหน่งใหม่แล้ว)';
  }
  if (raw.contains('SESSION_FULL')) {
    return 'รอบนัดนี้เต็มแล้ว ไม่สามารถอนุมัติผู้ขอรายนี้ได้\n'
        'กรุณาปฏิเสธคำขอ หรือเพิ่ม capacity ของรอบนัดก่อน';
  }
  return 'อนุมัติไม่สำเร็จ: ${mapManagementError(e)}';
}
