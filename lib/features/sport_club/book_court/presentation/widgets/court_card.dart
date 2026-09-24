import 'package:flutter/material.dart';
import 'package:sheserved/core/constants/app_colors.dart';

import '../../data/book_court_models.dart';

/// Venue card for the Book Court discovery feed.
class CourtCard extends StatelessWidget {
  final VenueSummary venue;
  final double? distanceKm;
  final VoidCallback? onTap;

  const CourtCard({super.key, required this.venue, this.distanceKm, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 1.5,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (venue.photoUrls.isNotEmpty)
              SizedBox(
                height: 140,
                width: double.infinity,
                child: Image.network(
                  venue.photoUrls.first,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Container(
                    height: 140,
                    color: Colors.grey.shade200,
                    child: const Icon(Icons.image_not_supported_outlined),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          venue.name,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (venue.averageRating != null) ...[
                        const Icon(
                          Icons.star_rounded,
                          size: 16,
                          color: AppColors.alertGold,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          venue.averageRating!.toStringAsFixed(1),
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                        Text(
                          ' (${venue.reviewCount})',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        Icons.place_outlined,
                        size: 14,
                        color: Colors.grey.shade600,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          [
                            venue.district,
                            venue.province,
                          ].whereType<String>().join(', '),
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade700,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
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
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        Icons.sports_tennis_rounded,
                        size: 14,
                        color: Colors.grey.shade600,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${venue.courtCount} สนาม/คอร์ท',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade700,
                        ),
                      ),
                      const Spacer(),
                      if (venue.amenityIds.isNotEmpty)
                        Row(
                          children: [
                            for (final key in venue.amenityIds.take(4))
                              Padding(
                                padding: const EdgeInsets.only(left: 4),
                                child: Icon(
                                  _amenityIcon(key),
                                  size: 15,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                          ],
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static IconData _amenityIcon(String key) => switch (key) {
    'parking' => Icons.local_parking_rounded,
    'restroom' => Icons.wc_rounded,
    'shower' => Icons.shower_rounded,
    'ev_charging' => Icons.ev_station_rounded,
    'equipment_rental' => Icons.sports_baseball_rounded,
    'lighting' => Icons.lightbulb_outline_rounded,
    'locker' => Icons.lock_rounded,
    'wifi' => Icons.wifi_rounded,
    'cafe' => Icons.local_cafe_rounded,
    'first_aid' => Icons.medical_services_rounded,
    _ => Icons.check_circle_outline_rounded,
  };
}
