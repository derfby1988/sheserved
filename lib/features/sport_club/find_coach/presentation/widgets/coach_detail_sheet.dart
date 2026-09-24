import 'package:flutter/material.dart';
import 'package:sheserved/core/constants/app_colors.dart';

import '../../data/coach_models.dart';
import '../../data/find_coach_repository.dart';

/// Coach detail sheet: bio, sports/specialties, service areas, weekly
/// availability and reviews. Read-only — booking requests are started via
/// [onRequest] so discovery never creates requests.
class CoachDetailSheet extends StatefulWidget {
  final CoachSummary coach;
  final FindCoachRepository repo;
  final ScrollController? scrollController;
  final Future<void> Function()? onRequest;

  const CoachDetailSheet({
    super.key,
    required this.coach,
    required this.repo,
    this.scrollController,
    this.onRequest,
  });

  static Future<void> show(
    BuildContext context, {
    required CoachSummary coach,
    required FindCoachRepository repo,
    Future<void> Function()? onRequest,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => DraggableScrollableSheet(
        initialChildSize: 0.8,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, scrollController) => CoachDetailSheet(
          coach: coach,
          repo: repo,
          scrollController: scrollController,
          onRequest: onRequest,
        ),
      ),
    );
  }

  @override
  State<CoachDetailSheet> createState() => _CoachDetailSheetState();
}

class _CoachDetailSheetState extends State<CoachDetailSheet> {
  List<CoachAvailabilityWindow> _availability = [];
  List<CoachReview> _reviews = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        widget.repo.listCoachAvailability(widget.coach.id),
        widget.repo.listCoachReviews(widget.coach.id),
      ]);
      if (!mounted) return;
      setState(() {
        _availability = results[0] as List<CoachAvailabilityWindow>;
        _reviews = results[1] as List<CoachReview>;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final coach = widget.coach;
    return Material(
      color: Colors.white,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      child: _loading
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(48),
                child: CircularProgressIndicator(),
              ),
            )
          : ListView(
              controller: widget.scrollController,
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    CircleAvatar(
                      radius: 30,
                      backgroundImage:
                          (coach.avatarUrl?.isNotEmpty == true)
                          ? NetworkImage(coach.avatarUrl!)
                          : null,
                      child: coach.avatarUrl?.isNotEmpty == true
                          ? null
                          : const Icon(Icons.person, size: 30),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  coach.displayName,
                                  style: const TextStyle(
                                    fontSize: 19,
                                    fontWeight: FontWeight.w800,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (coach.isVerified) ...[
                                const SizedBox(width: 4),
                                Icon(
                                  Icons.verified_rounded,
                                  size: 18,
                                  color: Colors.blue.shade700,
                                ),
                              ],
                            ],
                          ),
                          if (coach.hourlyRate != null)
                            Text(
                              '${coach.hourlyRate!.toStringAsFixed(0)} บาท/ชั่วโมง • ${_modeLabel(coach.teachingMode)}',
                              style: const TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                                color: AppColors.primaryDark,
                              ),
                            ),
                          if (coach.averageRating != null)
                            Text(
                              '⭐ ${coach.averageRating!.toStringAsFixed(1)} (${coach.reviewCount} รีวิว)',
                              style: TextStyle(
                                fontSize: 12.5,
                                color: Colors.grey.shade700,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (coach.bio?.isNotEmpty == true) ...[
                  const SizedBox(height: 12),
                  Text(
                    coach.bio!,
                    style: TextStyle(
                      fontSize: 13.5,
                      color: Colors.grey.shade800,
                    ),
                  ),
                ],
                if (coach.specialties.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Text(
                    'ความเชี่ยวชาญ',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      for (final spec in coach.specialties)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            spec,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.primaryDark,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
                if (coach.skillLevels.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    'ระดับ: ${coach.skillLevels.map(_levelLabel).join(', ')}',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ],
                if (coach.serviceAreas.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Text(
                    'พื้นที่ให้บริการ',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  for (final area in coach.serviceAreas)
                    Text(
                      '• ${[area.district, area.province].whereType<String>().join(', ')}'
                      '${area.radiusKm != null ? ' (รัศมี ${area.radiusKm!.toStringAsFixed(0)} กม.)' : ''}',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade700,
                      ),
                    ),
                ],
                const SizedBox(height: 12),
                const Text(
                  'ตารางว่างประจำสัปดาห์',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                if (_availability.isEmpty)
                  Text(
                    'โค้ชยังไม่ได้ตั้งตารางว่าง',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade600,
                    ),
                  )
                else
                  for (final w in _availability)
                    Text(
                      '${_dayLabel(w.dayOfWeek)}: ${w.startTime}–${w.endTime}',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade700,
                      ),
                    ),
                const SizedBox(height: 8),
                Text(
                  'เวลาแสดงตามเขตเวลาโค้ช (${coach.timezone})',
                  style: TextStyle(fontSize: 11.5, color: Colors.grey.shade500),
                ),
                if (_reviews.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const Text(
                    'รีวิวล่าสุด',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  for (final review in _reviews.take(5))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CircleAvatar(
                            radius: 14,
                            backgroundImage:
                                (review.userAvatarUrl?.isNotEmpty == true)
                                ? NetworkImage(review.userAvatarUrl!)
                                : null,
                            child: review.userAvatarUrl?.isNotEmpty == true
                                ? null
                                : const Icon(Icons.person, size: 14),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        review.userDisplayName ?? 'ผู้ใช้',
                                        style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    Row(
                                      children: [
                                        for (var i = 0; i < 5; i++)
                                          Icon(
                                            i < review.rating
                                                ? Icons.star_rounded
                                                : Icons
                                                      .star_outline_rounded,
                                            size: 12,
                                            color: AppColors.alertGold,
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                                if (review.comment?.isNotEmpty == true)
                                  Text(
                                    review.comment!,
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      color: Colors.grey.shade700,
                                    ),
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
                if (widget.onRequest != null) ...[
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primaryDark,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: widget.onRequest,
                      icon: const Icon(Icons.send_rounded, size: 18),
                      label: const Text('ขอนัดกับโค้ช'),
                    ),
                  ),
                ],
              ],
            ),
    );
  }

  static String _modeLabel(TeachingMode mode) => switch (mode) {
    TeachingMode.online => 'ออนไลน์',
    TeachingMode.both => 'ออนไซต์ + ออนไลน์',
    _ => 'ออนไซต์',
  };

  static String _levelLabel(String level) => switch (level) {
    'beginner' => 'เริ่มต้น',
    'intermediate' => 'ระดับกลาง',
    'advanced' => 'ขั้นสูง',
    'pro' => 'อาชีพ',
    _ => level,
  };

  static String _dayLabel(int dow) => switch (dow) {
    0 => 'อาทิตย์',
    1 => 'จันทร์',
    2 => 'อังคาร',
    3 => 'พุธ',
    4 => 'พฤหัสบดี',
    5 => 'ศุกร์',
    6 => 'เสาร์',
    _ => '',
  };
}
