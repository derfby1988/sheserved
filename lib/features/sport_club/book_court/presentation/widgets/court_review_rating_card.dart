import 'package:flutter/material.dart';
import 'package:sheserved/core/constants/app_colors.dart';

import '../../data/book_court_models.dart';

/// Aggregate rating card + review list for the venue detail sheet.
class CourtReviewRatingCard extends StatelessWidget {
  final double? averageRating;
  final int reviewCount;
  final List<VenueReview> reviews;

  const CourtReviewRatingCard({
    super.key,
    this.averageRating,
    this.reviewCount = 0,
    this.reviews = const [],
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.star_rounded,
              color: AppColors.alertGold,
              size: 22,
            ),
            const SizedBox(width: 4),
            Text(
              averageRating == null
                  ? 'ยังไม่มีรีวิว'
                  : '${averageRating!.toStringAsFixed(1)} ($reviewCount รีวิว)',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            ),
          ],
        ),
        if (reviews.isNotEmpty) ...[
          const SizedBox(height: 8),
          for (final review in reviews.take(5))
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
                      crossAxisAlignment: CrossAxisAlignment.start,
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
                                        : Icons.star_outline_rounded,
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
      ],
    );
  }
}
