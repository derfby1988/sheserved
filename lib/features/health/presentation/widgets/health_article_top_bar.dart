import 'dart:ui';
import 'package:flutter/material.dart';
import '../../../../shared/widgets/widgets.dart';

/// Top navigation bar for the health article page (Area 1).
/// Shows search bar or sticky article title when scrolled.
class HealthArticleTopBar extends StatelessWidget {
  final bool showStickyTitle;
  final String? articleTitle;

  const HealthArticleTopBar({
    super.key,
    required this.showStickyTitle,
    this.articleTitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: TlzAppTopBar.onPrimary(
        notificationCategory: 'health',
        onCartTap: () => ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ตะกร้าสินค้าจะเปิดใช้งานเร็วๆ นี้')),
        ),
        middle: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: showStickyTitle && articleTitle != null
              ? Container(
                  key: const ValueKey('sticky_title'),
                  padding: const EdgeInsets.only(left: 8),
                  alignment: Alignment.centerLeft,
                  child: Text(
                    articleTitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                )
              : TlzAnimatedSearchBar.onPrimary(
                  key: const ValueKey('search_bar'),
                  hintText: 'ค้นหายา ร้านยา หมอ...',
                  onQRTap: () => ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('QR Scanner จะเปิดใช้งานเร็วๆ นี้'),
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}

/// Control bar with section navigation buttons (Area 2).
class HealthArticleControlBar extends StatelessWidget {
  final String activeSection;
  final VoidCallback onArticleTap;
  final VoidCallback onProductsTap;
  final VoidCallback onCommentsTap;
  final VoidCallback onBookmarksTap;

  const HealthArticleControlBar({
    super.key,
    required this.activeSection,
    required this.onArticleTap,
    required this.onProductsTap,
    required this.onCommentsTap,
    required this.onBookmarksTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      height: 44,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: Colors.white.withOpacity(0.2),
                width: 1,
              ),
            ),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(
                    Icons.arrow_back,
                    color: Colors.white,
                    size: 20,
                  ),
                  onPressed: () => Navigator.pop(context),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  constraints: const BoxConstraints(),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    reverse: true,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        _buildNavButton(
                          'หัวข้อ',
                          activeSection == 'article',
                          onTap: onArticleTap,
                        ),
                        _buildNavButton(
                          'สินค้า',
                          activeSection == 'products',
                          onTap: onProductsTap,
                        ),
                        _buildNavButton(
                          'ความคิดเห็น',
                          activeSection == 'comments',
                          onTap: onCommentsTap,
                        ),
                        _buildNavButton(
                          'ที่บันทึกไว้',
                          activeSection == 'bookmarks',
                          onTap: onBookmarksTap,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavButton(String label, bool isActive, {VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isActive ? Colors.white.withOpacity(0.3) : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isActive ? Colors.white : Colors.white.withOpacity(0.6),
            fontSize: 12,
            fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
            fontFamily: 'SukhumvitSet',
          ),
        ),
      ),
    );
  }
}
