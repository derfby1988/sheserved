import 'package:flutter/material.dart';
import 'dart:ui';

class ThaiMhungPhoto {
  final String id;
  final String url;
  final String? userName;

  ThaiMhungPhoto({required this.id, required this.url, this.userName});
}

class ThaiMhungGalleryWidget extends StatefulWidget {
  final List<ThaiMhungPhoto> photos;
  final Function(ThaiMhungPhoto) onPhotoTap;

  const ThaiMhungGalleryWidget({
    super.key,
    required this.photos,
    required this.onPhotoTap,
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

  @override
  Widget build(BuildContext context) {
    if (widget.photos.isEmpty) return const SizedBox.shrink();

    return Container(
      height: 120,
      width: double.infinity,
      alignment: Alignment.bottomCenter,
      padding: const EdgeInsets.only(bottom: 20),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Glassmorphism background for the gallery area
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
          
          // PageView for photos
          SizedBox(
            height: 110,
            child: PageView.builder(
              controller: _pageController,
              itemCount: widget.photos.length,
              onPageChanged: (index) => setState(() => _currentPage = index),
              itemBuilder: (context, index) {
                final photo = widget.photos[index];
                final bool isSelected = index == _currentPage;
                
                return AnimatedScale(
                  scale: isSelected ? 1.1 : 0.8,
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOutBack,
                  child: GestureDetector(
                    onTap: () {
                      if (isSelected) {
                        widget.onPhotoTap(photo);
                      } else {
                        _pageController.animateToPage(
                          index,
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeInOut,
                        );
                      }
                    },
                    child: Hero(
                      tag: 'thai_mhung_photo_${photo.id}',
                      child: Container(
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
                            image: NetworkImage(photo.url),
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          
          // Left Ellipsis indicator
          if (_currentPage > 2)
            Positioned(
              left: 30,
              child: _buildEllipsis(),
            ),
            
          // Right Ellipsis indicator
          if (_currentPage < widget.photos.length - 3)
            Positioned(
              right: 30,
              child: _buildEllipsis(),
            ),
        ],
      ),
    );
  }

  Widget _buildEllipsis() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Text(
        '..',
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
      ),
    );
  }
}
