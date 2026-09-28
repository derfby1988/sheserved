import 'package:flutter/material.dart';
import 'package:sheserved/core/constants/app_colors.dart';
import 'package:sheserved/features/sport_club/presentation/widgets/sport_club_utils.dart';
import 'package:sheserved/shared/widgets/glass/glass_dialog.dart';
import 'package:sheserved/shared/widgets/glass/glass_primitives.dart';

import '../../../data/coach_models.dart';
import '../coach_labels.dart';

/// Completed/cancelled offering history — mirrors the
/// `GroupSessionHistoryDialog` pattern: a constrained Glass panel with a
/// locally-paginated list of past sessions.
class CoachOfferingHistoryDialog {
  const CoachOfferingHistoryDialog._();

  static Future<void> show(
    BuildContext context, {
    required CoachOffering offering,
  }) {
    return GlassDialog.show<void>(
      context: context,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      panelBorderRadius: 24,
      panelAccentColor: AppColors.primary,
      contentPadding: EdgeInsets.zero,
      builder: (_) => _CoachOfferingHistoryDialog(offering: offering),
    );
  }
}

class _CoachOfferingHistoryDialog extends StatefulWidget {
  const _CoachOfferingHistoryDialog({required this.offering});

  final CoachOffering offering;

  @override
  State<_CoachOfferingHistoryDialog> createState() =>
      _CoachOfferingHistoryDialogState();
}

class _CoachOfferingHistoryDialogState
    extends State<_CoachOfferingHistoryDialog> {
  static const _pageSize = 8;

  late final ScrollController _scrollController;
  late final List<CoachOfferingSession> _past;
  late int _visibleCount;

  @override
  void initState() {
    super.initState();
    _past = List.of(widget.offering.pastSessions)
      ..sort((a, b) => b.startsAt.compareTo(a.startsAt));
    _visibleCount = _past.length < _pageSize ? _past.length : _pageSize;
    _scrollController = ScrollController()..addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients || _visibleCount >= _past.length) {
      return;
    }
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      setState(
        () => _visibleCount = _visibleCount + _pageSize < _past.length
            ? _visibleCount + _pageSize
            : _past.length,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.offering;
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: 420,
        maxHeight: MediaQuery.of(context).size.height * 0.8,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.history_rounded,
                  color: AppColors.primary,
                  size: 24,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'ประวัติ — ${o.title}',
                        style: const TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        '${CoachLabels.offeringStatus(o.status)} · '
                        '${_past.length} รอบที่จบ/ยกเลิก',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: Colors.white.withValues(alpha: 0.65),
                        ),
                      ),
                    ],
                  ),
                ),
                GlassIconButton(
                  icon: Icons.close_rounded,
                  semanticsLabel: 'ปิด',
                  onTap: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Flexible(
              child: _past.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'ยังไม่มีรอบที่สิ้นสุดแล้ว',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: Colors.white.withValues(alpha: 0.65),
                        ),
                      ),
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      shrinkWrap: true,
                      itemCount: _visibleCount,
                      itemBuilder: (_, i) => _tile(_past[i], i),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tile(CoachOfferingSession s, int index) {
    final (label, color) = switch (s.status) {
      'completed' => ('จบแล้ว', const Color(0xFF1565C0)),
      'cancelled' => ('ยกเลิก', const Color(0xFFC62828)),
      _ => ('ผ่านไปแล้ว', const Color(0xFF64748B)),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: LitGlassSurface.frosted(
        borderRadius: 14,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'รอบที่ ${s.seq > 0 ? s.seq : index + 1} · '
                      '${formatThaiSessionRange(s.startsAt.toLocal(), s.endsAt.toLocal())}',
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                    Text(
                      [
                        if (s.locationLabel != null) s.locationLabel!,
                        if (s.capacity != null)
                          'ผู้เรียน ${s.confirmedCount}/${s.capacity}'
                        else
                          'ผู้เรียน ${s.confirmedCount} คน',
                      ].join(' · '),
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 7,
                  vertical: 2.5,
                ),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
