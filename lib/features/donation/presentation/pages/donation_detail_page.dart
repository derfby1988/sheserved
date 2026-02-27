import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../models/donation_models.dart';

class DonationDetailPage extends StatelessWidget {
  final DonationRequest request;

  const DonationDetailPage({super.key, required this.request});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: CustomScrollView(
        slivers: [
          // Hero Image Header
          SliverAppBar(
            expandedHeight: 300,
            pinned: true,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: Hero(
                tag: 'donation_image_${request.id}',
                child: Image.network(
                  request.imageUrl ?? "https://placehold.co/600x400/76A5A5/FFFFFF?text=${request.title}",
                  fit: BoxFit.cover,
                ),
              ),
            ),
          ),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          request.title,
                          style: AppTextStyles.heading2.copyWith(color: AppColors.primary),
                        ),
                      ),
                      if (request.isTrending)
                        const Chip(
                          label: Text('Trending', style: TextStyle(color: Colors.white, fontSize: 12)),
                          backgroundColor: Colors.orange,
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  
                  // Progress Section
                  Text(
                    'ความคืบหน้าการระดมทุน',
                    style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: LinearProgressIndicator(
                      value: request.progress,
                      minHeight: 12,
                      backgroundColor: Colors.grey[200],
                      valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('ได้แล้ว: ${request.currentAmount.toInt().toString()} บ.', style: AppTextStyles.bodySmall),
                      Text('เป้าหมาย: ${request.targetAmount?.toInt().toString() ?? '∞'} บ.', style: AppTextStyles.bodySmall),
                    ],
                  ),
                  
                  const Divider(height: 40),
                  
                  Text(
                    'รายละเอียดกิจกรรม',
                    style: AppTextStyles.heading3.copyWith(color: Colors.black87),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    request.description ?? 'ไม่มีรายละเอียดเพิ่มเติมสำหรับรายการนี้',
                    style: AppTextStyles.bodyLarge.copyWith(height: 1.6),
                  ),
                  if (request.neededDate != null || request.usageLocation != null) ...[
                    const SizedBox(height: 32),
                    Text(
                      'ข้อมูลพื้นที่และความจำเป็น',
                      style: AppTextStyles.heading3.copyWith(color: Colors.black87),
                    ),
                    const SizedBox(height: 12),
                    if (request.neededDate != null)
                      _InfoRow(icon: Icons.event, label: 'วันที่จำเป็นต้องใช้', value: request.neededDate.toString().split(' ')[0]),
                    if (request.usageLocation != null)
                      _InfoRow(icon: Icons.location_on, label: 'สถานที่ใช้ความช่วยเหลือ', value: request.usageLocation!),
                  ],
                  
                  const SizedBox(height: 100), // Space for bottom button
                ],
              ),
            ),
          ),
        ],
      ),
      bottomSheet: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, -5),
            ),
          ],
        ),
        child: ElevatedButton(
          onPressed: () {
            // TODO: Implement Payment/Contribution flow
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            minimumSize: const Size(double.infinity, 54),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: const Text('ร่วมบริจาคตอนนี้', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRow({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppColors.primary),
          const SizedBox(width: 8),
          Text('$label:', style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(width: 8),
          Expanded(child: Text(value, style: AppTextStyles.bodyMedium)),
        ],
      ),
    );
  }
}
