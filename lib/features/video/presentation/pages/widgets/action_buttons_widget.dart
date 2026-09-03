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
  final bool isLiked; // ✅ [Support Analytics] DB toggle state

  // รายการคำร้องบริจาคที่ active อยู่ของวิดีโอนี้
  final List<DonationRequest> activeRequests;
  final int activeRequestIndex;

  /// true = ผู้ใช้มีสิทธิ์สร้างคำร้องบริจาค (Reporter/Responder ที่ผ่านเกณฑ์)
  /// false = ผู้ดูทั่วไป / ไทยมุง
  final bool userCanCreateRequest;

  final String yieldWayCount; // ✅ เพิ่มกลับมาเพื่อใช้แสดงผลข้อความ
  final int yieldWayCountValue; // ✅ เพิ่มค่าตัวเลขเพื่อคำนวณกราฟ
  final int
  yieldWayNotifiedCount; // ✅ เพิ่มจำนวนผู้ที่ถูกแจ้งเตือนเพื่อหาเปอร์เซ็นต์
  final VoidCallback onLike;
  final VoidCallback onYieldWay;
  final VoidCallback onDonate;

  /// เรียกเมื่อผู้ใช้กดลูกศรสลับดูคำร้อง (true = ถัดไป, false = ย้อนหลัง)
  final Function(bool forward)? onSwitchRequest;

  const ActionButtonsWidget({
    super.key,
    required this.likeCountFormatted,
    this.likeCount = 0,
    this.isLiked = false,
    required this.activeRequests,
    required this.yieldWayCount, // ✅ ตอนนี้มีฟิลด์รองรับแล้ว
    this.yieldWayCountValue = 0,
    this.yieldWayNotifiedCount = 0,
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
        _buildInteractionButtonRow(),
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
    // ✅ รองรับโหมด Reporter/Responder ที่ยังไม่มีคำร้อง active
    // (ต้องไม่ clamp กับ list ว่าง → จะ throw ArgumentError)
    final DonationRequest? req = activeRequests.isEmpty
        ? null
        : activeRequests[activeRequestIndex.clamp(
            0,
            activeRequests.length - 1,
          )];

    // คำนวณเปอร์เซ็นต์สำหรับกราฟบริจาค
    // ใช้ goalAmountGross (รวมค่าบริการแล้ว) ตามที่ USER ต้องการ หรือ targetAmount เป็นตัวสำรอง
    final double target = req?.goalAmountGross ?? req?.targetAmount ?? 0.0;
    final double current = req?.currentAmount ?? 0.0;
    final double percentage = target > 0
        ? (current / target).clamp(0.0, 1.0)
        : 0.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final double leftBoxWidth = 50.0;
        final double arrowWidth = 18.0;

        // พื้นที่ที่เหลือสำหรับกราฟ
        double maxBarWidth = constraints.maxWidth - leftBoxWidth;
        if (hasMultiple && !userCanCreateRequest) {
          maxBarWidth -= (arrowWidth * 2);
        }

        final double currentBarWidth = current == 0
            ? 0.0
            : maxBarWidth * percentage;

        return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // ลูกศรซ้าย (เฉพาะ Viewer + หลายคำร้อง)
            if (hasMultiple && !userCanCreateRequest)
              GestureDetector(
                onTap: () => onSwitchRequest?.call(false),
                child: Container(
                  width: arrowWidth,
                  height: 22,
                  decoration: BoxDecoration(
                    color: const Color(0xFF6B7280).withOpacity(0.5),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(4),
                      bottomLeft: Radius.circular(4),
                    ),
                  ),
                  child: const Icon(
                    Icons.chevron_left,
                    color: Colors.white,
                    size: 14,
                  ),
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
                  width: leftBoxWidth,
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF6B7280).withOpacity(0.8),
                    border: Border.all(color: Colors.white.withOpacity(0.2)),
                  ),
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          const Visibility(
                            maintainSize: true,
                            maintainAnimation: true,
                            maintainState: true,
                            visible: false,
                            child: Text(
                              '0',
                              style: TextStyle(
                                fontFamily: 'SukhumvitSet',
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              _donationDisplayValue,
                              style: const TextStyle(
                                fontFamily: 'SukhumvitSet',
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
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

            // กราฟแท่งบริจาค
            IntrinsicHeight(
              child: Row(
                children: [
                  GestureDetector(
                    onTap: onDonate,
                    child: Container(
                      width: currentBarWidth,
                      padding: const EdgeInsets.symmetric(
                        vertical: 2,
                        horizontal: 8,
                      ),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            _donationLabelColor.withOpacity(0.7),
                            _donationLabelColor,
                          ],
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                        ),
                      ),
                      alignment: Alignment.centerLeft,
                      child: current > 0
                          ? const FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                'บริจาค',
                                style: TextStyle(
                                  fontFamily: 'SukhumvitSet',
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                  ),

                  // ป้ายชื่อ (ส่วนที่เหลือของความกว้าง หรือป้ายชื่อเดิมกรณีไม่มีกราฟ)
                  GestureDetector(
                    onTap: onDonate,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: _donationLabelColor,
                        borderRadius: BorderRadius.only(
                          topRight: (hasMultiple && !userCanCreateRequest)
                              ? Radius.zero
                              : const Radius.circular(12),
                          bottomRight: (hasMultiple && !userCanCreateRequest)
                              ? Radius.zero
                              : const Radius.circular(12),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.2),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Center(
                        child: Text(
                          _donationLabel,
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
                    ),
                  ),
                ],
              ),
            ),

            // ลูกศรขวา (เฉพาะ Viewer + หลายคำร้อง)
            if (hasMultiple && !userCanCreateRequest)
              GestureDetector(
                onTap: () => onSwitchRequest?.call(true),
                child: Container(
                  width: arrowWidth,
                  height: 22,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF6B35).withOpacity(0.7),
                    borderRadius: const BorderRadius.only(
                      topRight: Radius.circular(4),
                      bottomRight: Radius.circular(4),
                    ),
                  ),
                  child: const Icon(
                    Icons.chevron_right,
                    color: Colors.white,
                    size: 14,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildInteractionButtonRow() {
    const orange = Color(0xFFFF6B35);

    // คำนวณเปอร์เซ็นต์สำหรับการให้ทาง
    // USER ต้องการ: เทียบกับจำนวนที่ระบบแจ้งเตือนไป (yieldWayNotifiedCount)
    final double percentage = yieldWayNotifiedCount > 0
        ? (yieldWayCountValue / yieldWayNotifiedCount).clamp(0.0, 1.0)
        : 0.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final double leftBoxWidth = 50.0;
        final double buttonWidth =
            32.0; // ใช้ความกว้างเดียวกับปุ่มหัวใจเพื่อให้ Layout ตรงกัน
        final double maxBarWidth =
            constraints.maxWidth - leftBoxWidth - buttonWidth;
        final double currentBarWidth = yieldWayCountValue == 0
            ? 0.0
            : maxBarWidth * percentage;

        return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // 1. Left Box: ตัวเลขยอดให้ทาง
            ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(4),
                bottomLeft: Radius.circular(4),
              ),
              child: Container(
                width: leftBoxWidth,
                padding: const EdgeInsets.symmetric(vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF6B7280).withOpacity(0.8),
                  border: Border.all(color: Colors.white.withOpacity(0.2)),
                ),
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        const Visibility(
                          maintainSize: true,
                          maintainAnimation: true,
                          maintainState: true,
                          visible: false,
                          child: Text(
                            '0',
                            style: TextStyle(
                              fontFamily: 'SukhumvitSet',
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            yieldWayCount,
                            style: const TextStyle(
                              fontFamily: 'SukhumvitSet',
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // 2. กราฟแท่งให้ทาง และ ปุ่มกด
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // กราฟแท่ง
                  Container(
                    width: currentBarWidth,
                    padding: const EdgeInsets.symmetric(
                      vertical: 2,
                      horizontal: 4,
                    ),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [orange.withOpacity(0.7), orange],
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                      ),
                    ),
                    alignment: Alignment.centerLeft,
                    child: yieldWayCountValue >= 1
                        ? const FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              'ให้ทาง',
                              maxLines: 1,
                              style: TextStyle(
                                fontFamily: 'SukhumvitSet',
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),

                  // ปุ่มกด (Right Box)
                  GestureDetector(
                    onTap: onYieldWay,
                    child: Container(
                      width: buttonWidth,
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      decoration: BoxDecoration(
                        color: orange,
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
                      child: const Center(
                        child: Icon(
                          Icons.emergency_share_rounded,
                          color: Colors.white,
                          size: 14,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
