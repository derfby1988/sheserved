import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:sheserved/features/donation/models/donation_models.dart';
import 'like_trend_chart_widget.dart'; // ✅ นำเข้า Widget ใหม่

/// ActionButtonsWidget — ปุ่มโต้ตอบ: ส่งกำลังใจ / ให้ทาง / บริจาค
///
/// ปุ่ม "บริจาค" ทำงาน 2 โหมดตามบทบาทผู้ใช้:
/// - [userCanCreateRequest] = true  → โหมด "เปิดรับบริจาค" (Reporter ที่มีผู้ช่วยเหลือมาถึงแล้ว / Responder)
///   Reporter: เห็นปุ่มได้ก็ต่อเมื่อมีผู้ช่วยเหลือรายอื่นเดินทางมาถึง (status=arrived) แล้วเท่านั้น
///   Responder: เห็นปุ่มได้ทันที (รับงานแล้ว + อาชีพตรง)
/// - [userCanCreateRequest] = false → โหมด "บริจาค" (Viewer/ThaiMhung)
///   แสดงเฉพาะเมื่อมีคำร้อง active ≥ 1 ใบ เพื่อไม่สร้างความสับสน
class ActionButtonsWidget extends StatelessWidget {
  final String likeCountFormatted;
  final int likeCount; // ✅ เพิ่มตัวแปรยอดไลค์แบบตัวเลข
  final bool isLiked;  // ✅ [Support Analytics] DB toggle state

  // รายการคำร้องบริจาคที่ active อยู่ของวิดีโอนี้
  final List<DonationRequest> activeRequests;
  final int activeRequestIndex;

  /// true = ผู้ใช้มีสิทธิ์สร้างคำร้องบริจาค (Reporter/Responder ที่ผ่านเกณฑ์)
  /// false = ผู้ดูทั่วไป / ไทยมุง
  final bool userCanCreateRequest;

  final String yieldWayCount;
  final VoidCallback onLike;
  final VoidCallback onYieldWay;
  final VoidCallback onDonate;

  /// เรียกเมื่อผู้ใช้กดลูกศรสลับดูคำร้อง (true = ถัดไป, false = ย้อนหลัง)
  final Function(bool forward)? onSwitchRequest;

  const ActionButtonsWidget({
    super.key,
    required this.likeCountFormatted,
    this.likeCount = 0, // ✅ กำหนดค่าเริ่มต้น
    this.isLiked = false,
    required this.activeRequests,
    required this.yieldWayCount,
    this.activeRequestIndex = 0,
    this.userCanCreateRequest = false,
    required this.onLike,
    required this.onYieldWay,
    required this.onDonate,
    this.onSwitchRequest,
  });

  /// ✅ ตรรกะ: ควรแสดงปุ่มบริจาคไหม?
  /// - Reporter/Responder → แสดงเสมอ (เพื่อสร้างคำร้อง)
  /// - Viewer → แสดงเฉพาะเมื่อมีคำร้อง active อยู่
  bool get _showDonateButton =>
      userCanCreateRequest || activeRequests.isNotEmpty;

  String get _donationDisplayValue {
    if (activeRequests.isEmpty) return '+';
    final req =
        activeRequests[activeRequestIndex.clamp(0, activeRequests.length - 1)];
    final current = req.currentAmount ?? 0;
    if (current >= 1000) {
      final k = current / 1000;
      return k == k.roundToDouble()
          ? '${k.round()}K'
          : '${k.toStringAsFixed(1)}K';
    }
    return NumberFormat('#,##0').format(current);
  }

  String get _donationLabel {
    // โหมดสร้างคำร้อง (Reporter/Responder)
    if (userCanCreateRequest && activeRequests.isEmpty) {
      return 'เปิดรับบริจาค';
    }
    if (userCanCreateRequest && activeRequests.isNotEmpty) {
      return 'รับบริจาค';
    }
    // โหมดบริจาค (Viewer)
    if (activeRequests.length > 1) {
      final idx = activeRequestIndex.clamp(0, activeRequests.length - 1);
      final req = activeRequests[idx];
      // แสดงชื่อคำร้อง (title) แทนตัวเลขลำดับ เพื่อให้รู้ว่ากำลังบริจาคให้สิ่งใด
      return req.title.isNotEmpty ? req.title : 'บริจาค';
    }
    return 'บริจาค';
  }

