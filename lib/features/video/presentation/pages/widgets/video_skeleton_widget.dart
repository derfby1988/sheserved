import 'package:flutter/material.dart';
import 'dart:math' as math;

/// Skeleton Loading Widget สำหรับ Video Player
/// แสดงแทนขณะกำลังโหลด Metadata หรือรอ HLS พร้อม
class VideoSkeletonWidget extends StatefulWidget {
  /// แสดงแบบ Card เล็กสำหรับ Trending Panel
  final bool isTrendingCard;

  const VideoSkeletonWidget({super.key, this.isTrendingCard = false});

  @override
  State<VideoSkeletonWidget> createState() => _VideoSkeletonWidgetState();
}

class _VideoSkeletonWidgetState extends State<VideoSkeletonWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _shimmerController;
  late Animation<double> _shimmerAnimation;

  @override
  void initState() {
    super.initState();
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();

    _shimmerAnimation = Tween<double>(begin: -2, end: 2).animate(
      CurvedAnimation(parent: _shimmerController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _shimmerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.isTrendingCard
        ? _buildTrendingCardSkeleton()
        : _buildFullPlayerSkeleton();
  }

  Widget _buildShimmerBox({
    required double width,
    required double height,
    double borderRadius = 8,
  }) {
    return AnimatedBuilder(
      animation: _shimmerAnimation,
      builder: (context, child) {
        return Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(borderRadius),
            gradient: LinearGradient(
              begin: Alignment(-1.0 + _shimmerAnimation.value * 0.3, 0),
              end: Alignment(1.0 + _shimmerAnimation.value * 0.3, 0),
              colors: const [
                Color(0xFF2A2A2A),
                Color(0xFF3A3A3A),
                Color(0xFF4A4A4A),
                Color(0xFF3A3A3A),
                Color(0xFF2A2A2A),
              ],
              stops: const [0.0, 0.25, 0.5, 0.75, 1.0],
              transform: GradientRotation(_shimmerAnimation.value * math.pi * 0.1),
            ),
          ),
        );
      },
    );
  }

  // Skeleton แบบ Card เล็กสำหรับ Trending Panel
  Widget _buildTrendingCardSkeleton() {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A2A),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildShimmerBox(width: double.infinity, height: 14, borderRadius: 4),
            const SizedBox(height: 6),
            _buildShimmerBox(width: 80, height: 11, borderRadius: 4),
          ],
        ),
      ),
    );
  }

  // Skeleton แบบ Full Player สำหรับหน้าหลัก
  Widget _buildFullPlayerSkeleton() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Video player area
        _buildShimmerBox(
          width: double.infinity,
          height: 200,
          borderRadius: 16,
        ),
        const SizedBox(height: 12),
        // Viewer count row
        Row(
          children: [
            _buildShimmerBox(width: 20, height: 20, borderRadius: 10),
            const SizedBox(width: 8),
            _buildShimmerBox(width: 60, height: 14, borderRadius: 4),
          ],
        ),
        const SizedBox(height: 12),
        // Action buttons row
        Row(
          children: [
            _buildShimmerBox(width: 70, height: 36, borderRadius: 18),
            const SizedBox(width: 8),
            _buildShimmerBox(width: 70, height: 36, borderRadius: 18),
            const SizedBox(width: 8),
            _buildShimmerBox(width: 70, height: 36, borderRadius: 18),
          ],
        ),
      ],
    );
  }
}

/// Skeleton สำหรับ Status Badge (กำลัง Processing)
class VideoProcessingBadge extends StatefulWidget {
  final String message;
  const VideoProcessingBadge({super.key, this.message = 'กำลังประมวลผลวิดีโอ...'});

  @override
  State<VideoProcessingBadge> createState() => _VideoProcessingBadgeState();
}

class _VideoProcessingBadgeState extends State<VideoProcessingBadge>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.7, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _pulseAnim,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.orange.withOpacity(0.9),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.orange.withOpacity(0.4),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              widget.message,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
