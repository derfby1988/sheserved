import 'package:flutter/material.dart';
import 'package:sheserved/core/constants/app_colors.dart';

import '../../application/court_card_style_service.dart';
import '../../data/book_court_models.dart';
import '../../domain/court_card_style.dart';
import 'court_card.dart';

/// Admin tab "รูปแบบการ์ด": previews every Court Card style and stores the
/// chosen one in `app_settings`, so the Book Court feed renders that style on
/// every device.
class CourtCardStylePanel extends StatefulWidget {
  final CourtCardStyleService? service;

  const CourtCardStylePanel({super.key, this.service});

  @override
  State<CourtCardStylePanel> createState() => _CourtCardStylePanelState();
}

class _CourtCardStylePanelState extends State<CourtCardStylePanel> {
  CourtCardStyleService get _service =>
      widget.service ?? CourtCardStyleService.instance;

  bool _loading = true;
  CourtCardStyle? _saving;

  static final VenueSummary _previewVenue = VenueSummary(
    id: 'preview-venue',
    name: 'สนามตัวอย่าง สุขุมวิท',
    district: 'คลองเตย',
    province: 'กรุงเทพฯ',
    timezone: 'Asia/Bangkok',
    courtCount: 6,
    averageRating: 4.3,
    reviewCount: 18,
    startingPriceAmount: 250,
    amenityIds: const {'parking', 'shower', 'lighting'},
  );

  static final List<VenueBooking> _previewBookings = [
    VenueBooking(
      id: 'preview-booking',
      courtId: 'preview-court',
      venueId: _previewVenue.id,
      sportId: 'preview-sport',
      startsAt: DateTime.now().add(const Duration(hours: 2, minutes: 15)),
      endsAt: DateTime.now().add(const Duration(hours: 3, minutes: 15)),
      status: VenueBookingStatus.confirmed,
      courtName: '3',
      unitLabel: 'คอร์ท',
      priceTotal: 250,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    await _service.load(force: true);
    if (!mounted) return;
    setState(() => _loading = false);
  }

  Future<void> _select(CourtCardStyle style) async {
    if (_saving != null) return;
    setState(() => _saving = style);
    final persisted = await _service.select(style);
    if (!mounted) return;
    setState(() => _saving = null);
    _toast(
      persisted
          ? 'ใช้รูปแบบ "${style.label}" กับการ์ดสนามของทุกเครื่องแล้ว'
          : 'เปลี่ยนบนเครื่องนี้แล้ว แต่บันทึกขึ้นเซิร์ฟเวอร์ไม่สำเร็จ',
    );
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<CourtCardStyle>(
      valueListenable: _service.style,
      builder: (context, selected, _) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          _header(selected),
          if (_loading)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: LinearProgressIndicator(minHeight: 2),
            ),
          const SizedBox(height: 12),
          for (final style in CourtCardStyle.values) ...[
            _styleTile(style, selected),
            const SizedBox(height: 14),
          ],
        ],
      ),
    );
  }

  Widget _header(CourtCardStyle selected) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primaryDark.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'รูปแบบการ์ดสนาม (Book Court)',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            'รูปแบบที่เลือกมีผลกับการ์ดสนามในหน้า Book Court ของทุกคน '
            'และบันทึกไว้ในตาราง app_settings',
            style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700),
          ),
          const SizedBox(height: 6),
          Text(
            'ใช้อยู่ตอนนี้: ${selected.label}',
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: AppColors.primaryDark,
            ),
          ),
        ],
      ),
    );
  }

  Widget _styleTile(CourtCardStyle style, CourtCardStyle selected) {
    final isSelected = style == selected;
    final isSaving = _saving == style;
    return Container(
      key: ValueKey('court-card-style-${style.wireValue}'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isSelected ? AppColors.primaryDark : Colors.grey.shade300,
          width: isSelected ? 1.8 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  style.label,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (isSelected)
                const Row(
                  children: [
                    Icon(
                      Icons.check_circle_rounded,
                      size: 18,
                      color: AppColors.primaryDark,
                    ),
                    SizedBox(width: 4),
                    Text(
                      'ใช้อยู่',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primaryDark,
                      ),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            style.description,
            style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700),
          ),
          const SizedBox(height: 10),
          // Previews are non-interactive: tapping the button selects.
          IgnorePointer(
            child: CourtCard(
              venue: _previewVenue,
              distanceKm: 3.4,
              upcomingBookings: _previewBookings,
              styleOverride: style,
            ),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              key: ValueKey('court-card-style-select-${style.wireValue}'),
              onPressed: isSaving ? null : () => _select(style),
              icon: isSaving
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check_rounded, size: 18),
              label: Text(isSelected ? 'เลือกซ้ำ' : 'ใช้รูปแบบนี้'),
            ),
          ),
        ],
      ),
    );
  }
}
