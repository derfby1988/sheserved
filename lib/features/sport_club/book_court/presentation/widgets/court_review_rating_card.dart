import 'package:flutter/material.dart';
import 'package:sheserved/core/constants/app_colors.dart';

import '../../data/book_court_models.dart';

/// Compact review summary for the venue detail sheet. Shows the
/// aggregate 1–10 score, a short preview of recent published reviews and
/// a link to the full review page.
class CourtReviewRatingCard extends StatelessWidget {
  final double? averageRating;
  final int reviewCount;
  final List<VenueReview> reviews;
  final VenueOwnerPublicProfile? ownerProfile;
  final VoidCallback? onSeeAll;

  const CourtReviewRatingCard({
    super.key,
    this.averageRating,
    this.reviewCount = 0,
    this.reviews = const [],
    this.ownerProfile,
    this.onSeeAll,
  });

  @override
  Widget build(BuildContext context) {
    final avatarUrl = ownerProfile?.avatarUrl?.trim();
    final hasAvatar = avatarUrl?.isNotEmpty == true;
    final ownerName = ownerProfile?.displayName?.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (ownerProfile != null) ...[
          Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: AppColors.primary.withValues(alpha: 0.12),
                child: hasAvatar
                    ? ClipOval(
                        child: Image.network(
                          avatarUrl!,
                          width: 40,
                          height: 40,
                          fit: BoxFit.cover,
                          loadingBuilder: (context, child, progress) =>
                              progress == null
                              ? child
                              : const Center(
                                  child: SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 1.5,
                                    ),
                                  ),
                                ),
                          errorBuilder: (context, error, stackTrace) =>
                              const Icon(
                                Icons.person_rounded,
                                size: 20,
                                color: AppColors.primaryDark,
                              ),
                        ),
                      )
                    : const Icon(
                        Icons.person_rounded,
                        size: 20,
                        color: AppColors.primaryDark,
                      ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'เจ้าของสถานที่',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    Text(
                      ownerName?.isNotEmpty == true
                          ? ownerName!
                          : 'เจ้าของสถานที่',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
        ],
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.primaryDark,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                averageRating?.toStringAsFixed(1) ?? '-',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                averageRating == null ? 'ยังไม่มีรีวิว' : '$reviewCount รีวิว',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
            ),
            if (onSeeAll != null && reviewCount > 0)
              TextButton(
                onPressed: onSeeAll,
                child: const Text('ดูรีวิวทั้งหมด'),
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
                    backgroundImage: (review.userAvatarUrl?.isNotEmpty == true)
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
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.primaryDark.withValues(
                                  alpha: 0.1,
                                ),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                review.rating10.toStringAsFixed(1),
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.primaryDark,
                                ),
                              ),
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
