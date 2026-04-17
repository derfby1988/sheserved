import 'package:flutter/material.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../models/donation_models.dart';

/// การ์ดแสดงคำร้องขอที่กำลังได้รับความนิยม
class TrendingDonationCard extends StatelessWidget {
  final DonationRequest request;
  final VoidCallback onTap;

  const TrendingDonationCard({
    super.key,
    required this.request,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        width: 157,
        height: 212,
        margin: const EdgeInsets.only(right: 16),
        decoration: BoxDecoration(
          color: const Color(0xFF7FA2C2), // Light blue background for text area
          borderRadius: BorderRadius.circular(10),
          boxShadow: const [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 4,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          children: [
            // Image area
            Hero(
              tag: 'donation_image_${request.id}',
              child: Container(
                width: 157,
                height: 157,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                ),
                clipBehavior: Clip.antiAlias,
                child: request.imageUrl != null
                    ? Image.network(request.imageUrl!, fit: BoxFit.cover)
                    : const Center(child: Icon(Icons.image, color: Colors.grey, size: 40)),
              ),
            ),
            // Title text area
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    request.title,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
