import 'package:flutter/material.dart';
import 'dart:ui';

class ThaiMhungPhoto {
  final String id;
  final String url;
  final String? userName;

  ThaiMhungPhoto({required this.id, required this.url, this.userName});
}

// ============================================================
// ThaiMhungGalleryWidget
// แสดงรูปในช่วง [currentPage-2 ... currentPage ... currentPage+2]
// ตามแผน §4 Thai Mhung: "แสดงรูปตัวอย่างข้างซ้าย/ขวาสูงสุด 2 รูป"
// Ellipsis (..) แสดงเมื่อมีรูปที่อยู่นอก window ด้านซ้ายหรือขวา
// ============================================================
class ThaiMhungGalleryWidget extends StatefulWidget {
  final List<ThaiMhungPhoto> photos;
  final Function(ThaiMhungPhoto) onPhotoTap;
  /// true = ผู้ใช้มีสิทธิ์เห็นภาพต้นฉบับ (ไม่เบลอ)
  /// false (default) = แสดง Face Blur overlay
  final bool canViewUnblurred;

  /// จำนวนรูปที่แสดงแต่ละด้านรอบ currentPage (ตาม spec = 2)
  static const int windowRadius = 2;

  const ThaiMhungGalleryWidget({
    super.key,
    required this.photos,
    required this.onPhotoTap,
    this.canViewUnblurred = false,
  });

  @override
  State<ThaiMhungGalleryWidget> createState() => _ThaiMhungGalleryWidgetState();
}

class _ThaiMhungGalleryWidgetState extends State<ThaiMhungGalleryWidget> {
  late PageController _pageController;
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _currentPage = widget.photos.length ~/ 2;
    _pageController = PageController(
      initialPage: _currentPage,
      viewportFraction: 0.35,
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  /// ✅ visible window: แสดงเฉพาะ index ในช่วง ±windowRadius รอบ currentPage
  List<({ThaiMhungPhoto photo, int originalIndex})> get _visiblePhotos {
    final r = ThaiMhungGalleryWidget.windowRadius;
    final start = (_currentPage - r).clamp(0, widget.photos.length - 1);
    final end = (_currentPage + r).clamp(0, widget.photos.length - 1);
    return [
      for (int i = start; i <= end; i++)
        (photo: widget.photos[i], originalIndex: i),
    ];
  }

  /// มีรูปนอก window ทางซ้ายหรือไม่
  bool get _hasMoreLeft => _currentPage > ThaiMhungGalleryWidget.windowRadius;

  /// มีรูปนอก window ทางขวาหรือไม่
  bool get _hasMoreRight =>
      _currentPage < widget.photos.length - 1 - ThaiMhungGalleryWidget.windowRadius;

  @override
  Widget build(BuildContext context) {
    if (widget.photos.isEmpty) return const SizedBox.shrink();

    final visible = _visiblePhotos;
    final itemWidth = MediaQuery.of(context).size.width * 0.25;

    return Container(
      height: 120,
      width: double.infinity,
      alignment: Alignment.bottomCenter,
      padding: const EdgeInsets.only(bottom: 20),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Glassmorphism background
          Container(
            height: 90,
            width: MediaQuery.of(context).size.width * 0.9,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white24),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: const SizedBox.expand(),
              ),
            ),
          ),

          // ✅ แสดงเฉพาะรูปใน visible window ±2 รอบ currentPage
          SizedBox(
            height: 110,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Left Ellipsis - แสดงเมื่อมีรูปที่ซ่อนอยู่ทางซ้าย
                if (_hasMoreLeft) _buildEllipsis(onTap: () {
                  _pageController.animateToPage(
                    (_currentPage - ThaiMhungGalleryWidget.windowRadius - 1).clamp(0, widget.photos.length - 1),
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                  );
                }),

                // รูปที่อยู่ใน visible window เท่านั้น
                ...visible.map((item) {
                  final isSelected = item.originalIndex == _currentPage;
                  return AnimatedScale(
                    scale: isSelected ? 1.1 : 0.8,
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOutBack,
                    child: SizedBox(
                      width: itemWidth,
                      child: GestureDetector(
                        onTap: () {
                          if (isSelected) {
                            widget.onPhotoTap(item.photo);
                          } else {
                            _pageController.animateToPage(
                              item.originalIndex,
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeInOut,
                            );
                          }
                        },
                        child: Hero(
                          tag: 'thai_mhung_photo_${item.photo.id}',
                          child: Stack(
                            children: [
                              // Base image
                              Container(
                                margin: const EdgeInsets.symmetric(horizontal: 4),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: isSelected ? Colors.blue : Colors.white38,
                                    width: isSelected ? 2 : 1,
                                  ),
                                  boxShadow: [
                                    if (isSelected)
                                      BoxShadow(
                                        color: Colors.blue.withValues(alpha: 0.4),
                                        blurRadius: 10,
                                        spreadRadius: 2,
                                      ),
                                  ],
                                  image: DecorationImage(
                                    image: NetworkImage(item.photo.url),
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              ),
                              // Face blur overlay — แสดงเมื่อไม่มีสิทธิ์เห็นต้นฉบับ
                              if (!widget.canViewUnblurred)
                                Positioned.fill(
                                  child: _FaceBlurOverlay(),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }),

                // Right Ellipsis - แสดงเมื่อมีรูปที่ซ่อนอยู่ทางขวา
                if (_hasMoreRight) _buildEllipsis(onTap: () {
                  _pageController.animateToPage(
                    (_currentPage + ThaiMhungGalleryWidget.windowRadius + 1).clamp(0, widget.photos.length - 1),
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                  );
                }),
              ],
            ),
          ),

          // PageController listener — invisible, รับ swipe gesture จากผู้ใช้
          Positioned.fill(
            child: PageView.builder(
              controller: _pageController,
              itemCount: widget.photos.length,
              onPageChanged: (index) => setState(() => _currentPage = index),
              itemBuilder: (_, __) => const SizedBox.shrink(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEllipsis({VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Text(
          '..',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}

/// Simulated Face Blur Overlay
/// ใช้ BackdropFilter + CustomPainter เพื่อทำ Bokeh-style blur บริเวณหน้าคน
/// ในระบบ Production จะส่งภาพผ่าน MediaPipe บน Server แทน
class _FaceBlurOverlay extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Stack(
        children: [
          // Full blur layer หลัก (Gaussian Blur สม่ำเสมอ)
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
            child: Container(color: Colors.transparent),
          ),
          // Privacy icon + label
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.face_retouching_off, color: Colors.white70, size: 16),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'ซ่อนภาพ',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 8,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