  /// สีพื้นหลังของป้ายชื่อปุ่ม:
  /// - โหมดสร้างคำร้อง (Reporter/Responder) → เขียว-เน้น
  /// - โหมดบริจาค (Viewer) → ส้มเดิม
  Color get _donationLabelColor {
    if (userCanCreateRequest) {
      return activeRequests.isEmpty
          ? const Color(0xFF2DC653) // เขียว: ยังไม่มีคำร้อง สร้างได้เลย
          : const Color(0xFF1A8FD1); // น้ำเงิน: มีคำร้องอยู่แล้ว เพิ่มได้
    }
    return const Color(0xFFFF6B35); // ส้มเดิมสำหรับ Viewer
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ✅ ใช้ LikeTrendChartWidget แทนแถว "ส่งกำลังใจ" แบบเดิม
        LikeTrendChartWidget(
          isLiked: isLiked,
          likeCount: likeCount,
          likeCountFormatted: likeCountFormatted,
          onToggleLike: onLike,
        ),
        const SizedBox(height: 6),
        _buildInteractionButtonRow(
          value: yieldWayCount,
          label: 'ให้ทาง',
          onTap: onYieldWay,
        ),
        // ✅ ซ่อนปุ่มบริจาคสำหรับ Viewer เมื่อยังไม่มีคำร้อง active
        if (_showDonateButton) ...[
          const SizedBox(height: 6),
          _buildDonationRow(),
        ],
      ],
    );
  }

  /// แถวบริจาค — มีลูกศรสลับคำร้อง หากมีหลายใบ
  Widget _buildDonationRow() {
    final hasMultiple = activeRequests.length > 1;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ลูกศรซ้าย (เฉพาะ Viewer + หลายคำร้อง)
        if (hasMultiple && !userCanCreateRequest)
          GestureDetector(
            onTap: () => onSwitchRequest?.call(false),
            child: Container(
              width: 18,
              height: 22,
              decoration: BoxDecoration(
                color: const Color(0xFF6B7280).withOpacity(0.5),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(4),
                  bottomLeft: Radius.circular(4),
                ),
              ),
              child:
                  const Icon(Icons.chevron_left, color: Colors.white, size: 14),
            ),
          ),

        // ค่าตัวเลข (ยอดบริจาค หรือ '+' ถ้ายังไม่มี)
        GestureDetector(
          onTap: onDonate,
          child: ClipRRect(
            borderRadius: (hasMultiple && !userCanCreateRequest)
                ? BorderRadius.zero
                : const BorderRadius.only(
                    topLeft: Radius.circular(4),
                    bottomLeft: Radius.circular(4),
                  ),
            child: Container(
              width: 50, // ลดจาก 70 เหลือ 50
              padding: const EdgeInsets.symmetric(vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF6B7280).withOpacity(0.8),
                border:
                    Border.all(color: Colors.white.withOpacity(0.2)),
              ),
              child: Center(
                child: Text(
                  _donationDisplayValue,
                  style: const TextStyle(
                    fontFamily: 'SukhumvitSet',
                    fontSize: 12, // ลดจาก 14 เหลือ 12
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ),

        // ป้ายชื่อ (เปลี่ยนสีตามโหมด)
        GestureDetector(
          onTap: onDonate,
          child: Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
              decoration: BoxDecoration(
                color: _donationLabelColor,
                borderRadius: const BorderRadius.only(
                  topRight: Radius.circular(12),
                  bottomRight: Radius.circular(12),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Text(
                _donationLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: 'SukhumvitSet',
                  fontSize: 11, // ลดจาก 12 เหลือ 11
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ),

        // ลูกศรขวา (เฉพาะ Viewer + หลายคำร้อง)
        if (hasMultiple && !userCanCreateRequest)
          GestureDetector(
            onTap: () => onSwitchRequest?.call(true),
            child: Container(
              width: 18,
              height: 22,
              decoration: BoxDecoration(
                color: const Color(0xFFFF6B35).withOpacity(0.7),
                borderRadius: const BorderRadius.only(
                  topRight: Radius.circular(4),
                  bottomRight: Radius.circular(4),
                ),
              ),
              child: const Icon(Icons.chevron_right,
                  color: Colors.white, size: 14),
            ),
          ),
      ],
    );
  }

  Widget _buildInteractionButtonRow({
    required String value,
    required String label,
    required VoidCallback onTap,
    bool isActive = false,
  }) {
    const orange = Color(0xFFFF6B35);
    return GestureDetector(
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(4),
              bottomLeft: Radius.circular(4),
            ),
            child: Container(
              width: 50,
              padding: const EdgeInsets.symmetric(vertical: 2),
              decoration: BoxDecoration(
                color: isActive
                    ? orange.withOpacity(0.85)
                    : const Color(0xFF6B7280).withOpacity(0.8),
                border: Border.all(color: Colors.white.withOpacity(0.2)),
              ),
              child: Center(
                child: Text(
                  value,
                  style: const TextStyle(
                    fontFamily: 'SukhumvitSet',
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: isActive ? orange : orange,
                borderRadius: const BorderRadius.only(
                  topRight: Radius.circular(12),
                  bottomRight: Radius.circular(12),
                ),
                boxShadow: [
                  BoxShadow(
                    color: isActive
                        ? orange.withOpacity(0.5)
                        : Colors.black.withOpacity(0.2),
                    blurRadius: isActive ? 8 : 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isActive) ...[
                    const Icon(Icons.favorite, color: Colors.white, size: 10),
                    const SizedBox(width: 3),
                  ],
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'SukhumvitSet',
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
