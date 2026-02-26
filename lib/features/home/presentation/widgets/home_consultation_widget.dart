import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_text_styles.dart';
import '../../../../features/auth/data/repositories/user_repository.dart';
import 'home_painters.dart';

/// Consultation Widget - วงกลมปรึกษาแพทย์และเภสัช
class HomeConsultationWidget extends StatefulWidget {
  final VoidCallback? onTap;
  final int? availableCount;
  final bool useRealtime;

  const HomeConsultationWidget({
    super.key,
    this.onTap,
    this.availableCount,
    this.useRealtime = true,
  });

  @override
  State<HomeConsultationWidget> createState() => _HomeConsultationWidgetState();
}

class _HomeConsultationWidgetState extends State<HomeConsultationWidget> {
  int _count = 0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    if (widget.availableCount != null) {
      _count = widget.availableCount!;
      _isLoading = false;
    } else if (widget.useRealtime) {
      _loadCount();
    }
  }

  Future<void> _loadCount() async {
    try {
      final repo = UserRepository(Supabase.instance.client);
      final count = await repo.getTotalOnlineProviderCount();
      if (mounted) {
        setState(() {
          _count = count;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Outer Solid Green Ring
            SizedBox(
              width: 280,
              height: 280,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Solid Green Circle (outer ring)
                  Container(
                    width: 280,
                    height: 280,
                    decoration: const BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                  // White Circle (inner cutout)
                  Container(
                    width: 240,
                    height: 240,
                    decoration: const BoxDecoration(
                      color: AppColors.backgroundWhite,
                      shape: BoxShape.circle,
                    ),
                  ),
                  // Green Dots on Ring
                  Positioned(
                    right: 0,
                    top: 20,
                    child: Container(
                      width: 16,
                      height: 16,
                      decoration: const BoxDecoration(
                        color: AppColors.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    bottom: 20,
                    child: Container(
                      width: 16,
                      height: 16,
                      decoration: const BoxDecoration(
                        color: AppColors.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            
            // Inner Circle Background - White
            Container(
              width: 240,
              height: 240,
              decoration: const BoxDecoration(
                color: AppColors.backgroundWhite,
                shape: BoxShape.circle,
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Inner Dotted Line
                  SizedBox(
                    width: 220,
                    height: 220,
                    child: CustomPaint(
                      painter: DottedCirclePainter(
                        color: AppColors.textHint.withOpacity(0.3),
                        strokeWidth: 1.5,
                        dashWidth: 4,
                        dashSpace: 3,
                      ),
                    ),
                  ),
                  
                  // Content
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Stethoscope Icon
                      const Icon(
                        Icons.medical_services,
                        size: 56,
                        color: AppColors.textPrimary,
                      ),
                      
                      const SizedBox(height: 16),
                      
                      // Title "ปรึกษา"
                      Text(
                        'ปรึกษา',
                        style: AppTextStyles.heading3.copyWith(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      
                      const SizedBox(height: 6),
                      
                      // Subtitle "แพทย์ & เภสัช"
                      RichText(
                        textAlign: TextAlign.center,
                        text: TextSpan(
                          style: AppTextStyles.bodyMedium.copyWith(
                            color: AppColors.textPrimary,
                          ),
                          children: [
                            const TextSpan(text: 'แพทย์ '),
                            TextSpan(
                              text: '&',
                              style: AppTextStyles.bodyMedium.copyWith(
                                color: AppColors.textSecondary,
                              ),
                            ),
                            const TextSpan(text: ' เภสัช'),
                          ],
                        ),
                      ),
                      
                      const SizedBox(height: 12),
                      
                      // Status "พร้อมให้บริการขณะนี้"
                      Text(
                        'พร้อมให้บริการขณะนี้',
                        style: AppTextStyles.caption.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                      
                      const SizedBox(height: 8),
                      
                      // Count
                      widget.useRealtime && widget.availableCount == null
                        ? StreamBuilder<Map<String, int>>(
                            stream: UserRepository(Supabase.instance.client).watchOnlineProviderCounts(),
                            builder: (context, snapshot) {
                              final onlineCount = snapshot.hasData 
                                ? snapshot.data!.values.fold<int>(0, (a, b) => a + b)
                                : _count;
                                
                              return _buildOnlineCount(onlineCount);
                            }
                          )
                        : _buildOnlineCount(_count),
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

  Widget _buildOnlineCount(int onlineCount) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: onlineCount > 0 ? AppColors.success : AppColors.textHint,
            shape: BoxShape.circle,
            boxShadow: onlineCount > 0 ? [
              BoxShadow(
                color: AppColors.success.withOpacity(0.4),
                blurRadius: 4,
                spreadRadius: 1,
              )
            ] : null,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          '$onlineCount ราย',
          style: AppTextStyles.bodySmall.copyWith(
            color: onlineCount > 0 ? AppColors.success : AppColors.textSecondary,
            fontWeight: onlineCount > 0 ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ],
    );
  }
}
