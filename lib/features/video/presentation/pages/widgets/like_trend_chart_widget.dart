import 'package:flutter/material.dart';

class LikeTrendChartWidget extends StatelessWidget {
  final bool isLiked;
  final int likeCount;
  final String likeCountFormatted;
  final VoidCallback onToggleLike;

  const LikeTrendChartWidget({
    super.key,
    required this.isLiked,
    required this.likeCount,
    required this.likeCountFormatted,
    required this.onToggleLike,
  });

  double get _maxY {
    if (likeCount == 0) return 10;
    int digits = likeCount.toString().length;
    double multiplier = 10;
    for (int i = 1; i < digits; i++) multiplier *= 10;
    double max = ((likeCount / (multiplier / 10)).ceil() * (multiplier / 10));
    return max <= likeCount ? max + (multiplier / 10) : max;
  }

  @override
  Widget build(BuildContext context) {
    const orange = Color(0xFFFF6B35);

    return SizedBox(
      height: 26, // ความสูงให้สอดคล้องกับปุ่มอื่นๆ
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Left Box: กล่องแสดงตัวเลขยอดไลค์
          ClipRRect(
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(4),
              bottomLeft: Radius.circular(4),
            ),
            child: Container(
              width: 50,
              decoration: BoxDecoration(
                color: isLiked
                    ? orange.withOpacity(0.85)
                    : const Color(0xFF6B7280).withOpacity(0.8),
                border: Border.all(color: Colors.white.withOpacity(0.2)),
              ),
              child: Center(
                child: Text(
                  likeCountFormatted,
                  style: const TextStyle(
                    fontFamily: 'SukhumvitSet',
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),

          // 2. Graph & Button Area
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final double buttonWidth = 32.0;
                final double maxBarWidth = constraints.maxWidth - buttonWidth;
                final double percentage = _maxY == 0 ? 0 : (likeCount / _maxY).clamp(0.0, 1.0);
                final double currentBarWidth = likeCount == 0 ? 0.0 : maxBarWidth * percentage;

                return Row(
                  children: [
                    // กราฟแท่ง
                    Container(
                      width: currentBarWidth,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [orange.withOpacity(0.7), orange],
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                        ),
                      ),
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: likeCount >= 1
                          ? FittedBox(
                              fit: BoxFit.scaleDown,
                              child: const Text(
                                'ส่งกำลังใจ',
                                maxLines: 1,
                                style: TextStyle(
                                  fontFamily: 'SukhumvitSet',
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),

                    // ปุ่มกด Like (ติดกับปลายกราฟ)
                    GestureDetector(
                      onTap: onToggleLike,
                      child: Container(
                        width: buttonWidth,
                        decoration: BoxDecoration(
                          color: isLiked ? orange : const Color(0xFF6B7280).withOpacity(0.8),
                          borderRadius: const BorderRadius.only(
                            topRight: Radius.circular(12),
                            bottomRight: Radius.circular(12),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: isLiked
                                  ? orange.withOpacity(0.5)
                                  : Colors.black.withOpacity(0.2),
                              blurRadius: isLiked ? 8 : 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Center(
                          child: Icon(
                            isLiked
                                ? Icons.favorite_rounded
                                : Icons.favorite_border_rounded,
                            color: Colors.white,
                            size: 14,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
