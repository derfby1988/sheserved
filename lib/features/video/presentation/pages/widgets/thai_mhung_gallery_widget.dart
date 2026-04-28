import 'package:flutter/material.dart';

class ThaiMhungPhoto {
  final String id;
  final String url;
  final String? userName;

  ThaiMhungPhoto({required this.id, required this.url, this.userName});
}

class ThaiMhungGalleryWidget extends StatefulWidget {
  final List<ThaiMhungPhoto> photos;
  final Function(ThaiMhungPhoto) onPhotoTap;
  final bool canViewUnblurred;

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

  List<({ThaiMhungPhoto photo, int originalIndex})> get _visiblePhotos {
    final r = ThaiMhungGalleryWidget.windowRadius;
    final start = (_currentPage - r).clamp(0, widget.photos.length - 1);
    final end = (_currentPage + r).clamp(0, widget.photos.length - 1);
    return [
      for (int i = start; i <= end; i++)
        (photo: widget.photos[i], originalIndex: i),
    ];
  }

  bool get _hasMoreLeft => _currentPage > ThaiMhungGalleryWidget.windowRadius;

  bool get _hasMoreRight =>
      _currentPage < widget.photos.length - 1 - ThaiMhungGalleryWidget.windowRadius;

  @override
  Widget build(BuildContext context) {
    if (widget.photos.isEmpty) return const SizedBox.shrink();

    final visible = _visiblePhotos;

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
              color: Colors.black.withOpacity(0.2),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white24),
            ),
          ),

          // Photos Row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_hasMoreLeft) _buildEllipsis(onTap: () {
                  _pageController.animateToPage(
                    (_currentPage - ThaiMhungGalleryWidget.windowRadius - 1).clamp(0, widget.photos.length - 1),
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                  );
                }),

                ...visible.map((item) {
                  final isSelected = item.originalIndex == _currentPage;
                  return Expanded(
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
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isSelected ? Colors.blue : Colors.white38,
                              width: isSelected ? 2 : 1,
                            ),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Stack(
                              children: [
                                Positioned.fill(
                                  // ✅ แสดงภาพตรงๆ: ใบหน้าถูกเบลอโดย Server (deface) มาแล้ว
                                  child: Image.network(
                                    item.photo.url,
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) => Container(
                                      color: Colors.grey[900],
                                      child: const Icon(Icons.broken_image, color: Colors.white24),
                                    ),
                                  ),
                                ),
                                // 🛡️ Badge แจ้งว่าใบหน้าถูกปกป้องโดย Server-side Face Blur
                                Positioned(
                                  bottom: 3,
                                  right: 3,
                                  child: Container(
                                    padding: const EdgeInsets.all(2),
                                    decoration: BoxDecoration(
                                      color: Colors.black54,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Icon(Icons.face_retouching_off, color: Colors.white70, size: 10),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }),

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

          // PageController listener
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
