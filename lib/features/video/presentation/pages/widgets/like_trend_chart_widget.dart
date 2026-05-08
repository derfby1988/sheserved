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

    return LayoutBuilder(
      builder: (context, constraints) {
        final double buttonWidth = 32.0;
        final double leftBoxWidth = 50.0;
        // คำนวณความกว้างสูงสุดของกราฟที่เหลือ
        final double maxBarWidth = constraints.maxWidth - leftBoxWidth - buttonWidth;
        final double percentage = _maxY == 0 ? 0 : (likeCount / _maxY).clamp(0.0, 1.0);
        final double currentBarWidth = likeCount == 0 ? 0.0 : maxBarWidth * percentage;

        return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center, // ปล่อยให้ตรงกลาง (กราฟและปุ่มจะเตี้ยกว่ากล่องซ้ายตามที่ต้องการ)
          children: [
            // 1. Left Box: กล่องแสดงตัวเลขยอดไลค์
            ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(4),
                bottomLeft: Radius.circular(4),
              ),
              child: Container(
                width: leftBoxWidth,
                padding: const EdgeInsets.symmetric(vertical: 2), // Padding ต้นฉบับเหมือนปุ่ม "ให้ทาง"
                decoration: BoxDecoration(
                  color: isLiked
                      ? orange.withOpacity(0.85)
                      : const Color(0xFF6B7280).withOpacity(0.8),
                  border: Border.all(color: Colors.white.withOpacity(0.2)),
                ),
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // 🌟 ใช้ข้อความดัมมี่ล่องหน เพื่อบังคับให้ความสูงของกล่องนี้เท่ากับกล่อง "ให้ทาง" แบบเป๊ะๆ
                          // เพราะเวลา FittedBox หดตัวอักษร มันจะหดความสูงด้วย ทำให้กล่องเตี้ยลง
                          const Visibility(
                            maintainSize: true,
                            maintainAnimation: true,
                            maintainState: true,
                            visible: false,
                            child: Text(
                              '0',
                              style: TextStyle(
                                fontFamily: 'SukhumvitSet',
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          // ตัวหนังสือที่หดขนาดได้
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              '$likeCountFormatted คน', // เติมคำว่า คน
                              style: const TextStyle(
                                fontFamily: 'SukhumvitSet',
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // กราฟแท่ง และ ปุ่มกด Like (มัดรวมกันเพื่อให้สูงเท่ากันเป๊ะ)
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 2. กราฟแท่ง
                  Container(
                    width: currentBarWidth,
                    padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [orange.withOpacity(0.7), orange],
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                      ),
                    ),
                    alignment: Alignment.centerLeft,
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

                  // 3. ปุ่มกด Like (ติดกับปลายกราฟ)
                  GestureDetector(
                    onTap: onToggleLike,
                    child: Container(
                      width: buttonWidth,
                      padding: const EdgeInsets.symmetric(vertical: 2),
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
              ),
            ),
          ],
        );
      },
    );
  }
}
