import 'package:flutter/material.dart';

class ViewerCountWidget extends StatelessWidget {
  final String formattedViewerCount;
  final int viewerCount;

  const ViewerCountWidget({
    super.key,
    required this.formattedViewerCount,
    this.viewerCount = 0,
  });

  double get _maxY {
    if (viewerCount == 0) return 10;
    int digits = viewerCount.toString().length;
    double multiplier = 10;
    for (int i = 1; i < digits; i++) multiplier *= 10;
    double max = ((viewerCount / (multiplier / 10)).ceil() * (multiplier / 10));
    return max <= viewerCount ? max + (multiplier / 10) : max;
  }

  @override
  Widget build(BuildContext context) {
    const orange = Color(0xFFFF6B35);

    return LayoutBuilder(
      builder: (context, constraints) {
        final double leftBoxWidth = 50.0;
        // คำนวณความกว้างสูงสุดของกราฟที่เหลือ
        final double maxBarWidth = constraints.maxWidth - leftBoxWidth;
        final double percentage = _maxY == 0 ? 0 : (viewerCount / _maxY).clamp(0.0, 1.0);
        
        // ให้มีความกว้างพอแสดงข้อความ "กำลังรับชม" เป็นค่าต่ำสุด
        final double minBarWidth = 60.0; 
        double currentBarWidth = viewerCount == 0 ? minBarWidth : maxBarWidth * percentage;
        if (currentBarWidth < minBarWidth) {
          currentBarWidth = minBarWidth;
        }

        return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // 1. Left Box: กล่องแสดงตัวเลขยอดรับชม
            ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(4),
                bottomLeft: Radius.circular(4),
              ),
              child: Container(
                width: leftBoxWidth,
                padding: const EdgeInsets.symmetric(vertical: 2),
                decoration: BoxDecoration(
                  color: orange.withOpacity(0.85),
                  border: Border.all(color: Colors.white.withOpacity(0.2)),
                ),
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // ใช้ข้อความล่องหน บังคับให้ความสูงของกล่องนี้เท่ากับปุ่มอื่นๆ
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
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            '$formattedViewerCount ราย',
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

            // กราฟแท่งข้อความ (มัดรวมกันเพื่อให้สูงเท่ากันเป๊ะ)
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 2. กราฟแท่ง
                  Container(
                    width: currentBarWidth,
                    padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 6),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [orange.withOpacity(0.7), orange],
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                      ),
                      borderRadius: const BorderRadius.only(
                        topRight: Radius.circular(12),
                        bottomRight: Radius.circular(12),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: orange.withOpacity(0.5),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    alignment: Alignment.centerLeft,
                    child: const FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        'กำลังรับชม',
                        maxLines: 1,
                        style: TextStyle(
                          fontFamily: 'SukhumvitSet',
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
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
