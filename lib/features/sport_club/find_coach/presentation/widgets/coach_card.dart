import 'package:flutter/material.dart';
import 'package:sheserved/core/constants/app_colors.dart';

import '../../data/coach_models.dart';

/// Coach card for the Find Coach directory.
class CoachCard extends StatelessWidget {
  final CoachSummary coach;
  final double? distanceKm;
  final VoidCallback? onTap;

  const CoachCard({super.key, required this.coach, this.distanceKm, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 1.5,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 26,
                backgroundImage: (coach.avatarUrl?.isNotEmpty == true)
                    ? NetworkImage(coach.avatarUrl!)
                    : null,
                child: coach.avatarUrl?.isNotEmpty == true
                    ? null
                    : const Icon(Icons.person, size: 26),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            coach.displayName,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (coach.isVerified)
                          Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: Icon(
                              Icons.verified_rounded,
                              size: 16,
                              color: Colors.blue.shade700,
                            ),
                          ),
                        if (coach.averageRating != null) ...[
                          const Icon(
                            Icons.star_rounded,
                            size: 16,
                            color: AppColors.alertGold,
                          ),
                          Text(
                            coach.averageRating!.toStringAsFixed(1),
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (coach.hourlyRate != null)
                          Text(
                            '${coach.hourlyRate!.toStringAsFixed(0)} บาท/ชม.',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.primaryDark,
                            ),
                          ),
                        const SizedBox(width: 8),
                        Text(
                          _modeLabel(coach.teachingMode),
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade700,
                          ),
                        ),
                        const Spacer(),
                        if (distanceKm != null)
                          Text(
                            '${distanceKm!.toStringAsFixed(1)} กม.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                          ),
                      ],
                    ),
                    if (coach.specialties.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: [
                          for (final spec in coach.specialties.take(4))
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                spec,
                                style: const TextStyle(fontSize: 11),
                              ),
                            ),
                        ],
                      ),
                    ],
                    if (coach.serviceAreas.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            Icons.place_outlined,
                            size: 13,
                            color: Colors.grey.shade600,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              coach.serviceAreas
                                  .map(
                                    (a) => [
                                      a.district,
                                      a.province,
                                    ].whereType<String>().join(', '),
                                  )
                                  .where((s) => s.isNotEmpty)
                                  .take(2)
                                  .join(' • '),
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _modeLabel(TeachingMode mode) => switch (mode) {
    TeachingMode.online => 'ออนไลน์',
    TeachingMode.both => 'ออนไซต์ + ออนไลน์',
    _ => 'ออนไซต์',
  };
}
